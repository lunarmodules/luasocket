/*=========================================================================*\
* Networking support for the Lua language
* Diego Nehab
* 9/11/1999
*
* RCS ID: $Id$
\*=========================================================================*/
#ifndef _LUASOCKET_H_
#define _LUASOCKET_H_

/*-------------------------------------------------------------------------*\
* Current luasocket version
\*-------------------------------------------------------------------------*/
#define LUASOCKET_VERSION "LuaSocket 1.5"

/*-------------------------------------------------------------------------*\
* This macro prefixes all exported API functions
\*-------------------------------------------------------------------------*/
#ifndef LUASOCKET_API
#define LUASOCKET_API extern
#endif

/*-------------------------------------------------------------------------*\
* Initializes the library.
\*-------------------------------------------------------------------------*/
LUASOCKET_API int lua_socketlibopen(lua_State *L);

#endif /* _LUASOCKET_H_ */
