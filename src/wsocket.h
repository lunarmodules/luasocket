#ifndef WSOCKET_H
#define WSOCKET_H
/*=========================================================================*\
* Socket compatibilization module for Win32
* LuaSocket toolkit
*
* RCS ID: $Id$
\*=========================================================================*/

/*=========================================================================*\
* WinSock include files
\*=========================================================================*/
#include <winsock.h>

typedef int socklen_t;
typedef SOCKET t_sock;
typedef t_sock *p_sock;

#define SOCK_INVALID (INVALID_SOCKET)

#endif /* WSOCKET_H */
