/*=========================================================================*\
* Select implementation
* LuaSocket toolkit
*
* RCS ID: $Id$
\*=========================================================================*/
#include <string.h>

#include <lua.h>
#include <lauxlib.h>

#include "luasocket.h"
#include "socket.h"
#include "auxiliar.h"
#include "select.h"

/*=========================================================================*\
* Internal function prototypes.
\*=========================================================================*/
static int meth_set(lua_State *L);
static int meth_isset(lua_State *L);
static int c_select(lua_State *L);
static int global_select(lua_State *L);

/* fd_set object methods */
static luaL_reg set[] = {
    {"set",    meth_set},
    {"isset",  meth_isset},
    {NULL,     NULL}
};

/* functions in library namespace */
static luaL_reg func[] = {
    {"select", global_select},
    {NULL,     NULL}
};

/*=========================================================================*\
* Internal function prototypes.
\*=========================================================================*/
/*-------------------------------------------------------------------------*\
* Initializes module
\*-------------------------------------------------------------------------*/
int select_open(lua_State *L)
{
    /* get select auxiliar lua function from lua code and register
    * pass it as an upvalue to global_select */
#ifdef LUASOCKET_COMPILED
#include "select.lch"
#else
    lua_dofile(L, "select.lua");
#endif
    luaL_openlib(L, NULL, func, 1);
    aux_newclass(L, "select{fd_set}", set);
    return 0;
}

/*=========================================================================*\
* Global Lua functions
\*=========================================================================*/
/*-------------------------------------------------------------------------*\
* Waits for a set of sockets until a condition is met or timeout.
\*-------------------------------------------------------------------------*/
static int global_select(lua_State *L)
{
    fd_set *read_fd_set, *write_fd_set;
    /* make sure we have enough arguments (nil is the default) */
    lua_settop(L, 3);
    /* check timeout */
    if (!lua_isnil(L, 3) && !lua_isnumber(L, 3))
        luaL_argerror(L, 3, "number or nil expected");
    /* select auxiliar lua function to be called comes first */
    lua_pushvalue(L, lua_upvalueindex(1)); 
    lua_insert(L, 1);
    /* pass fd_set objects */
    read_fd_set = (fd_set *) lua_newuserdata(L, sizeof(fd_set)); 
    FD_ZERO(read_fd_set);
    aux_setclass(L, "select{fd_set}", -1);
    write_fd_set = (fd_set *) lua_newuserdata(L, sizeof(fd_set)); 
    FD_ZERO(write_fd_set);
    aux_setclass(L, "select{fd_set}", -1);
    /* pass select auxiliar C function */
    lua_pushcfunction(L, c_select);
    /* call select auxiliar lua function */
    lua_call(L, 6, 3);
    return 3;
}

/*=========================================================================*\
* Lua methods
\*=========================================================================*/
static int meth_set(lua_State *L)
{
    fd_set *set = (fd_set *) aux_checkclass(L, "select{fd_set}", 1);
    t_sock fd = (t_sock) lua_tonumber(L, 2);
    if (fd >= 0) FD_SET(fd, set);
    return 0;
}

static int meth_isset(lua_State *L)
{
    fd_set *set = (fd_set *) aux_checkclass(L, "select{fd_set}", 1);
    t_sock fd = (t_sock) lua_tonumber(L, 2);
    if (fd >= 0 && FD_ISSET(fd, set)) lua_pushnumber(L, 1);
    else lua_pushnil(L);
    return 1;
}

/*=========================================================================*\
* Internal functions
\*=========================================================================*/
static int c_select(lua_State *L)
{
    int max_fd = (int) lua_tonumber(L, 1);
    fd_set *read_fd_set = (fd_set *) aux_checkclass(L, "select{fd_set}", 2);
    fd_set *write_fd_set = (fd_set *) aux_checkclass(L, "select{fd_set}", 3);
    int timeout = lua_isnil(L, 4) ? -1 : (int)(lua_tonumber(L, 4) * 1000);
    struct timeval tv;
    tv.tv_sec = timeout / 1000;
    tv.tv_usec = (timeout % 1000) * 1000;
    lua_pushnumber(L, select(max_fd, read_fd_set, write_fd_set, NULL, 
                timeout < 0 ? NULL : &tv));
    return 1;
}
