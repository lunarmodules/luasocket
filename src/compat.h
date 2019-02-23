#ifndef COMPAT_H
#define COMPAT_H

#include "lua.h"
#include "lauxlib.h"

#if LUA_VERSION_NUM==501
#define luaL_setfuncs socket_setfuncs
#define luaL_testudata socket_testudata
void luaL_setfuncs (lua_State *L, const luaL_Reg *l, int nup);
void *luaL_testudata ( lua_State *L, int arg, const char *tname);
#endif

#endif
