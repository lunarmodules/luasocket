/*=========================================================================*\
* Internet domain class
* RCS ID: $Id$
\*=========================================================================*/
#ifndef INET_H_
#define INET_H_ 

#include <lua.h>
#include "lssock.h"

/* class name */
#define INET_CLASS "luasocket(inet)"

/*-------------------------------------------------------------------------*\
* Socket fields
\*-------------------------------------------------------------------------*/
#define INET_FIELDS SOCK_FIELDS

/*-------------------------------------------------------------------------*\
* Socket structure
\*-------------------------------------------------------------------------*/
typedef t_sock t_inet;
typedef t_inet *p_inet;

/*-------------------------------------------------------------------------*\
* Exported functions
\*-------------------------------------------------------------------------*/
void inet_open(lua_State *L);
void inet_construct(lua_State *L, p_inet inet);
void inet_inherit(lua_State *L, cchar *lsclass);

cchar *inet_tryconnect(p_sock sock, cchar *address, ushort);
cchar *inet_trybind(p_sock sock, cchar *address, ushort);
cchar *inet_trysocket(p_inet inet, int type);

#endif /* INET_H_ */
