#ifndef UNIX_H_
#define UNIX_H_

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

#define COMPAT_FD int
#define COMPAT_INVALIDFD (-1)

#define compat_bind bind
#define compat_connect connect
#define compat_listen listen
#define compat_close close
#define compat_select select

#endif /* UNIX_H_ */
