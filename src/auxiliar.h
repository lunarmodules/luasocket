/*=========================================================================*\
* Auxiliar routines for class hierarchy manipulation
*
* RCS ID: $Id$
\*=========================================================================*/
#ifndef AUX_H
#define AUX_H

#include <lua.h>
#include <lauxlib.h>

void aux_newclass(lua_State *L, const char *name, luaL_reg *func);
void aux_add2group(lua_State *L, const char *name, const char *group);
void *aux_checkclass(lua_State *L, const char *name, int objidx);
void *aux_checkgroup(lua_State *L, const char *group, int objidx);
void aux_setclass(lua_State *L, const char *name, int objidx);

/* min and max macros */
#ifndef MIN
#define MIN(x, y) ((x) < (y) ? x : y)
#endif
#ifndef MAX
#define MAX(x, y) ((x) > (y) ? x : y)
#endif

#endif
