/*=========================================================================*\
* Internet domain class: inherits from the Socket class, and implement
* a few methods shared by all internet related objects
* Lua methods:
*   getpeername: gets socket peer ip address and port
*   getsockname: gets local socket ip address and port
* Global Lua fuctions:
*   toip: gets resolver info on host name
*   tohostname: gets resolver info on dotted-quad
*
* RCS ID: $Id$
\*=========================================================================*/
#include <string.h>

#include <lua.h>
#include <lauxlib.h>

#include "lsinet.h"
#include "lssock.h"
#include "lscompat.h"

/*=========================================================================*\
* Internal function prototypes.
\*=========================================================================*/
static int inet_lua_toip(lua_State *L);
static int inet_lua_tohostname(lua_State *L);
static int inet_lua_getpeername(lua_State *L);
static int inet_lua_getsockname(lua_State *L);
static void inet_pushresolved(lua_State *L, struct hostent *hp);

#ifdef COMPAT_INETATON
static int inet_aton(cchar *cp, struct in_addr *inp);
#endif

/*=========================================================================*\
* Exported functions
\*=========================================================================*/
/*-------------------------------------------------------------------------*\
* Initializes module
\*-------------------------------------------------------------------------*/
void inet_open(lua_State *L)
{
    lua_pushcfunction(L, inet_lua_toip);
    priv_newglobal(L, "toip");
    lua_pushcfunction(L, inet_lua_tohostname);
    priv_newglobal(L, "tohostname");
    priv_newglobalmethod(L, "getsockname");
    priv_newglobalmethod(L, "getpeername");
}

/*-------------------------------------------------------------------------*\
* Hook lua methods to methods table.
* Input
*   lsclass: class name
\*-------------------------------------------------------------------------*/
void inet_inherit(lua_State *L, cchar *lsclass)
{
    unsigned int i;
    static struct luaL_reg funcs[] = {
        {"getsockname", inet_lua_getsockname},
        {"getpeername", inet_lua_getpeername},
    };
    sock_inherit(L, lsclass);
    for (i = 0; i < sizeof(funcs)/sizeof(funcs[0]); i++) {
        lua_pushcfunction(L, funcs[i].func);
        priv_setmethod(L, lsclass, funcs[i].name);
    }
}

/*-------------------------------------------------------------------------*\
* Constructs the object 
\*-------------------------------------------------------------------------*/
void inet_construct(lua_State *L, p_inet inet)
{
    sock_construct(L, (p_sock) inet);
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
static int inet_lua_toip(lua_State *L)
{
    cchar *address = luaL_checkstring(L, 1);
    struct in_addr addr;
    struct hostent *hp;
    if (inet_aton(address, &addr))
        hp = gethostbyaddr((char *) &addr, sizeof(addr), AF_INET);
    else hp = gethostbyname(address);
    if (!hp) {
        lua_pushnil(L);
        lua_pushstring(L, compat_hoststrerror());
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
static int inet_lua_tohostname(lua_State *L)
{
    cchar *address = luaL_checkstring(L, 1);
    struct in_addr addr;
    struct hostent *hp;
    if (inet_aton(address, &addr))
        hp = gethostbyaddr((char *) &addr, sizeof(addr), AF_INET);
    else hp = gethostbyname(address);
    if (!hp) {
        lua_pushnil(L);
        lua_pushstring(L, compat_hoststrerror());
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
* Lua Input: sock 
*   sock: socket
* Lua Returns
*   On success: ip address and port of peer
*   On error: nil
\*-------------------------------------------------------------------------*/
static int inet_lua_getpeername(lua_State *L)
{
    p_sock sock = (p_sock) lua_touserdata(L, 1);
    struct sockaddr_in peer;
    size_t peer_len = sizeof(peer);
    if (getpeername(sock->fd, (SA *) &peer, &peer_len) < 0) {
        lua_pushnil(L);
        return 1;
    }
    lua_pushstring(L, inet_ntoa(peer.sin_addr));
    lua_pushnumber(L, ntohs(peer.sin_port));
    return 2;
}

/*-------------------------------------------------------------------------*\
* Retrieves socket local name
* Lua Input: sock 
*   sock: socket
* Lua Returns
*   On success: local ip address and port
*   On error: nil
\*-------------------------------------------------------------------------*/
static int inet_lua_getsockname(lua_State *L)
{
    p_sock sock = (p_sock) lua_touserdata(L, 1);
    struct sockaddr_in local;
    size_t local_len = sizeof(local);
    if (getsockname(sock->fd, (SA *) &local, &local_len) < 0) {
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
* Tries to create a TCP socket and connect to remote address (address, port)
* Input
*   client: socket structure to be used
*   address: host name or ip address
*   port: port number to bind to
* Returns
*   NULL in case of success, error message otherwise
\*-------------------------------------------------------------------------*/
cchar *inet_tryconnect(p_inet inet, cchar *address, ushort port)
{
    struct sockaddr_in remote;
    memset(&remote, 0, sizeof(remote));
    remote.sin_family = AF_INET;
    remote.sin_port = htons(port);
    if (!strlen(address) || !inet_aton(address, &remote.sin_addr)) {
        struct hostent *hp = gethostbyname(address);
        struct in_addr **addr;
        if (!hp) return compat_hoststrerror();
        addr = (struct in_addr **) hp->h_addr_list;
        memcpy(&remote.sin_addr, *addr, sizeof(struct in_addr));
    }
    compat_setblocking(inet->fd);
    if (compat_connect(inet->fd, (SA *) &remote, sizeof(remote)) < 0) {
        const char *err = compat_connectstrerror();
        compat_close(inet->fd);
        inet->fd = COMPAT_INVALIDFD;
        return err;
    } 
    compat_setnonblocking(inet->fd);
    return NULL;
}

/*-------------------------------------------------------------------------*\
* Tries to create a TCP socket and bind it to (address, port)
* Input
*   address: host name or ip address
*   port: port number to bind to
* Returns
*   NULL in case of success, error message otherwise
\*-------------------------------------------------------------------------*/
cchar *inet_trybind(p_inet inet, cchar *address, ushort port)
{
    struct sockaddr_in local;
    memset(&local, 0, sizeof(local));
    /* address is either wildcard or a valid ip address */
    local.sin_addr.s_addr = htonl(INADDR_ANY);
    local.sin_port = htons(port);
    local.sin_family = AF_INET;
    if (strcmp(address, "*") && 
            (!strlen(address) || !inet_aton(address, &local.sin_addr))) {
        struct hostent *hp = gethostbyname(address);
        struct in_addr **addr;
        if (!hp) return compat_hoststrerror();
        addr = (struct in_addr **) hp->h_addr_list;
        memcpy(&local.sin_addr, *addr, sizeof(struct in_addr));
    }
    compat_setblocking(inet->fd);
    if (compat_bind(inet->fd, (SA *) &local, sizeof(local)) < 0) {
        const char *err = compat_bindstrerror();
        compat_close(inet->fd);
        inet->fd = COMPAT_INVALIDFD;
        return err;
    }
    compat_setnonblocking(inet->fd);
    return NULL;
}

/*-------------------------------------------------------------------------*\
* Tries to create a new inet socket
* Input
*   udp: udp structure
* Returns
*   NULL if successfull, error message on error
\*-------------------------------------------------------------------------*/
cchar *inet_trysocket(p_inet inet, int type)
{
    if (inet->fd != COMPAT_INVALIDFD) compat_close(inet->fd);
    inet->fd = compat_socket(AF_INET, type, 0);
    if (inet->fd == COMPAT_INVALIDFD) return compat_socketstrerror();
    else return NULL;
}

/*-------------------------------------------------------------------------*\
* Some systems do not provide this so that we provide our own. It's not
* marvelously fast, but it works just fine.
\*-------------------------------------------------------------------------*/
#ifdef COMPAT_INETATON
static int inet_aton(const char *cp, struct in_addr *inp)
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
