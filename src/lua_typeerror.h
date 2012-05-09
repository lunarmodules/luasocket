#ifndef LUA_TYPEERROR_H_
#define LUA_TYPEERROR_H_

struct lua_State;
int luaL_typeerror (struct lua_State *L, int narg, const char *tname);

#endif
