#ifndef AUX_H
#define AUX_H
/*=========================================================================*\
* Auxiliar routines for class hierarchy manipulation
* LuaSocket toolkit
*
* A LuaSocket class is a name associated with Lua metatables. A LuaSocket 
* group is a name associated to a class. A class can belong to any number 
* of groups. This module provides the functionality to:
*
*   - create new classes 
*   - add classes to groups 
*   - set the class of object
*   - check if an object belongs to a given class or group
*
* LuaSocket class names follow the convention <module>{<class>}. Modules
* can define any number of classes and groups. The module tcp.c, for
* example, defines the classes tcp{master}, tcp{client} and tcp{server} and
* the groups tcp{client, server} and tcp{any}. Module functions can then
* perform type-checking on it's arguments by either class or group.
*
* LuaSocket metatables define the __index metamethod as being a table. This
* table has one field for each method supported by the class. In DEBUG
* mode, it also has one field with the class name. 
*
* The mapping from class name to the corresponding metatable and the
* reverse mapping are done using lauxlib. 
*
* RCS ID: $Id$
\*=========================================================================*/

#include <lua.h>
#include <lauxlib.h>

/* min and max macros */
#ifndef MIN
#define MIN(x, y) ((x) < (y) ? x : y)
#endif
#ifndef MAX
#define MAX(x, y) ((x) > (y) ? x : y)
#endif

int aux_open(lua_State *L);
void aux_newclass(lua_State *L, const char *classname, luaL_reg *func);
void aux_add2group(lua_State *L, const char *classname, const char *group);
void aux_setclass(lua_State *L, const char *classname, int objidx);
void *aux_checkclass(lua_State *L, const char *classname, int objidx);
void *aux_checkgroup(lua_State *L, const char *groupname, int objidx);
void *aux_getclassudata(lua_State *L, const char *groupname, int objidx);
void *aux_getgroupudata(lua_State *L, const char *groupname, int objidx);
int aux_checkboolean(lua_State *L, int objidx);
const char *aux_optlstring(lua_State *L, int n, const char *v, size_t *l);

#endif /* AUX_H */
