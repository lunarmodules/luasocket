/*=========================================================================*\
* Unix domain socket 
* LuaSocket toolkit
*
* RCS ID: $Id$
\*=========================================================================*/
#include <string.h> 

#include <lua.h>
#include <lauxlib.h>

#include "auxiliar.h"
#include "socket.h"
#include "options.h"
#include "unix.h"
#include <sys/un.h> 

/*=========================================================================*\
* Internal function prototypes
\*=========================================================================*/
static int global_create(lua_State *L);
static int meth_connect(lua_State *L);
static int meth_listen(lua_State *L);
static int meth_bind(lua_State *L);
static int meth_send(lua_State *L);
static int meth_shutdown(lua_State *L);
static int meth_receive(lua_State *L);
static int meth_accept(lua_State *L);
static int meth_close(lua_State *L);
static int meth_setoption(lua_State *L);
static int meth_settimeout(lua_State *L);
static int meth_getfd(lua_State *L);
static int meth_setfd(lua_State *L);
static int meth_dirty(lua_State *L);

static const char *unix_tryconnect(p_unix un, const char *path);
static const char *unix_trybind(p_unix un, const char *path);

/* unix object methods */
static luaL_reg un[] = {
    {"__gc",        meth_close},
    {"__tostring",  aux_tostring},
    {"accept",      meth_accept},
    {"bind",        meth_bind},
    {"close",       meth_close},
    {"connect",     meth_connect},
    {"dirty",       meth_dirty},
    {"getfd",       meth_getfd},
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
    {"linger",      opt_linger},
    {NULL,          NULL}
};

/* functions in library namespace */
static luaL_reg func[] = {
    {"unix", global_create},
    {NULL, NULL}
};

/*-------------------------------------------------------------------------*\
* Initializes module
\*-------------------------------------------------------------------------*/
int unix_open(lua_State *L) {
    /* create classes */
    aux_newclass(L, "unix{master}", un);
    aux_newclass(L, "unix{client}", un);
    aux_newclass(L, "unix{server}", un);
    /* create class groups */
    aux_add2group(L, "unix{master}", "unix{any}");
    aux_add2group(L, "unix{client}", "unix{any}");
    aux_add2group(L, "unix{server}", "unix{any}");
    aux_add2group(L, "unix{client}", "unix{client,server}");
    aux_add2group(L, "unix{server}", "unix{client,server}");
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
    p_unix un = (p_unix) aux_checkclass(L, "unix{client}", 1);
    return buf_meth_send(L, &un->buf);
}

static int meth_receive(lua_State *L) {
    p_unix un = (p_unix) aux_checkclass(L, "unix{client}", 1);
    return buf_meth_receive(L, &un->buf);
}

/*-------------------------------------------------------------------------*\
* Just call option handler
\*-------------------------------------------------------------------------*/
static int meth_setoption(lua_State *L) {
    p_unix un = (p_unix) aux_checkgroup(L, "unix{any}", 1);
    return opt_meth_setoption(L, opt, &un->sock);
}

/*-------------------------------------------------------------------------*\
* Select support methods
\*-------------------------------------------------------------------------*/
static int meth_getfd(lua_State *L) {
    p_unix un = (p_unix) aux_checkgroup(L, "unix{any}", 1);
    lua_pushnumber(L, (int) un->sock);
    return 1;
}

/* this is very dangerous, but can be handy for those that are brave enough */
static int meth_setfd(lua_State *L) {
    p_unix un = (p_unix) aux_checkgroup(L, "unix{any}", 1);
    un->sock = (t_sock) luaL_checknumber(L, 2); 
    return 0;
}

static int meth_dirty(lua_State *L) {
    p_unix un = (p_unix) aux_checkgroup(L, "unix{any}", 1);
    lua_pushboolean(L, !buf_isempty(&un->buf));
    return 1;
}

/*-------------------------------------------------------------------------*\
* Waits for and returns a client object attempting connection to the 
* server object 
\*-------------------------------------------------------------------------*/
static int meth_accept(lua_State *L) {
    p_unix server = (p_unix) aux_checkclass(L, "unix{server}", 1);
    p_tm tm = tm_markstart(&server->tm);
    t_sock sock;
    int err = sock_accept(&server->sock, &sock, NULL, NULL, tm);
    /* if successful, push client socket */
    if (err == IO_DONE) {
        p_unix clnt = (p_unix) lua_newuserdata(L, sizeof(t_unix));
        aux_setclass(L, "unix{client}", -1);
        /* initialize structure fields */
        sock_setnonblocking(&sock);
        clnt->sock = sock;
        io_init(&clnt->io, (p_send)sock_send, (p_recv)sock_recv, 
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
static const char *unix_trybind(p_unix un, const char *path) {
    struct sockaddr_un local;
    size_t len = strlen(path);
    int err;
    if (len >= sizeof(local.sun_path)) return "path too long";
    memset(&local, 0, sizeof(local));
    strcpy(local.sun_path, path);
    local.sun_family = AF_UNIX;
#ifdef UNIX_HAS_SUN_LEN
    local.sun_len = sizeof(local.sun_family) + sizeof(local.sun_len) 
        + len + 1;
    err = sock_bind(&un->sock, (SA *) &local, local.sun_len);

#else 
    err = sock_bind(&un->sock, (SA *) &local, 
            sizeof(local.sun_family) + len);
#endif
    if (err != IO_DONE) sock_destroy(&un->sock);
    return sock_strerror(err); 
}

static int meth_bind(lua_State *L) {
    p_unix un = (p_unix) aux_checkclass(L, "unix{master}", 1);
    const char *path =  luaL_checkstring(L, 2);
    const char *err = unix_trybind(un, path);
    if (err) {
        lua_pushnil(L);
        lua_pushstring(L, err);
        return 2;
    }
    lua_pushnumber(L, 1);
    return 1;
}

/*-------------------------------------------------------------------------*\
* Turns a master unix object into a client object.
\*-------------------------------------------------------------------------*/
static const char *unix_tryconnect(p_unix un, const char *path)
{
    struct sockaddr_un remote;
    int err;
    size_t len = strlen(path);
    if (len >= sizeof(remote.sun_path)) return "path too long";
    memset(&remote, 0, sizeof(remote));
    strcpy(remote.sun_path, path);
    remote.sun_family = AF_UNIX;
    tm_markstart(&un->tm);
#ifdef UNIX_HAS_SUN_LEN
    remote.sun_len = sizeof(remote.sun_family) + sizeof(remote.sun_len) 
        + len + 1;
    err = sock_connect(&un->sock, (SA *) &remote, remote.sun_len, &un->tm);
#else
    err = sock_connect(&un->sock, (SA *) &remote, 
            sizeof(remote.sun_family) + len, &un->tm);
#endif
    if (err != IO_DONE) sock_destroy(&un->sock);
    return sock_strerror(err);
}

static int meth_connect(lua_State *L)
{
    p_unix un = (p_unix) aux_checkclass(L, "unix{master}", 1);
    const char *path =  luaL_checkstring(L, 2);
    const char *err = unix_tryconnect(un, path);
    if (err) {
        lua_pushnil(L);
        lua_pushstring(L, err);
        return 2;
    }
    /* turn master object into a client object */
    aux_setclass(L, "unix{client}", 1);
    lua_pushnumber(L, 1);
    return 1;
}

/*-------------------------------------------------------------------------*\
* Closes socket used by object 
\*-------------------------------------------------------------------------*/
static int meth_close(lua_State *L)
{
    p_unix un = (p_unix) aux_checkgroup(L, "unix{any}", 1);
    sock_destroy(&un->sock);
    return 0;
}

/*-------------------------------------------------------------------------*\
* Puts the sockt in listen mode
\*-------------------------------------------------------------------------*/
static int meth_listen(lua_State *L)
{
    p_unix un = (p_unix) aux_checkclass(L, "unix{master}", 1);
    int backlog = (int) luaL_optnumber(L, 2, 32);
    int err = sock_listen(&un->sock, backlog);
    if (err != IO_DONE) {
        lua_pushnil(L);
        lua_pushstring(L, sock_strerror(err));
        return 2;
    }
    /* turn master object into a server object */
    aux_setclass(L, "unix{server}", 1);
    lua_pushnumber(L, 1);
    return 1;
}

/*-------------------------------------------------------------------------*\
* Shuts the connection down partially
\*-------------------------------------------------------------------------*/
static int meth_shutdown(lua_State *L)
{
    p_unix un = (p_unix) aux_checkgroup(L, "unix{client}", 1);
    const char *how = luaL_optstring(L, 2, "both");
    switch (how[0]) {
        case 'b':
            if (strcmp(how, "both")) goto error;
            sock_shutdown(&un->sock, 2);
            break;
        case 's':
            if (strcmp(how, "send")) goto error;
            sock_shutdown(&un->sock, 1);
            break;
        case 'r':
            if (strcmp(how, "receive")) goto error;
            sock_shutdown(&un->sock, 0);
            break;
    }
    lua_pushnumber(L, 1);
    return 1;
error:
    luaL_argerror(L, 2, "invalid shutdown method");
    return 0;
}

/*-------------------------------------------------------------------------*\
* Just call tm methods
\*-------------------------------------------------------------------------*/
static int meth_settimeout(lua_State *L) {
    p_unix un = (p_unix) aux_checkgroup(L, "unix{any}", 1);
    return tm_meth_settimeout(L, &un->tm);
}

/*=========================================================================*\
* Library functions
\*=========================================================================*/
/*-------------------------------------------------------------------------*\
* Creates a master unix object 
\*-------------------------------------------------------------------------*/
static int global_create(lua_State *L) {
    t_sock sock;
    int err = sock_create(&sock, AF_UNIX, SOCK_STREAM, 0);
    /* try to allocate a system socket */
    if (err == IO_DONE) { 
        /* allocate unix object */
        p_unix un = (p_unix) lua_newuserdata(L, sizeof(t_unix));
        /* set its type as master object */
        aux_setclass(L, "unix{master}", -1);
        /* initialize remaining structure fields */
        sock_setnonblocking(&sock);
        un->sock = sock;
        io_init(&un->io, (p_send) sock_send, (p_recv) sock_recv, 
                (p_error) sock_ioerror, &un->sock);
        tm_init(&un->tm, -1, -1);
        buf_init(&un->buf, &un->io, &un->tm);
        return 1;
    } else {
        lua_pushnil(L);
        lua_pushstring(L, sock_strerror(err));
        return 2;
    }
}
