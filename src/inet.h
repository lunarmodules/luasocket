/*=========================================================================*\
* Internet domain functions
*
* RCS ID: $Id$
\*=========================================================================*/
#ifndef INET_H
#define INET_H 

#include <lua.h>
#include "socket.h"

/*-------------------------------------------------------------------------*\
* Exported functions
\*-------------------------------------------------------------------------*/
void inet_open(lua_State *L);

const char *inet_tryconnect(p_sock ps, const char *address, 
        unsigned short port);
const char *inet_trybind(p_sock ps, const char *address, 
        unsigned short port, int backlog);
const char *inet_trycreate(p_sock ps, int type);

int inet_meth_getpeername(lua_State *L, p_sock ps);
int inet_meth_getsockname(lua_State *L, p_sock ps);

#ifdef INET_ATON
int inet_aton(const char *cp, struct in_addr *inp);
#endif

#endif /* INET_H_ */
