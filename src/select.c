/*=========================================================================*\
* Select implementation
* Global Lua fuctions:
*   select: waits until socket ready
* RCS ID: $Id$
\*=========================================================================*/
#include <string.h>
#include <lua.h>
#include <lauxlib.h>

#include "luasocket.h"
#include "lspriv.h"
#include "lsselect.h"
#include "lsfd.h"

/* auxiliar functions */
static int local_select(lua_State *L);
static int local_getfd(lua_State *L);
static int local_pending(lua_State *L);
static int local_FD_SET(lua_State *L);
static int local_FD_ISSET(lua_State *L);

static int select_lua_select(lua_State *L);

/*-------------------------------------------------------------------------*\
* Marks type as selectable
* Input
*   name: type name
\*-------------------------------------------------------------------------*/
void select_addclass(lua_State *L, cchar *lsclass)
{
    lua_pushstring(L, "luasocket(select)");
    lua_gettable(L, LUA_REGISTRYINDEX);
    lua_pushstring(L, lsclass);
    lua_pushnumber(L, 1);
    lua_settable(L, -3);
    lua_pop(L, 1);
}

void select_open(lua_State *L)
{
    /* push select auxiliar lua function and register
    * select_lua_select with it as an upvalue */
#ifdef LUASOCKET_DOFILE
    lua_dofile(L, "lsselect.lua");
#else
#include "lsselect.loh"
#endif
    lua_getglobal(L, LUASOCKET_LIBNAME);
    lua_pushstring(L, "_select");
    lua_gettable(L, -2);
    lua_pushcclosure(L, select_lua_select, 1);
    priv_newglobal(L, "select");
    lua_pop(L, 1);
    /* create luasocket(select) table */
    lua_pushstring(L, "luasocket(select)");
    lua_newtable(L);
    lua_settable(L, LUA_REGISTRYINDEX);
}

/*-------------------------------------------------------------------------*\
* Waits for a set of sockets until a condition is met or timeout.
* Lua Input: {input}, {output} [, timeout]
*   {input}: table of sockets to be tested for input
*   {output}: table of sockets to be tested for output
*   timeout: maximum amount of time to wait for condition, in seconds
* Lua Returns: {input}, {output}, err
*   {input}: table with sockets ready for input
*   {output}: table with sockets ready for output
*   err: "timeout" or nil
\*-------------------------------------------------------------------------*/
static int select_lua_select(lua_State *L)
{
    fd_set read, write;
    FD_ZERO(&read);
    FD_ZERO(&write);
    /* push select lua auxiliar function */
    lua_pushvalue(L, lua_upvalueindex(1)); lua_insert(L, 1);
    /* make sure we have enough arguments (nil is the default) */
    lua_settop(L, 4);
    /* pass FD_SET and manipulation functions */
    lua_boxpointer(L, &read);
    lua_boxpointer(L, &write);
    lua_pushcfunction(L, local_FD_SET);
    lua_pushcfunction(L, local_FD_ISSET);
    /* pass getfd function with selectable table as upvalue */
    lua_pushstring(L, "luasocket(select)"); lua_gettable(L, LUA_REGISTRYINDEX);
    lua_pushcclosure(L, local_getfd, 1);
    /* pass pending function */
    lua_pushstring(L, "luasocket(select)"); lua_gettable(L, LUA_REGISTRYINDEX);
    lua_pushcclosure(L, local_pending, 1);
    /* pass select auxiliar C function */
    lua_pushcfunction(L, local_select);
    /* call select auxiliar lua function */
    lua_call(L, 10, 3);
    return 3;
}

static int local_getfd(lua_State *L)
{
    priv_pushclass(L, 1);
    lua_gettable(L, lua_upvalueindex(1));
    if (!lua_isnil(L, -1)) {
        p_fd sock = (p_fd) lua_touserdata(L, 1);
        lua_pushnumber(L, sock->fd);
    }
    return 1;
}

static int local_pending(lua_State *L)
{
    priv_pushclass(L, 1);
    lua_gettable(L, lua_upvalueindex(1));
    if (!lua_isnil(L, -1)) {
        p_fd sock = (p_fd) lua_touserdata(L, 1);
        if (sock->fd_pending(L, sock)) lua_pushnumber(L, 1);
        else lua_pushnil(L);
    }
    return 1;
}

static int local_select(lua_State *L)
{
    int max_fd = (int) lua_tonumber(L, 1);
    fd_set *read_set = (fd_set *) lua_touserdata(L, 2);
    fd_set *write_set = (fd_set *) lua_touserdata(L, 3);
    int deadline = lua_isnil(L, 4) ? -1 : (int)(lua_tonumber(L, 4) * 1000);
    struct timeval tv;
    if (deadline >= 0) {
        tv.tv_sec = deadline / 1000;
        tv.tv_usec = (deadline % 1000) * 1000;
        lua_pushnumber(L, select(max_fd, read_set, write_set, NULL, &tv));
    } else {
        lua_pushnumber(L, select(max_fd, read_set, write_set, NULL, NULL));
    }
    return 1;
}

static int local_FD_SET(lua_State *L)
{
    COMPAT_FD fd = (COMPAT_FD) lua_tonumber(L, 1);
    fd_set *set = (fd_set *) lua_topointer(L, 2);
    if (fd >= 0) FD_SET(fd, set);
    return 0;
}

static int local_FD_ISSET(lua_State *L)
{
    COMPAT_FD fd = (COMPAT_FD) lua_tonumber(L, 1);
    fd_set *set = (fd_set *) lua_topointer(L, 2);
    if (fd >= 0 && FD_ISSET(fd, set)) lua_pushnumber(L, 1);
    else lua_pushnil(L);
    return 1;
}
