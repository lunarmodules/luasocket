#ifndef COMPAT_H
#define COMPAT_H

#if LUA_VERSION_NUM==501

#pragma GCC visibility push(hidden)

void luasocket_setfuncs (lua_State *L, const luaL_Reg *l, int nup);
void *luasocket_testudata ( lua_State *L, int arg, const char *tname);

#pragma GCC visibility pop

#define luaL_setfuncs luasocket_setfuncs
#define luaL_testudata luasocket_testudata

#endif

#endif
