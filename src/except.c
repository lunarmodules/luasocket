#include <lauxlib.h>
#include <stdio.h>

#include "except.h"

static int global_try(lua_State *L);
static int global_protect(lua_State *L);
static int protected(lua_State *L);

static luaL_reg func[] = {
    {"try",      global_try},
    {"protect",  global_protect},
    {NULL,       NULL}
};

/*-------------------------------------------------------------------------*\
* Exception handling: try method
\*-------------------------------------------------------------------------*/
static int global_try(lua_State *L) {
    if (lua_isnil(L, 1) || (lua_isboolean(L, 1) && !lua_toboolean(L, 1))) {
        lua_settop(L, 2);
        lua_error(L);
        return 0;
    } else return lua_gettop(L);
}

/*-------------------------------------------------------------------------*\
* Exception handling: protect factory
\*-------------------------------------------------------------------------*/
static int protected(lua_State *L) {
    lua_pushvalue(L, lua_upvalueindex(1));
    lua_insert(L, 1);
    if (lua_pcall(L, lua_gettop(L) - 1, LUA_MULTRET, 0) != 0) {
        lua_pushnil(L);
        lua_insert(L, 1);
        return 2;
    } else return lua_gettop(L);
}

static int global_protect(lua_State *L) {
    lua_insert(L, 1);
    lua_pushcclosure(L, protected, 1);
    return 1;
}

/*-------------------------------------------------------------------------*\
* Init module
\*-------------------------------------------------------------------------*/
int except_open(lua_State *L) {
    luaL_openlib(L, NULL, func, 0);
    return 0;
}
