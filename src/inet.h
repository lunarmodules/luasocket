#ifndef INET_H 
#define INET_H 
/*=========================================================================*\
* Internet domain functions
* LuaSocket toolkit
*
* This module implements the creation and connection of internet domain
* sockets, on top of the socket.h interface, and the interface of with the
* resolver. 
*
* The function inet_aton is provided for the platforms where it is not
* available. The module also implements the interface of the internet
* getpeername and getsockname functions as seen by Lua programs.
*
* The Lua functions toip and tohostname are also implemented here.
*
* RCS ID: $Id$
\*=========================================================================*/
#include <lua.h>
#include "socket.h"
#include "timeout.h"

#ifdef WIN32
#define INET_ATON
#endif

void inet_open(lua_State *L);

const char *inet_tryconnect(p_sock ps, p_tm tm, const char *address, 
        unsigned short port);
const char *inet_trybind(p_sock ps, const char *address, 
        unsigned short port, int backlog);
const char *inet_trycreate(p_sock ps, int type);
const char *inet_tryaccept(p_sock ps, p_tm tm, p_sock pc);

int inet_meth_getpeername(lua_State *L, p_sock ps);
int inet_meth_getsockname(lua_State *L, p_sock ps);

#ifdef INET_ATON
int inet_aton(const char *cp, struct in_addr *inp);
#endif

#endif /* INET_H */
