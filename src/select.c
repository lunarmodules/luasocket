/*=========================================================================*\
* Select implementation
* RCS ID: $Id$
\*=========================================================================*/
#include <string.h>

#include <lua.h>
#include <lauxlib.h>

#include "luasocket.h"
#include "socket.h"
#include "auxiliar.h"
#include "select.h"

static int meth_set(lua_State *L);
static int meth_isset(lua_State *L);
static int c_select(lua_State *L);
static int global_select(lua_State *L);
static void check_obj_tab(lua_State *L, int tabidx);

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

void select_open(lua_State *L)
{
    /* get select auxiliar lua function from lua code and register
    * pass it as an upvalue to global_select */
#ifdef LUASOCKET_COMPILED
#include "select.lch"
#else
    lua_dofile(L, "select.lua");
#endif
    luaL_openlib(L, LUASOCKET_LIBNAME, func, 1);
    lua_pop(L, 1);
    aux_newclass(L, "select{fd_set}", set);
}

/*-------------------------------------------------------------------------*\
* Waits for a set of sockets until a condition is met or timeout.
\*-------------------------------------------------------------------------*/
static int global_select(lua_State *L)
{
    fd_set *read_fd_set, *write_fd_set;
    /* make sure we have enough arguments (nil is the default) */
    lua_settop(L, 3);
    /* check object tables */
    check_obj_tab(L, 1);
    check_obj_tab(L, 2); 
    /* check timeout */
    if (!lua_isnil(L, 3) && !lua_isnumber(L, 3))
        luaL_argerror(L, 3, "number or nil expected");
    /* select auxiliar lua function to be called comes first */
    lua_pushvalue(L, lua_upvalueindex(1)); 
    lua_insert(L, 1);
    /* pass fd_set objects */
    read_fd_set = lua_newuserdata(L, sizeof(fd_set)); 
    FD_ZERO(read_fd_set);
    aux_setclass(L, "select{fd_set}", -1);
    write_fd_set = lua_newuserdata(L, sizeof(fd_set)); 
    FD_ZERO(write_fd_set);
    aux_setclass(L, "select{fd_set}", -1);
    /* pass select auxiliar C function */
    lua_pushcfunction(L, c_select);
    /* call select auxiliar lua function */
    lua_call(L, 6, 3);
    return 3;
}

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

static void check_obj_tab(lua_State *L, int tabidx)
{
    if (tabidx < 0) tabidx = lua_gettop(L) + tabidx + 1;
    if (lua_istable(L, tabidx)) {
        lua_pushnil(L);
        while (lua_next(L, tabidx) != 0) {
            if (aux_getgroupudata(L, "select{able}", -1) == NULL) {
                char msg[45];
                if (lua_isnumber(L, -2))
                    sprintf(msg, "table entry #%g is invalid", 
                            lua_tonumber(L, -2));
                else
                    sprintf(msg, "invalid entry found in table");
                luaL_argerror(L, tabidx, msg);
            }
            lua_pop(L, 1);
        }
    } else if (!lua_isnil(L, tabidx))
        luaL_argerror(L, tabidx, "table or nil expected");
}
