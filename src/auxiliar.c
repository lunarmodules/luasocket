/*=========================================================================*\
* Auxiliar routines for class hierarchy manipulation
* LuaSocket toolkit
*
* RCS ID: $Id$
\*=========================================================================*/
#include <string.h>
#include <stdio.h>

#include "luasocket.h"
#include "auxiliar.h"

/*=========================================================================*\
* Exported functions
\*=========================================================================*/
/*-------------------------------------------------------------------------*\
* Prints the value of a class in a nice way
\*-------------------------------------------------------------------------*/
int aux_meth_tostring(lua_State *L)
{
    char buf[32];
    if (!lua_getmetatable(L, 1)) goto error;
    lua_pushstring(L, "__index");
    lua_gettable(L, -2);
    if (!lua_istable(L, -1)) goto error;
    lua_pushstring(L, "class");
    lua_gettable(L, -2);
    if (!lua_isstring(L, -1)) goto error;
    sprintf(buf, "%p", lua_touserdata(L, 1));
    lua_pushfstring(L, "socket: %s: %s", lua_tostring(L, -1), buf);
    return 1;
error:
    lua_pushnil(L);
    return 1;
}

/*-------------------------------------------------------------------------*\
* Initializes the module
\*-------------------------------------------------------------------------*/
void aux_open(lua_State *L)
{
    ;
}

/*-------------------------------------------------------------------------*\
* Creates a new class with given methods
\*-------------------------------------------------------------------------*/
void aux_newclass(lua_State *L, const char *classname, luaL_reg *func)
{
    luaL_newmetatable(L, classname); /* mt */
    /* set __tostring metamethod */
    lua_pushstring(L, "__tostring"); 
    lua_pushcfunction(L, aux_meth_tostring);
    lua_rawset(L, -3);      
    /* create __index table to place methods */
    lua_pushstring(L, "__index");    /* mt,"__index" */
    lua_newtable(L);                 /* mt,"__index",it */ 
    luaL_openlib(L, NULL, func, 0);
    /* put class name into class metatable */
    lua_pushstring(L, "class");      /* mt,"__index",it,"class" */
    lua_pushstring(L, classname);    /* mt,"__index",it,"class",classname */
    lua_rawset(L, -3);               /* mt,"__index",it */
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

