/*=========================================================================*\
* Select implementation
* LuaSocket toolkit
*
* RCS ID: $Id$
\*=========================================================================*/
#include <string.h>

#include <lua.h>
#include <lauxlib.h>

#include "socket.h"
#include "timeout.h"
#include "select.h"

/*=========================================================================*\
* Internal function prototypes.
\*=========================================================================*/
static int getfd(lua_State *L);
static int dirty(lua_State *L);
static int collect_fd(lua_State *L, int tab, int max_fd, int itab, fd_set *set);
static int check_dirty(lua_State *L, int tab, int dtab, fd_set *set);
static void return_fd(lua_State *L, fd_set *set, int max_fd, 
        int itab, int tab, int start);
static void make_assoc(lua_State *L, int tab);
static int global_select(lua_State *L);

/* functions in library namespace */
static luaL_reg func[] = {
    {"select", global_select},
    {NULL,     NULL}
};

/*=========================================================================*\
* Exported functions
\*=========================================================================*/
/*-------------------------------------------------------------------------*\
* Initializes module
\*-------------------------------------------------------------------------*/
int select_open(lua_State *L) {
    luaL_openlib(L, NULL, func, 0);
    return 0;
}

/*=========================================================================*\
* Global Lua functions
\*=========================================================================*/
/*-------------------------------------------------------------------------*\
* Waits for a set of sockets until a condition is met or timeout.
\*-------------------------------------------------------------------------*/
static int global_select(lua_State *L) {
    int rtab, wtab, itab, max_fd, ret, ndirty;
    fd_set rset, wset;
    t_tm tm;
    double t = luaL_optnumber(L, 3, -1);
    FD_ZERO(&rset); FD_ZERO(&wset);
    lua_settop(L, 3);
    lua_newtable(L); itab = lua_gettop(L);
    lua_newtable(L); rtab = lua_gettop(L);
    lua_newtable(L); wtab = lua_gettop(L);
    max_fd = collect_fd(L, 1, -1, itab, &rset);
    ndirty = check_dirty(L, 1, rtab, &rset);
    t = ndirty > 0? 0.0: t;
    tm_init(&tm, t, -1);
    tm_markstart(&tm);
    max_fd = collect_fd(L, 2, max_fd, itab, &wset);
    ret = sock_select(max_fd+1, &rset, &wset, NULL, &tm);
    if (ret > 0 || ndirty > 0) {
        return_fd(L, &rset, max_fd+1, itab, rtab, ndirty);
        return_fd(L, &wset, max_fd+1, itab, wtab, 0);
        make_assoc(L, rtab);
        make_assoc(L, wtab);
        return 2;
    } else if (ret == 0) {
        lua_pushstring(L, "timeout");
        return 3;
    } else {
        lua_pushstring(L, "error");
        return 3;
    }
}

/*=========================================================================*\
* Internal functions
\*=========================================================================*/
static int getfd(lua_State *L) {
    int fd = -1;
    lua_pushstring(L, "getfd");
    lua_gettable(L, -2);
    if (!lua_isnil(L, -1)) {
        lua_pushvalue(L, -2);
        lua_call(L, 1, 1);
        if (lua_isnumber(L, -1)) 
            fd = (int) lua_tonumber(L, -1); 
    } 
    lua_pop(L, 1);
    return fd;
}

static int dirty(lua_State *L) {
    int is = 0;
    lua_pushstring(L, "dirty");
    lua_gettable(L, -2);
    if (!lua_isnil(L, -1)) {
        lua_pushvalue(L, -2);
        lua_call(L, 1, 1);
        is = lua_toboolean(L, -1);
    } 
    lua_pop(L, 1);
    return is;
}

static int collect_fd(lua_State *L, int tab, int max_fd, 
        int itab, fd_set *set) {
    int i = 1;
    if (lua_isnil(L, tab)) 
        return max_fd;
    while (1) {
        int fd;
        lua_pushnumber(L, i);
        lua_gettable(L, tab);
        if (lua_isnil(L, -1)) {
            lua_pop(L, 1);
            break;
        }
        fd = getfd(L);
        if (fd > 0) {
            FD_SET(fd, set);
            if (max_fd < fd) max_fd = fd;
            lua_pushnumber(L, fd);
            lua_pushvalue(L, -2);
            lua_settable(L, itab);
        }
        lua_pop(L, 1);
        i = i + 1;
    }
    return max_fd;
}

static int check_dirty(lua_State *L, int tab, int dtab, fd_set *set) {
    int ndirty = 0, i = 1;
    if (lua_isnil(L, tab)) 
        return 0;
    while (1) {
        int fd;
        lua_pushnumber(L, i);
        lua_gettable(L, tab);
        if (lua_isnil(L, -1)) {
            lua_pop(L, 1);
            break;
        }
        fd = getfd(L);
        if (fd > 0 && dirty(L)) {
            lua_pushnumber(L, ++ndirty);
            lua_pushvalue(L, -2);
            lua_settable(L, dtab);
            FD_CLR(fd, set);
        }
        lua_pop(L, 1);
        i = i + 1;
    }
    return ndirty;
}

static void return_fd(lua_State *L, fd_set *set, int max_fd, 
        int itab, int tab, int start) {
    int fd;
    for (fd = 0; fd < max_fd; fd++) {
        if (FD_ISSET(fd, set)) {
            lua_pushnumber(L, ++start);
            lua_pushnumber(L, fd);
            lua_gettable(L, itab);
            lua_settable(L, tab);
        }
    }
}

static void make_assoc(lua_State *L, int tab) {
    int i = 1, atab;
    lua_newtable(L); atab = lua_gettop(L);
    while (1) {
        lua_pushnumber(L, i);
        lua_gettable(L, tab);
        if (!lua_isnil(L, -1)) {
            lua_pushnumber(L, i);
            lua_pushvalue(L, -2);
            lua_settable(L, atab);
            lua_pushnumber(L, i);
            lua_settable(L, atab);
        } else {
            lua_pop(L, 1);
            break;
        }
        i = i+1;
    }
}

