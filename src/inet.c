/*=========================================================================*\
* Internet domain functions
*
* RCS ID: $Id$
\*=========================================================================*/
#include <string.h>

#include <lua.h>
#include <lauxlib.h>

#include "luasocket.h"
#include "inet.h"

/*=========================================================================*\
* Internal function prototypes.
\*=========================================================================*/
static int inet_global_toip(lua_State *L);
static int inet_global_tohostname(lua_State *L);

static void inet_pushresolved(lua_State *L, struct hostent *hp);

static luaL_reg func[] = {
    { "toip", inet_global_toip },
    { "tohostname", inet_global_tohostname },
    { NULL, NULL}
};

/*=========================================================================*\
* Exported functions
\*=========================================================================*/
/*-------------------------------------------------------------------------*\
* Initializes module
\*-------------------------------------------------------------------------*/
void inet_open(lua_State *L)
{
    luaL_openlib(L, LUASOCKET_LIBNAME, func, 0);
    lua_pop(L, 1);
}

/*=========================================================================*\
* Global Lua functions
\*=========================================================================*/
/*-------------------------------------------------------------------------*\
* Returns all information provided by the resolver given a host name
* or ip address
* Lua Input: address
*   address: ip address or hostname to dns lookup
* Lua Returns
*   On success: first IP address followed by a resolved table
*   On error: nil, followed by an error message
\*-------------------------------------------------------------------------*/
static int inet_global_toip(lua_State *L)
{
    const char *address = luaL_checkstring(L, 1);
    struct in_addr addr;
    struct hostent *hp;
    if (inet_aton(address, &addr))
        hp = gethostbyaddr((char *) &addr, sizeof(addr), AF_INET);
    else 
        hp = gethostbyname(address);
    if (!hp) {
        lua_pushnil(L);
        lua_pushstring(L, sock_hoststrerror());
        return 2;
    }
    addr = *((struct in_addr *) hp->h_addr);
    lua_pushstring(L, inet_ntoa(addr));
    inet_pushresolved(L, hp);
    return 2;
}

/*-------------------------------------------------------------------------*\
* Returns all information provided by the resolver given a host name
* or ip address
* Lua Input: address
*   address: ip address or host name to reverse dns lookup
* Lua Returns
*   On success: canonic name followed by a resolved table
*   On error: nil, followed by an error message
\*-------------------------------------------------------------------------*/
static int inet_global_tohostname(lua_State *L)
{
    const char *address = luaL_checkstring(L, 1);
    struct in_addr addr;
    struct hostent *hp;
    if (inet_aton(address, &addr))
        hp = gethostbyaddr((char *) &addr, sizeof(addr), AF_INET);
    else 
        hp = gethostbyname(address);
    if (!hp) {
        lua_pushnil(L);
        lua_pushstring(L, sock_hoststrerror());
        return 2;
    }
    lua_pushstring(L, hp->h_name);
    inet_pushresolved(L, hp);
    return 2;
}

/*=========================================================================*\
* Lua methods
\*=========================================================================*/
/*-------------------------------------------------------------------------*\
* Retrieves socket peer name
* Input: 
*   sock: socket
* Lua Returns
*   On success: ip address and port of peer
*   On error: nil
\*-------------------------------------------------------------------------*/
int inet_meth_getpeername(lua_State *L, p_sock ps)
{
    struct sockaddr_in peer;
    socklen_t peer_len = sizeof(peer);
    if (getpeername(*ps, (SA *) &peer, &peer_len) < 0) {
        lua_pushnil(L);
        return 1;
    }
    lua_pushstring(L, inet_ntoa(peer.sin_addr));
    lua_pushnumber(L, ntohs(peer.sin_port));
    return 2;
}

/*-------------------------------------------------------------------------*\
* Retrieves socket local name
* Input:
*   sock: socket
* Lua Returns
*   On success: local ip address and port
*   On error: nil
\*-------------------------------------------------------------------------*/
int inet_meth_getsockname(lua_State *L, p_sock ps)
{
    struct sockaddr_in local;
    socklen_t local_len = sizeof(local);
    if (getsockname(*ps, (SA *) &local, &local_len) < 0) {
        lua_pushnil(L);
        return 1;
    }
    lua_pushstring(L, inet_ntoa(local.sin_addr));
    lua_pushnumber(L, ntohs(local.sin_port));
    return 2;
}

/*=========================================================================*\
* Internal functions
\*=========================================================================*/
/*-------------------------------------------------------------------------*\
* Passes all resolver information to Lua as a table
* Input
*   hp: hostent structure returned by resolver
\*-------------------------------------------------------------------------*/
static void inet_pushresolved(lua_State *L, struct hostent *hp)
{
    char **alias;
    struct in_addr **addr;
    int i, resolved;
    lua_newtable(L); resolved = lua_gettop(L);
    lua_pushstring(L, "name");
    lua_pushstring(L, hp->h_name);
    lua_settable(L, resolved);
    lua_pushstring(L, "ip");
    lua_pushstring(L, "alias");
    i = 1;
    alias = hp->h_aliases;
    lua_newtable(L);
    while (*alias) {
        lua_pushnumber(L, i);
        lua_pushstring(L, *alias);
        lua_settable(L, -3);
        i++; alias++;
    }
    lua_settable(L, resolved);
    i = 1;
    lua_newtable(L);
    addr = (struct in_addr **) hp->h_addr_list;
    while (*addr) {
        lua_pushnumber(L, i);
        lua_pushstring(L, inet_ntoa(**addr));
        lua_settable(L, -3);
        i++; addr++;
    }
    lua_settable(L, resolved);
}

/*-------------------------------------------------------------------------*\
* Tries to connect to remote address (address, port)
* Input
*   ps: pointer to socket 
*   address: host name or ip address
*   port: port number to bind to
* Returns
*   NULL in case of success, error message otherwise
\*-------------------------------------------------------------------------*/
const char *inet_tryconnect(p_sock ps, const char *address, 
        unsigned short port)
{
    struct sockaddr_in remote;
    const char *err;
    memset(&remote, 0, sizeof(remote));
    remote.sin_family = AF_INET;
    remote.sin_port = htons(port);
    if (strcmp(address, "*")) {
        if (!strlen(address) || !inet_aton(address, &remote.sin_addr)) {
            struct hostent *hp = gethostbyname(address);
            struct in_addr **addr;
            remote.sin_family = AF_INET;
            if (!hp) return sock_hoststrerror();
            addr = (struct in_addr **) hp->h_addr_list;
            memcpy(&remote.sin_addr, *addr, sizeof(struct in_addr));
        }
    } else remote.sin_family = AF_UNSPEC;
    sock_setblocking(ps);
    err = sock_connect(ps, (SA *) &remote, sizeof(remote));
    if (err) {
        sock_destroy(ps);
        *ps = SOCK_INVALID;
        return err;
    } else {
        sock_setnonblocking(ps);
        return NULL;
    }
}

/*-------------------------------------------------------------------------*\
* Tries to bind socket to (address, port)
* Input
*   sock: pointer to socket
*   address: host name or ip address
*   port: port number to bind to
* Returns
*   NULL in case of success, error message otherwise
\*-------------------------------------------------------------------------*/
const char *inet_trybind(p_sock ps, const char *address, unsigned short port, 
        int backlog)
{
    struct sockaddr_in local;
    const char *err;
    memset(&local, 0, sizeof(local));
    /* address is either wildcard or a valid ip address */
    local.sin_addr.s_addr = htonl(INADDR_ANY);
    local.sin_port = htons(port);
    local.sin_family = AF_INET;
    if (strcmp(address, "*") && 
            (!strlen(address) || !inet_aton(address, &local.sin_addr))) {
        struct hostent *hp = gethostbyname(address);
        struct in_addr **addr;
        if (!hp) return sock_hoststrerror();
        addr = (struct in_addr **) hp->h_addr_list;
        memcpy(&local.sin_addr, *addr, sizeof(struct in_addr));
    }
    sock_setblocking(ps);
    err = sock_bind(ps, (SA *) &local, sizeof(local));
    if (err) {
        sock_destroy(ps);
        *ps = SOCK_INVALID;
        return err;
    } else {
        sock_setnonblocking(ps);
        if (backlog > 0) sock_listen(ps, backlog);
        return NULL;
    }
}

/*-------------------------------------------------------------------------*\
* Tries to create a new inet socket
* Input
*   sock: pointer to socket
* Returns
*   NULL if successfull, error message on error
\*-------------------------------------------------------------------------*/
const char *inet_trycreate(p_sock ps, int type)
{
    return sock_create(ps, AF_INET, type, 0);
}

/*-------------------------------------------------------------------------*\
* Some systems do not provide this so that we provide our own. It's not
* marvelously fast, but it works just fine.
\*-------------------------------------------------------------------------*/
#ifdef INET_ATON
int inet_aton(const char *cp, struct in_addr *inp)
{
    unsigned int a = 0, b = 0, c = 0, d = 0;
    int n = 0, r;
    unsigned long int addr = 0;
    r = sscanf(cp, "%u.%u.%u.%u%n", &a, &b, &c, &d, &n);
    if (r == 0 || n == 0) return 0;
    cp += n;
    if (*cp) return 0;
    if (a > 255 || b > 255 || c > 255 || d > 255) return 0;
    if (inp) {
        addr += a; addr <<= 8;
        addr += b; addr <<= 8;
        addr += c; addr <<= 8;
        addr += d;
        inp->s_addr = htonl(addr);
    }
    return 1;
}
#endif
