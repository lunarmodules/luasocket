#ifndef COMPAT_H_
#define COMPAT_H_

#include "lspriv.h"

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

#include <netinet/in.h>
#include <arpa/inet.h>

#define COMPAT_FD int
#define COMPAT_INVALIDFD (-1)

/* we are lazy... */
typedef struct sockaddr SA;

/*=========================================================================*\
* Exported functions
\*=========================================================================*/
void compat_open(lua_State *L);

#define compat_bind bind
#define compat_connect connect
#define compat_listen listen
#define compat_close close
#define compat_select select

COMPAT_FD compat_socket(int domain, int type, int protocol);
COMPAT_FD compat_accept(COMPAT_FD s, SA *addr, socklen_t *len, int deadline);
int compat_send(COMPAT_FD c, cchar *data, size_t count, size_t *done, 
        int deadline);
int compat_recv(COMPAT_FD c, uchar *data, size_t count, size_t *done, 
        int deadline);
int compat_sendto(COMPAT_FD c, cchar *data, size_t count, size_t *done,
        int deadline, SA *addr, socklen_t len);
int compat_recvfrom(COMPAT_FD c, uchar *data, size_t count, size_t *got, 
        int deadline, SA *addr, socklen_t *len);
void compat_setnonblocking(COMPAT_FD sock);
void compat_setblocking(COMPAT_FD sock);
void compat_setreuseaddr(COMPAT_FD sock);

const char *compat_hoststrerror(void);
const char *compat_socketstrerror(void);
const char *compat_bindstrerror(void);
const char *compat_connectstrerror(void);

cchar *compat_trysetoptions(lua_State *L, COMPAT_FD sock);

#endif /* COMPAT_H_ */
