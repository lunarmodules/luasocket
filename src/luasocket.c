/*=========================================================================*\
* LuaSocket toolkit
* Networking support for the Lua language
* Diego Nehab
* 26/11/1999
*
* This library is part of an  effort to progressively increase the network
* connectivity  of  the Lua  language.  The  Lua interface  to  networking
* functions follows the Sockets API  closely, trying to simplify all tasks
* involved in setting up both  client and server connections. The provided
* IO routines, however, follow the Lua  style, being very similar  to the
* standard Lua read and write functions.
*
* RCS ID: $Id$
\*=========================================================================*/

/*=========================================================================*\
* Standard include files
\*=========================================================================*/
#include <lua.h>
#include <lauxlib.h>

/*=========================================================================*\
* LuaSocket includes
\*=========================================================================*/
#include "luasocket.h"

#include "auxiliar.h"
#include "timeout.h"
#include "buffer.h"
#include "socket.h"
#include "inet.h"
#include "tcp.h"
#include "udp.h"
#include "select.h"
#include "mime.h"

/*=========================================================================*\
* Declarations
\*=========================================================================*/
static int global_gethostname(lua_State *L);
static int base_open(lua_State *L);

/* functions in library namespace */
static luaL_reg func[] = {
    {"gethostname", global_gethostname},
    {NULL, NULL}
};

/*-------------------------------------------------------------------------*\
* Setup basic stuff.
\*-------------------------------------------------------------------------*/
static int base_open(lua_State *L)
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
    /* define library functions */
    luaL_openlib(L, LUASOCKET_LIBNAME, func, 0); 
    lua_pop(L, 1);
    return 0;
}

/*-------------------------------------------------------------------------*\
* Gets the host name
\*-------------------------------------------------------------------------*/
static int global_gethostname(lua_State *L)
{
    char name[257];
    name[256] = '\0';
    if (gethostname(name, 256) < 0) {
        lua_pushnil(L);
        lua_pushstring(L, "gethostname failed");
        return 2;
    } else {
        lua_pushstring(L, name);
        return 1;
    }
}

/*-------------------------------------------------------------------------*\
* Initializes all library modules.
\*-------------------------------------------------------------------------*/
LUASOCKET_API int luaopen_socket(lua_State *L)
{
    if (!sock_open()) return 0;
    /* initialize all modules */
    base_open(L);
    aux_open(L);
    tm_open(L);
    buf_open(L);
    inet_open(L); 
    tcp_open(L);
    udp_open(L);
    select_open(L);
    mime_open(L);
#ifdef LUASOCKET_COMPILED
#include "auxiliar.lch"
#include "concat.lch"
#include "url.lch"
#include "callback.lch"
#include "mime.lch"
#include "smtp.lch"
#include "ftp.lch"
#include "http.lch"
#else
    lua_dofile(L, "auxiliar.lua");
    lua_dofile(L, "concat.lua");
    lua_dofile(L, "url.lua");
    lua_dofile(L, "callback.lua");
    lua_dofile(L, "mime.lua");
    lua_dofile(L, "smtp.lua");
    lua_dofile(L, "ftp.lua");
    lua_dofile(L, "http.lua");
#endif
    return 1;
}
