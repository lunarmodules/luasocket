/*=========================================================================*\
* Socket compatibilization module for Unix
*
* RCS ID: $Id$
\*=========================================================================*/
#ifndef UNIX_H
#define UNIX_H

/*=========================================================================*\
* BSD include files
\*=========================================================================*/
/* error codes */
#include <errno.h>
/* close function */
#include <unistd.h>
/* fnctnl function and associated constants */
#include <fcntl.h>
/* struct timeval and CLK_TCK */
#include <sys/time.h>
/* times function and struct tms */
#include <sys/times.h>
/* struct sockaddr */
#include <sys/types.h>
/* socket function */
#include <sys/socket.h>
/* gethostbyname and gethostbyaddr functions */
#include <netdb.h>
/* sigpipe handling */
#include <signal.h>
/* IP stuff*/
#include <netinet/in.h>
#include <arpa/inet.h>

typedef int t_sock;
typedef t_sock *p_sock;

#define SOCK_INVALID (-1)

#endif /* UNIX_H */
