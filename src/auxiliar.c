/*=========================================================================*\
* Auxiliar routines for class hierarchy manipulation
* LuaSocket toolkit
*
* RCS ID: $Id$
\*=========================================================================*/
#include <string.h>

#include "luasocket.h"
#include "auxiliar.h"

/*=========================================================================*\
* Exported functions
\*=========================================================================*/
/*-------------------------------------------------------------------------*\
* Initializes the module
\*-------------------------------------------------------------------------*/
void aux_open(lua_State *L)
{
    /* create namespace table */
    lua_pushstring(L, LUASOCKET_LIBNAME);
    lua_newtable(L);
#ifdef LUASOCKET_DEBUG
    lua_pushstring(L, "debug");
    lua_pushnumber(L, 1);
    lua_rawset(L, -3);
#endif
    /* make version string available so scripts */
    lua_pushstring(L, "version");
    lua_pushstring(L, LUASOCKET_VERSION);
    lua_rawset(L, -3);
    /* store namespace as global */
    lua_settable(L, LUA_GLOBALSINDEX);
    /* make sure modules know what is our namespace */
    lua_pushstring(L, "LUASOCKET_LIBNAME");
    lua_pushstring(L, LUASOCKET_LIBNAME);
    lua_settable(L, LUA_GLOBALSINDEX);
}

/*-------------------------------------------------------------------------*\
* Creates a new class with given methods
\*-------------------------------------------------------------------------*/
void aux_newclass(lua_State *L, const char *classname, luaL_reg *func)
{
    luaL_newmetatable(L, classname); /* mt */
    lua_pushstring(L, "__index");    /* mt,"__index" */
    lua_newtable(L);                 /* mt,"__index",it */ 
    luaL_openlib(L, NULL, func, 0);
#ifdef LUASOCKET_DEBUG
    lua_pushstring(L, "class");      /* mt,"__index",it,"class" */
    lua_pushstring(L, classname);    /* mt,"__index",it,"class",classname */
    lua_rawset(L, -3);               /* mt,"__index",it */
#endif
    /* get __gc method from class and use it for garbage collection */
    lua_pushstring(L, "__gc");       /* mt,"__index",it,"__gc" */
    lua_pushstring(L, "__gc");       /* mt,"__index",it,"__gc","__gc" */
    lua_rawget(L, -3);               /* mt,"__index",it,"__gc",fn */
    lua_rawset(L, -5);               /* mt,"__index",it */
    lua_rawset(L, -3);               /* mt */
    lua_pop(L, 1);
}

/*-------------------------------------------------------------------------*\
* Insert class into group
\*-------------------------------------------------------------------------*/
void aux_add2group(lua_State *L, const char *classname, const char *groupname)
{
    luaL_getmetatable(L, classname);
    lua_pushstring(L, groupname);
    lua_pushboolean(L, 1);
    lua_rawset(L, -3);
    lua_pop(L, 1);
}

/*-------------------------------------------------------------------------*\
* Make sure argument is a boolean
\*-------------------------------------------------------------------------*/
int aux_checkboolean(lua_State *L, int objidx)
{
    if (!lua_isboolean(L, objidx))
        luaL_typerror(L, objidx, lua_typename(L, LUA_TBOOLEAN));
    return lua_toboolean(L, objidx);
}

/*-------------------------------------------------------------------------*\
* Calls appropriate option handler
\*-------------------------------------------------------------------------*/
int aux_meth_setoption(lua_State *L, luaL_reg *opt)
{
    const char *name = luaL_checkstring(L, 2);      /* obj, name, args */
    while (opt->name && strcmp(name, opt->name))
        opt++;
    if (!opt->func) {
        char msg[45];
        sprintf(msg, "unknown option `%.35s'", name);
        luaL_argerror(L, 2, msg);
    }
    lua_remove(L, 2);                              /* obj, args */
    lua_pushcfunction(L, opt->func);               /* obj, args, func */
    lua_insert(L, 1);                              /* func, obj, args */
    lua_call(L, lua_gettop(L)-1, LUA_MULTRET);
    return lua_gettop(L);
}

/*-------------------------------------------------------------------------*\
* Return userdata pointer if object belongs to a given class, abort with 
* error otherwise
\*-------------------------------------------------------------------------*/
void *aux_checkclass(lua_State *L, const char *classname, int objidx)
{
    void *data = aux_getclassudata(L, classname, objidx);
    if (!data) {
        char msg[45];
        sprintf(msg, "%.35s expected", classname);
        luaL_argerror(L, objidx, msg);
    }
    return data;
}

/*-------------------------------------------------------------------------*\
* Return userdata pointer if object belongs to a given group, abort with 
* error otherwise
\*-------------------------------------------------------------------------*/
void *aux_checkgroup(lua_State *L, const char *groupname, int objidx)
{
    void *data = aux_getgroupudata(L, groupname, objidx);
    if (!data) {
        char msg[45];
        sprintf(msg, "%.35s expected", groupname);
        luaL_argerror(L, objidx, msg);
    }
    return data;
}

/*-------------------------------------------------------------------------*\
* Set object class
\*-------------------------------------------------------------------------*/
void aux_setclass(lua_State *L, const char *classname, int objidx)
{
    luaL_getmetatable(L, classname);
    if (objidx < 0) objidx--;
    lua_setmetatable(L, objidx);
}

/*-------------------------------------------------------------------------*\
* Get a userdata pointer if object belongs to a given group. Return NULL 
* otherwise
\*-------------------------------------------------------------------------*/
void *aux_getgroupudata(lua_State *L, const char *groupname, int objidx)
{
    if (!lua_getmetatable(L, objidx))
        return NULL;
    lua_pushstring(L, groupname);
    lua_rawget(L, -2);
    if (lua_isnil(L, -1)) {
        lua_pop(L, 2);
        return NULL;
    } else {
        lua_pop(L, 2);
        return lua_touserdata(L, objidx);
    }
}

/*-------------------------------------------------------------------------*\
* Get a userdata pointer if object belongs to a given class. Return NULL 
* otherwise
\*-------------------------------------------------------------------------*/
void *aux_getclassudata(lua_State *L, const char *classname, int objidx)
{
    return luaL_checkudata(L, objidx, classname);
}

