/*=========================================================================*\
* Socket compatibilization module for Win32
*
* RCS ID: $Id$
\*=========================================================================*/
#ifndef WSOCKET_H
#define WSOCKET_H

/*=========================================================================*\
* WinSock2 include files
\*=========================================================================*/
#include <winsock2.h>
#include <winbase.h>

typedef int socklen_t;
typedef int ssize_t;
typedef SOCKET t_sock;
typedef t_sock *p_sock;

#define SOCK_INVALID (INVALID_SOCKET)

#endif /* WSOCKET_H */
