#ifndef USOCKET_H
#define USOCKET_H
/*=========================================================================*\
* Socket compatibilization module for Unix
* LuaSocket toolkit
*
* RCS ID: $Id$
\*=========================================================================*/

/*=========================================================================*\
* BSD include files
\*=========================================================================*/
/* error codes */
#include <errno.h>
/* close function */
#include <unistd.h>
/* fnctnl function and associated constants */
#include <fcntl.h>
/* struct sockaddr */
#include <sys/types.h>
/* socket function */
#include <sys/socket.h>
/* struct timeval */
#include <sys/time.h>
/* gethostbyname and gethostbyaddr functions */
#include <netdb.h>
/* sigpipe handling */
#include <signal.h>
/* IP stuff*/
#include <netinet/in.h>
#include <arpa/inet.h>
/* TCP options (nagle algorithm disable) */
#include <netinet/tcp.h>

typedef int t_sock;
typedef t_sock *p_sock;

#define SOCK_INVALID (-1)

#endif /* USOCKET_H */
