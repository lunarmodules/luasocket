#ifndef SOCK_H
#define SOCK_H
/*=========================================================================*\
* Socket compatibilization module
* LuaSocket toolkit
*
* BSD Sockets and WinSock are similar, but there are a few irritating
* differences. Also, not all *nix platforms behave the same. This module
* (and the associated usocket.h and wsocket.h) factor these differences and
* creates a interface compatible with the io.h module.
*
* RCS ID: $Id$
\*=========================================================================*/
#include "io.h"

/*=========================================================================*\
* Platform specific compatibilization
\*=========================================================================*/
#ifdef _WIN32
#include "wsocket.h"
#else
#include "usocket.h"
#endif

/*=========================================================================*\
* The connect and accept functions accept a timeout and their
* implementations are somewhat complicated. We chose to move
* the timeout control into this module for these functions in
* order to simplify the modules that use them. 
\*=========================================================================*/
#include "timeout.h"

/* we are lazy... */
typedef struct sockaddr SA;

/*=========================================================================*\
* Functions bellow implement a comfortable platform independent 
* interface to sockets
\*=========================================================================*/
int sock_open(void);
int sock_close(void);
void sock_destroy(p_sock ps);
void sock_shutdown(p_sock ps, int how); 
int sock_sendto(p_sock ps, const char *data, size_t count, 
        size_t *sent, SA *addr, socklen_t addr_len, p_tm tm);
int sock_recvfrom(p_sock ps, char *data, size_t count, 
        size_t *got, SA *addr, socklen_t *addr_len, p_tm tm);

void sock_setnonblocking(p_sock ps);
void sock_setblocking(p_sock ps);

int sock_waitfd(int fd, int sw, p_tm tm);
int sock_select(int n, fd_set *rfds, fd_set *wfds, fd_set *efds, p_tm tm);

int sock_connect(p_sock ps, SA *addr, socklen_t addr_len, p_tm tm); 
int sock_connected(p_sock ps, p_tm tm);
int sock_create(p_sock ps, int domain, int type, int protocol);
int sock_bind(p_sock ps, SA *addr, socklen_t addr_len); 
int sock_listen(p_sock ps, int backlog);
int sock_accept(p_sock ps, p_sock pa, SA *addr, socklen_t *addr_len, p_tm tm);

const char *sock_hoststrerror(int err);
const char *sock_strerror(int err);

/* these are perfect to use with the io abstraction module 
   and the buffered input module */
int sock_send(p_sock ps, const char *data, size_t count, size_t *sent, p_tm tm);
int sock_recv(p_sock ps, char *data, size_t count, size_t *got, p_tm tm);
const char *sock_ioerror(p_sock ps, int err);

int sock_gethostbyaddr(const char *addr, socklen_t len, struct hostent **hp);
int sock_gethostbyname(const char *addr, struct hostent **hp);

#endif /* SOCK_H */
