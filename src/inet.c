/*=========================================================================*\
* Internet domain functions
* LuaSocket toolkit
*
* RCS ID: $Id$
\*=========================================================================*/
#include <stdio.h>
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

/* DNS functions */
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
    lua_pushstring(L, LUASOCKET_LIBNAME);
    lua_gettable(L, LUA_GLOBALSINDEX);
    if (lua_isnil(L, -1)) {
        lua_pop(L, 1);
        lua_newtable(L);
        lua_pushstring(L, LUASOCKET_LIBNAME);
        lua_pushvalue(L, -2);
        lua_settable(L, LUA_GLOBALSINDEX);
    }
    lua_pushstring(L, "dns");
    lua_newtable(L);
    luaL_openlib(L, NULL, func, 0);
    lua_settable(L, -3);
    lua_pop(L, 1);
}

/*=========================================================================*\
* Global Lua functions
\*=========================================================================*/
/*-------------------------------------------------------------------------*\
* Returns all information provided by the resolver given a host name
* or ip address
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
\*-------------------------------------------------------------------------*/
int inet_meth_getpeername(lua_State *L, p_sock ps)
{
    struct sockaddr_in peer;
    socklen_t peer_len = sizeof(peer);
    if (getpeername(*ps, (SA *) &peer, &peer_len) < 0) {
        lua_pushnil(L);
        lua_pushstring(L, "getpeername failed");
    } else {
        lua_pushstring(L, inet_ntoa(peer.sin_addr));
        lua_pushnumber(L, ntohs(peer.sin_port));
    }
    return 2;
}

/*-------------------------------------------------------------------------*\
* Retrieves socket local name
\*-------------------------------------------------------------------------*/
int inet_meth_getsockname(lua_State *L, p_sock ps)
{
    struct sockaddr_in local;
    socklen_t local_len = sizeof(local);
    if (getsockname(*ps, (SA *) &local, &local_len) < 0) {
        lua_pushnil(L);
        lua_pushstring(L, "getsockname failed");
    } else {
        lua_pushstring(L, inet_ntoa(local.sin_addr));
        lua_pushnumber(L, ntohs(local.sin_port));
    }
    return 2;
}

/*=========================================================================*\
* Internal functions
\*=========================================================================*/
/*-------------------------------------------------------------------------*\
* Passes all resolver information to Lua as a table
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
* Tries to create a new inet socket
\*-------------------------------------------------------------------------*/
const char *inet_trycreate(p_sock ps, int type)
{
    return sock_create(ps, AF_INET, type, 0);
}

/*-------------------------------------------------------------------------*\
* Tries to connect to remote address (address, port)
\*-------------------------------------------------------------------------*/
const char *inet_tryconnect(p_sock ps, const char *address, 
        unsigned short port, p_tm tm)
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
            if (!hp) return sock_hoststrerror();
            addr = (struct in_addr **) hp->h_addr_list;
            memcpy(&remote.sin_addr, *addr, sizeof(struct in_addr));
        }
    } else remote.sin_family = AF_UNSPEC;
    err = sock_connect(ps, (SA *) &remote, sizeof(remote), tm);
    if (err) sock_destroy(ps);
    return err;
}

/*-------------------------------------------------------------------------*\
* Tries to bind socket to (address, port)
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
        return err; 
    } else {
        sock_setnonblocking(ps);
        if (backlog >= 0) sock_listen(ps, backlog);
        return NULL;
    }
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


