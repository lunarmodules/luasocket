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
#include "smtp.h"
#include "mime.h"

/*=========================================================================*\
* Declarations
\*=========================================================================*/
static int base_open(lua_State *L);
static int mod_open(lua_State *L, const luaL_reg *mod);

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
    return 0;
}

static int mod_open(lua_State *L, const luaL_reg *mod)
{
    for (; mod->name; mod++) mod->func(L);
#ifdef LUASOCKET_COMPILED
#include "ltn12.lch"
#include "auxiliar.lch"
#include "url.lch"
#include "mime.lch"
#include "tp.lch"
#include "smtp.lch"
#include "http.lch"
#else
    lua_dofile(L, "ltn12.lua");
    lua_dofile(L, "auxiliar.lua");
    lua_dofile(L, "url.lua");
    lua_dofile(L, "mime.lua");
    lua_dofile(L, "tp.lua");
    lua_dofile(L, "smtp.lua");
    lua_dofile(L, "http.lua");
#endif
    return 0;
}

/*-------------------------------------------------------------------------*\
* Modules
\*-------------------------------------------------------------------------*/
static const luaL_reg mod[] = {
    {"base", base_open},
    {"aux", aux_open},
    {"tm", tm_open},
    {"buf", buf_open},
    {"inet", inet_open},
    {"tcp", tcp_open},
    {"udp", udp_open},
    {"select", select_open},
    {"mime", mime_open},
    {"smtp", smtp_open},
    {NULL, NULL}
};

/*-------------------------------------------------------------------------*\
* Initializes all library modules.
\*-------------------------------------------------------------------------*/
LUASOCKET_API int luaopen_socket(lua_State *L)
{
    if (!sock_open()) {
        lua_pushnil(L);
        lua_pushstring(L, "unable to initialize library");
        return 2;
    }
    mod_open(L, mod);
    return 1;
}
