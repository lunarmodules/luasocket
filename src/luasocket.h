/*=========================================================================*\
* TCP/IP support for LUA
* Diego Nehab
* 9/11/1999
\*=========================================================================*/

#ifndef _LUASOCKET_H_
#define _LUASOCKET_H_

/* Current luasocket version */
#define LUASOCKET_VERSION "LuaSocket 1.3b"

/*-------------------------------------------------------------------------*\
* These can be changed to according to the applications' needs.
\*-------------------------------------------------------------------------*/
/* TCP input buffer size */
#define LUASOCKET_TCPBUFFERSIZE 8192

/* The largest datagram handled by LuaSocket */
#define LUASOCKET_UDPBUFFERSIZE 4096
/* note that 576 bytes is the maximum safe value */

/*-------------------------------------------------------------------------*\
* Initializes the library interface with Lua and the socket library.
* Defines the symbols exported to Lua.
\*-------------------------------------------------------------------------*/
void lua_socketlibopen(lua_State *L);

#endif /* _LUASOCKET_H_ */
