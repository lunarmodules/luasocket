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

/*=========================================================================*\
* Exported functions
\*=========================================================================*/
/*-------------------------------------------------------------------------*\
* Initializes all library modules.
\*-------------------------------------------------------------------------*/
LUASOCKET_API int luaopen_socket(lua_State *L)
{
    if (!sock_open()) return 0;
    /* initialize all modules */
    aux_open(L);
    tm_open(L);
    buf_open(L);
    inet_open(L); 
    tcp_open(L);
    udp_open(L);
    select_open(L);
#ifdef LUASOCKET_COMPILED
#include "auxiliar.lch"
#include "concat.lch"
#include "code.lch"
#include "url.lch"
#include "smtp.lch"
#include "ftp.lch"
#include "http.lch"
#else
    lua_dofile(L, "auxiliar.lua");
    lua_dofile(L, "concat.lua");
    lua_dofile(L, "code.lua");
    lua_dofile(L, "url.lua");
    lua_dofile(L, "smtp.lua");
    lua_dofile(L, "ftp.lua");
    lua_dofile(L, "http.lua");
#endif
    return 1;
}
