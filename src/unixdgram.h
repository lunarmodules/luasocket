#ifndef UNIXDGRAM_H
#define UNIXDGRAM_H
/*=========================================================================*\
* DGRAM object
* LuaSocket toolkit
*
* The dgram.h module provides LuaSocket with support for DGRAM protocol
* (AF_INET, SOCK_DGRAM).
*
* Two classes are defined: connected and unconnected. DGRAM objects are
* originally unconnected. They can be "connected" to a given address
* with a call to the setpeername function. The same function can be used to
* break the connection.
\*=========================================================================*/

#include "unix.h"

#pragma GCC visibility push(hidden)

int unixdgram_open(lua_State *L);

#pragma GCC visibility pop

#endif /* UNIXDGRAM_H */
