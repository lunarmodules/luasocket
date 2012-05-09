#include "lua_typeerror.h"
#include "lua.h"
#include "lauxlib.h"

int luaL_typeerror (lua_State *L, int narg, const char *tname) 
{
  const char *msg = lua_pushfstring(L, "%s expected, got %s",tname, luaL_typename(L, narg));
  return luaL_argerror(L, narg, msg);
}

