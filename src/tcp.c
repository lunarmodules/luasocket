/*=========================================================================*\
* TCP object 
*
* RCS ID: $Id$
\*=========================================================================*/
#include <string.h> 

#include <lua.h>
#include <lauxlib.h>

#include "luasocket.h"

#include "aux.h"
#include "inet.h"
#include "tcp.h"

/*=========================================================================*\
* Internal function prototypes
\*=========================================================================*/
static int tcp_global_create(lua_State *L);
static int tcp_meth_connect(lua_State *L);
static int tcp_meth_bind(lua_State *L);
static int tcp_meth_send(lua_State *L);
static int tcp_meth_getsockname(lua_State *L);
static int tcp_meth_getpeername(lua_State *L);
static int tcp_meth_receive(lua_State *L);
static int tcp_meth_accept(lua_State *L);
static int tcp_meth_close(lua_State *L);
static int tcp_meth_timeout(lua_State *L);

/* tcp object methods */
static luaL_reg tcp[] = {
    {"connect",     tcp_meth_connect},
    {"send",        tcp_meth_send},
    {"receive",     tcp_meth_receive},
    {"bind",        tcp_meth_bind},
    {"accept",      tcp_meth_accept},
    {"setpeername", tcp_meth_connect},
    {"setsockname", tcp_meth_bind},
    {"getpeername", tcp_meth_getpeername},
    {"getsockname", tcp_meth_getsockname},
    {"timeout",     tcp_meth_timeout},
    {"close",       tcp_meth_close},
    {NULL,          NULL}
};

/* functions in library namespace */
static luaL_reg func[] = {
    {"tcp", tcp_global_create},
    {NULL, NULL}
};

/*-------------------------------------------------------------------------*\
* Initializes module
\*-------------------------------------------------------------------------*/
void tcp_open(lua_State *L)
{
    /* create classes */
    aux_newclass(L, "tcp{master}", tcp);
    aux_newclass(L, "tcp{client}", tcp);
    aux_newclass(L, "tcp{server}", tcp);
    /* create class groups */
    aux_add2group(L, "tcp{client}", "tcp{client, server}");
    aux_add2group(L, "tcp{server}", "tcp{client, server}");
    aux_add2group(L, "tcp{master}", "tcp{any}");
    aux_add2group(L, "tcp{client}", "tcp{any}");
    aux_add2group(L, "tcp{server}", "tcp{any}");
    /* define library functions */
    luaL_openlib(L, LUASOCKET_LIBNAME, func, 0); 
    lua_pop(L, 1);
}

/*=========================================================================*\
* Lua methods
\*=========================================================================*/
/*-------------------------------------------------------------------------*\
* Just call buffered IO methods
\*-------------------------------------------------------------------------*/
static int tcp_meth_send(lua_State *L)
{
    p_tcp tcp = (p_tcp) aux_checkclass(L, "tcp{client}", 1);
    return buf_meth_send(L, &tcp->buf);
}

static int tcp_meth_receive(lua_State *L)
{
    p_tcp tcp = (p_tcp) aux_checkclass(L, "tcp{client}", 1);
    return buf_meth_receive(L, &tcp->buf);
}

/*-------------------------------------------------------------------------*\
* Just call inet methods
\*-------------------------------------------------------------------------*/
static int tcp_meth_getpeername(lua_State *L)
{
    p_tcp tcp = (p_tcp) aux_checkclass(L, "tcp{client}", 1);
    return inet_meth_getpeername(L, &tcp->sock);
}

static int tcp_meth_getsockname(lua_State *L)
{
    p_tcp tcp = (p_tcp) aux_checkgroup(L, "tcp{client, server}", 1);
    return inet_meth_getsockname(L, &tcp->sock);
}

/*-------------------------------------------------------------------------*\
* Just call tm methods
\*-------------------------------------------------------------------------*/
static int tcp_meth_timeout(lua_State *L)
{
    p_tcp tcp = (p_tcp) aux_checkgroup(L, "tcp{any}", 1);
    return tm_meth_timeout(L, &tcp->tm);
}

/*-------------------------------------------------------------------------*\
* Closes socket used by object 
\*-------------------------------------------------------------------------*/
static int tcp_meth_close(lua_State *L)
{
    p_tcp tcp = (p_tcp) aux_checkgroup(L, "tcp{any}", 1);
    sock_destroy(&tcp->sock);
    return 0;
}

/*-------------------------------------------------------------------------*\
* Turns a master tcp object into a client object.
\*-------------------------------------------------------------------------*/
static int tcp_meth_connect(lua_State *L)
{
    p_tcp tcp = (p_tcp) aux_checkclass(L, "tcp{master}", 1);
    const char *address =  luaL_checkstring(L, 2);
    unsigned short port = (ushort) luaL_checknumber(L, 3);
    const char *err = inet_tryconnect(&tcp->sock, address, port);
    if (err) {
        lua_pushnil(L);
        lua_pushstring(L, err);
        return 2;
    }
    /* turn master object into a client object */
    aux_setclass(L, "tcp{client}", 1);
    lua_pushnumber(L, 1);
    return 1;
}

/*-------------------------------------------------------------------------*\
* Turns a master object into a server object
\*-------------------------------------------------------------------------*/
static int tcp_meth_bind(lua_State *L)
{
    p_tcp tcp = (p_tcp) aux_checkclass(L, "tcp{master}", 1);
    const char *address =  luaL_checkstring(L, 2);
    unsigned short port = (ushort) luaL_checknumber(L, 3);
    int backlog = (int) luaL_optnumber(L, 4, 1);
    const char *err = inet_trybind(&tcp->sock, address, port, backlog);
    if (err) {
        lua_pushnil(L);
        lua_pushstring(L, err);
        return 2;
    }
    /* turn master object into a server object */
    aux_setclass(L, "tcp{server}", 1);
    lua_pushnumber(L, 1);
    return 1;
}

/*-------------------------------------------------------------------------*\
* Waits for and returns a client object attempting connection to the 
* server object 
\*-------------------------------------------------------------------------*/
static int tcp_meth_accept(lua_State *L)
{
    struct sockaddr_in addr;
    size_t addr_len = sizeof(addr);
    p_tcp server = (p_tcp) aux_checkclass(L, "tcp{server}", 1);
    p_tm tm = &server->tm;
    p_tcp client = lua_newuserdata(L, sizeof(t_tcp));
    tm_markstart(tm);
    aux_setclass(L, "tcp{client}", -1);
    for ( ;; ) {
        sock_accept(&server->sock, &client->sock, 
            (SA *) &addr, &addr_len, tm_get(tm));
        if (client->sock == SOCK_INVALID) {
           if (tm_get(tm) == 0) {
                lua_pushnil(L);
                error_push(L, IO_TIMEOUT);
                return 2;
           }
        } else break;
    }
    /* initialize remaining structure fields */
    io_init(&client->io, (p_send) sock_send, (p_recv) sock_recv, &client->sock);
    tm_init(&client->tm, -1, -1);
    buf_init(&client->buf, &client->io, &client->tm);
    return 1;
}

/*=========================================================================*\
* Library functions
\*=========================================================================*/
/*-------------------------------------------------------------------------*\
* Creates a master tcp object 
\*-------------------------------------------------------------------------*/
int tcp_global_create(lua_State *L)
{
    /* allocate tcp object */
    p_tcp tcp = (p_tcp) lua_newuserdata(L, sizeof(t_tcp));
    /* set its type as master object */
    aux_setclass(L, "tcp{master}", -1);
    /* try to allocate a system socket */
    const char *err = inet_trycreate(&tcp->sock, SOCK_STREAM);
    if (err) { /* get rid of object on stack and push error */
        lua_pop(L, 1);
        lua_pushnil(L);
        lua_pushstring(L, err);
        return 2;
    }
    /* initialize remaining structure fields */
    io_init(&tcp->io, (p_send) sock_send, (p_recv) sock_recv, &tcp->sock);
    tm_init(&tcp->tm, -1, -1);
    buf_init(&tcp->buf, &tcp->io, &tcp->tm);
    return 1;
}
