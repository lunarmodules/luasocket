/*=========================================================================*\
* TCP object 
* LuaSocket toolkit
*
* RCS ID: $Id$
\*=========================================================================*/
#include <string.h> 

#include <lua.h>
#include <lauxlib.h>

#include "auxiliar.h"
#include "socket.h"
#include "inet.h"
#include "options.h"
#include "tcp.h"

/*=========================================================================*\
* Internal function prototypes
\*=========================================================================*/
static int global_create(lua_State *L);
static int meth_connect(lua_State *L);
static int meth_listen(lua_State *L);
static int meth_bind(lua_State *L);
static int meth_send(lua_State *L);
static int meth_getstats(lua_State *L);
static int meth_setstats(lua_State *L);
static int meth_getsockname(lua_State *L);
static int meth_getpeername(lua_State *L);
static int meth_shutdown(lua_State *L);
static int meth_receive(lua_State *L);
static int meth_accept(lua_State *L);
static int meth_close(lua_State *L);
static int meth_setoption(lua_State *L);
static int meth_settimeout(lua_State *L);
static int meth_getfd(lua_State *L);
static int meth_setfd(lua_State *L);
static int meth_dirty(lua_State *L);

/* tcp object methods */
static luaL_reg tcp[] = {
    {"__gc",        meth_close},
    {"__tostring",  aux_tostring},
    {"accept",      meth_accept},
    {"bind",        meth_bind},
    {"close",       meth_close},
    {"connect",     meth_connect},
    {"dirty",       meth_dirty},
    {"getfd",       meth_getfd},
    {"getpeername", meth_getpeername},
    {"getsockname", meth_getsockname},
    {"getstats",    meth_getstats},
    {"setstats",    meth_setstats},
    {"listen",      meth_listen},
    {"receive",     meth_receive},
    {"send",        meth_send},
    {"setfd",       meth_setfd},
    {"setoption",   meth_setoption},
    {"setpeername", meth_connect},
    {"setsockname", meth_bind},
    {"settimeout",  meth_settimeout},
    {"shutdown",    meth_shutdown},
    {NULL,          NULL}
};

/* socket option handlers */
static t_opt opt[] = {
    {"keepalive",   opt_keepalive},
    {"reuseaddr",   opt_reuseaddr},
    {"tcp-nodelay", opt_tcp_nodelay},
    {"linger",      opt_linger},
    {NULL,          NULL}
};

/* functions in library namespace */
static luaL_reg func[] = {
    {"tcp", global_create},
    {NULL, NULL}
};

/*-------------------------------------------------------------------------*\
* Initializes module
\*-------------------------------------------------------------------------*/
int tcp_open(lua_State *L)
{
    /* create classes */
    aux_newclass(L, "tcp{master}", tcp);
    aux_newclass(L, "tcp{client}", tcp);
    aux_newclass(L, "tcp{server}", tcp);
    /* create class groups */
    aux_add2group(L, "tcp{master}", "tcp{any}");
    aux_add2group(L, "tcp{client}", "tcp{any}");
    aux_add2group(L, "tcp{server}", "tcp{any}");
    /* define library functions */
    luaL_openlib(L, NULL, func, 0); 
    return 0;
}

/*=========================================================================*\
* Lua methods
\*=========================================================================*/
/*-------------------------------------------------------------------------*\
* Just call buffered IO methods
\*-------------------------------------------------------------------------*/
static int meth_send(lua_State *L) {
    p_tcp tcp = (p_tcp) aux_checkclass(L, "tcp{client}", 1);
    return buf_meth_send(L, &tcp->buf);
}

static int meth_receive(lua_State *L) {
    p_tcp tcp = (p_tcp) aux_checkclass(L, "tcp{client}", 1);
    return buf_meth_receive(L, &tcp->buf);
}

static int meth_getstats(lua_State *L) {
    p_tcp tcp = (p_tcp) aux_checkgroup(L, "tcp{any}", 1);
    return buf_meth_getstats(L, &tcp->buf);
}

static int meth_setstats(lua_State *L) {
    p_tcp tcp = (p_tcp) aux_checkgroup(L, "tcp{any}", 1);
    return buf_meth_setstats(L, &tcp->buf);
}

/*-------------------------------------------------------------------------*\
* Just call option handler
\*-------------------------------------------------------------------------*/
static int meth_setoption(lua_State *L)
{
    p_tcp tcp = (p_tcp) aux_checkgroup(L, "tcp{any}", 1);
    return opt_meth_setoption(L, opt, &tcp->sock);
}

/*-------------------------------------------------------------------------*\
* Select support methods
\*-------------------------------------------------------------------------*/
static int meth_getfd(lua_State *L)
{
    p_tcp tcp = (p_tcp) aux_checkgroup(L, "tcp{any}", 1);
    lua_pushnumber(L, (int) tcp->sock);
    return 1;
}

/* this is very dangerous, but can be handy for those that are brave enough */
static int meth_setfd(lua_State *L)
{
    p_tcp tcp = (p_tcp) aux_checkgroup(L, "tcp{any}", 1);
    tcp->sock = (t_sock) luaL_checknumber(L, 2); 
    return 0;
}

static int meth_dirty(lua_State *L)
{
    p_tcp tcp = (p_tcp) aux_checkgroup(L, "tcp{any}", 1);
    lua_pushboolean(L, !buf_isempty(&tcp->buf));
    return 1;
}

/*-------------------------------------------------------------------------*\
* Waits for and returns a client object attempting connection to the 
* server object 
\*-------------------------------------------------------------------------*/
static int meth_accept(lua_State *L)
{
    p_tcp server = (p_tcp) aux_checkclass(L, "tcp{server}", 1);
    p_tm tm = tm_markstart(&server->tm);
    t_sock sock;
    int err = sock_accept(&server->sock, &sock, NULL, NULL, tm);
    /* if successful, push client socket */
    if (err == IO_DONE) {
        p_tcp clnt = (p_tcp) lua_newuserdata(L, sizeof(t_tcp));
        aux_setclass(L, "tcp{client}", -1);
        /* initialize structure fields */
        sock_setnonblocking(&sock);
        clnt->sock = sock;
        io_init(&clnt->io, (p_send) sock_send, (p_recv) sock_recv, 
                (p_error) sock_ioerror, &clnt->sock);
        tm_init(&clnt->tm, -1, -1);
        buf_init(&clnt->buf, &clnt->io, &clnt->tm);
        return 1;
    } else {
        lua_pushnil(L); 
        lua_pushstring(L, sock_strerror(err));
        return 2;
    }
}

/*-------------------------------------------------------------------------*\
* Binds an object to an address 
\*-------------------------------------------------------------------------*/
static int meth_bind(lua_State *L)
{
    p_tcp tcp = (p_tcp) aux_checkclass(L, "tcp{master}", 1);
    const char *address =  luaL_checkstring(L, 2);
    unsigned short port = (unsigned short) luaL_checknumber(L, 3);
    const char *err = inet_trybind(&tcp->sock, address, port);
    if (err) {
        lua_pushnil(L);
        lua_pushstring(L, err);
        return 2;
    }
    lua_pushnumber(L, 1);
    return 1;
}

/*-------------------------------------------------------------------------*\
* Turns a master tcp object into a client object.
\*-------------------------------------------------------------------------*/
static int meth_connect(lua_State *L)
{
    p_tcp tcp = (p_tcp) aux_checkclass(L, "tcp{master}", 1);
    const char *address =  luaL_checkstring(L, 2);
    unsigned short port = (unsigned short) luaL_checknumber(L, 3);
    p_tm tm = tm_markstart(&tcp->tm);
    const char *err = inet_tryconnect(&tcp->sock, address, port, tm);
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
* Closes socket used by object 
\*-------------------------------------------------------------------------*/
static int meth_close(lua_State *L)
{
    p_tcp tcp = (p_tcp) aux_checkgroup(L, "tcp{any}", 1);
    sock_destroy(&tcp->sock);
    lua_pushnumber(L, 1);
    return 1;
}

/*-------------------------------------------------------------------------*\
* Puts the sockt in listen mode
\*-------------------------------------------------------------------------*/
static int meth_listen(lua_State *L)
{
    p_tcp tcp = (p_tcp) aux_checkclass(L, "tcp{master}", 1);
    int backlog = (int) luaL_optnumber(L, 2, 32);
    int err = sock_listen(&tcp->sock, backlog);
    if (err != IO_DONE) {
        lua_pushnil(L);
        lua_pushstring(L, sock_strerror(err));
        return 2;
    }
    /* turn master object into a server object */
    aux_setclass(L, "tcp{server}", 1);
    lua_pushnumber(L, 1);
    return 1;
}

/*-------------------------------------------------------------------------*\
* Shuts the connection down partially
\*-------------------------------------------------------------------------*/
static int meth_shutdown(lua_State *L)
{
    p_tcp tcp = (p_tcp) aux_checkclass(L, "tcp{client}", 1);
    const char *how = luaL_optstring(L, 2, "both");
    switch (how[0]) {
        case 'b':
            if (strcmp(how, "both")) goto error;
            sock_shutdown(&tcp->sock, 2);
            break;
        case 's':
            if (strcmp(how, "send")) goto error;
            sock_shutdown(&tcp->sock, 1);
            break;
        case 'r':
            if (strcmp(how, "receive")) goto error;
            sock_shutdown(&tcp->sock, 0);
            break;
    }
    lua_pushnumber(L, 1);
    return 1;
error:
    luaL_argerror(L, 2, "invalid shutdown method");
    return 0;
}

/*-------------------------------------------------------------------------*\
* Just call inet methods
\*-------------------------------------------------------------------------*/
static int meth_getpeername(lua_State *L)
{
    p_tcp tcp = (p_tcp) aux_checkclass(L, "tcp{client}", 1);
    return inet_meth_getpeername(L, &tcp->sock);
}

static int meth_getsockname(lua_State *L)
{
    p_tcp tcp = (p_tcp) aux_checkgroup(L, "tcp{any}", 1);
    return inet_meth_getsockname(L, &tcp->sock);
}

/*-------------------------------------------------------------------------*\
* Just call tm methods
\*-------------------------------------------------------------------------*/
static int meth_settimeout(lua_State *L)
{
    p_tcp tcp = (p_tcp) aux_checkgroup(L, "tcp{any}", 1);
    return tm_meth_settimeout(L, &tcp->tm);
}

/*=========================================================================*\
* Library functions
\*=========================================================================*/
/*-------------------------------------------------------------------------*\
* Creates a master tcp object 
\*-------------------------------------------------------------------------*/
static int global_create(lua_State *L)
{
    t_sock sock;
    const char *err = inet_trycreate(&sock, SOCK_STREAM);
    /* try to allocate a system socket */
    if (!err) { 
        /* allocate tcp object */
        p_tcp tcp = (p_tcp) lua_newuserdata(L, sizeof(t_tcp));
        /* set its type as master object */
        aux_setclass(L, "tcp{master}", -1);
        /* initialize remaining structure fields */
        sock_setnonblocking(&sock);
        tcp->sock = sock;
        io_init(&tcp->io, (p_send) sock_send, (p_recv) sock_recv, 
                (p_error) sock_ioerror, &tcp->sock);
        tm_init(&tcp->tm, -1, -1);
        buf_init(&tcp->buf, &tcp->io, &tcp->tm);
        return 1;
    } else {
        lua_pushnil(L);
        lua_pushstring(L, err);
        return 2;
    }
}
