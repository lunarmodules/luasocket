/*=========================================================================*\
* Auxiliar routines for class hierarchy manipulation
*
* RCS ID: $Id$
\*=========================================================================*/
#include "aux.h"

/*=========================================================================*\
* Internal function prototypes
\*=========================================================================*/
static void *aux_getgroupudata(lua_State *L, const char *group, int objidx);

/*=========================================================================*\
* Exported functions
\*=========================================================================*/
/*-------------------------------------------------------------------------*\
* Creates a new class. A class has methods given by the func array and the
* field 'class' tells the object class. The table 'group' list the class
* groups the object belongs to.
\*-------------------------------------------------------------------------*/
void aux_newclass(lua_State *L, const char *name, luaL_reg *func)
{
    luaL_newmetatable(L, name);
    lua_pushstring(L, "__index");
    lua_newtable(L);
    luaL_openlib(L, NULL, func, 0);
    lua_pushstring(L, "class");
    lua_pushstring(L, name);
    lua_settable(L, -3);
    lua_settable(L, -3);
    lua_pushstring(L, "group");
    lua_newtable(L);
    lua_settable(L, -3);
    lua_pop(L, 1);
}

/*-------------------------------------------------------------------------*\
* Add group to object list of groups. 
\*-------------------------------------------------------------------------*/
void aux_add2group(lua_State *L, const char *name, const char *group)
{
    luaL_getmetatable(L, name);
    lua_pushstring(L, "group");
    lua_gettable(L, -2);
    lua_pushstring(L, group);
    lua_pushnumber(L, 1);
    lua_settable(L, -3);
    lua_pop(L, 2);
}

/*-------------------------------------------------------------------------*\
* Get a userdata making sure the object belongs to a given class. 
\*-------------------------------------------------------------------------*/
void *aux_checkclass(lua_State *L, const char *name, int objidx)
{
    void *data = luaL_checkudata(L, objidx, name);
    if (!data) {
        char msg[45];
        sprintf(msg, "%.35s expected", name);
        luaL_argerror(L, objidx, msg);
    }
    return data;
}

/*-------------------------------------------------------------------------*\
* Get a userdata making sure the object belongs to a given group. 
\*-------------------------------------------------------------------------*/
void *aux_checkgroup(lua_State *L, const char *group, int objidx)
{
    void *data = aux_getgroupudata(L, group, objidx);
    if (!data) {
        char msg[45];
        sprintf(msg, "%.35s expected", group);
        luaL_argerror(L, objidx, msg);
    }
    return data;
}

/*-------------------------------------------------------------------------*\
* Set object class. 
\*-------------------------------------------------------------------------*/
void aux_setclass(lua_State *L, const char *name, int objidx)
{
    luaL_getmetatable(L, name);
    if (objidx < 0) objidx--;
    lua_setmetatable(L, objidx);
}

/*=========================================================================*\
* Internal functions 
\*=========================================================================*/
/*-------------------------------------------------------------------------*\
* Get a userdata if object belongs to a given group. 
\*-------------------------------------------------------------------------*/
static void *aux_getgroupudata(lua_State *L, const char *group, int objidx)
{
    if (!lua_getmetatable(L, objidx)) return NULL;
    lua_pushstring(L, "group");
    lua_gettable(L, -2);
    if (lua_isnil(L, -1)) {
        lua_pop(L, 2);
        return NULL;
    }
    lua_pushstring(L, group);
    lua_gettable(L, -2);
    if (lua_isnil(L, -1)) {
        lua_pop(L, 3);
        return NULL;
    }
    lua_pop(L, 3);
    return lua_touserdata(L, objidx);
}

