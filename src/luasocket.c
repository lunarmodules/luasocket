/*=========================================================================*\
* Networking support for the Lua language
* Diego Nehab
* 26/11/1999
*
* This library is part of an  effort to progressively increase the network
* connectivity  of  the Lua  language.  The  Lua interface  to  networking
* functions follows the Sockets API  closely, trying to simplify all tasks
* involved in setting up both  client and server connections. The provided
* IO routines,  however, follow the Lua  style, being very similar  to the
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
#include "lspriv.h"
#include "lsselect.h"
#include "lscompat.h"
#include "lsbase.h"
#include "lstm.h"
#include "lsbuf.h"
#include "lssock.h"
#include "lsinet.h"
#include "lstcpc.h"
#include "lstcps.h"
#include "lstcps.h"
#include "lsudp.h"

/*=========================================================================*\
* Exported functions
\*=========================================================================*/
/*-------------------------------------------------------------------------*\
* Initializes all library modules.
\*-------------------------------------------------------------------------*/
LUASOCKET_API int lua_socketlibopen(lua_State *L)
{
    compat_open(L);
    priv_open(L);
    select_open(L);
    base_open(L);
    tm_open(L);
    fd_open(L);
    sock_open(L);
    inet_open(L); 
    tcpc_open(L); 
    buf_open(L);
    tcps_open(L); 
    udp_open(L);
#if LUASOCKET_DEBUG
    lua_dofile(L, "concat.lua");
    lua_dofile(L, "code.lua");
    lua_dofile(L, "url.lua");
    lua_dofile(L, "http.lua");
    lua_dofile(L, "smtp.lua");
    lua_dofile(L, "ftp.lua");
#else
#include "concat.loh"
#include "code.loh"
#include "url.loh"
#include "http.loh"
#include "smtp.loh"
#include "ftp.loh"
#endif
    return 0;
}
