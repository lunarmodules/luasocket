#ifndef SOCKET_H
#define SOCKET_H
/*=========================================================================*\
* Socket compatibilization module
* LuaSocket toolkit
*
* BSD Sockets and WinSock are similar, but there are a few irritating
* differences. Also, not all *nix platforms behave the same. This module
* (and the associated usocket.h and wsocket.h) factor these differences and
* creates a interface compatible with the io.h module.
\*=========================================================================*/
#include "io.h"
#include "common.h"

/*=========================================================================*\
* Platform specific compatibilization
\*=========================================================================*/
#ifdef _WIN32
#include "wsocket.h"
#define LUA_GAI_STRERROR gai_strerrorA
#else
#include "usocket.h"
#define LUA_GAI_STRERROR gai_strerror
#endif

/*=========================================================================*\
* The connect and accept functions accept a timeout and their
* implementations are somewhat complicated. We chose to move
* the timeout control into this module for these functions in
* order to simplify the modules that use them. 
\*=========================================================================*/
#include "timeout.h"

/* convenient shorthand */
typedef struct sockaddr SA;

/*=========================================================================*\
* Functions bellow implement a comfortable platform independent 
* interface to sockets
\*=========================================================================*/

#ifndef _WIN32
#pragma GCC visibility push(hidden)
#endif

LUASOCKET_API int socket_waitfd(p_socket ps, int sw, p_timeout tm);
LUASOCKET_API int socket_open(void);
LUASOCKET_API int socket_close(void);
LUASOCKET_API void socket_destroy(p_socket ps);
LUASOCKET_API int socket_select(t_socket n, fd_set *rfds, fd_set *wfds, fd_set *efds, p_timeout tm);
LUASOCKET_API int socket_create(p_socket ps, int domain, int type, int protocol);
LUASOCKET_API int socket_bind(p_socket ps, SA *addr, socklen_t addr_len);
LUASOCKET_API int socket_listen(p_socket ps, int backlog);
LUASOCKET_API void socket_shutdown(p_socket ps, int how);
LUASOCKET_API int socket_connect(p_socket ps, SA *addr, socklen_t addr_len, p_timeout tm);
LUASOCKET_API int socket_accept(p_socket ps, p_socket pa, SA *addr, socklen_t *addr_len, p_timeout tm);
LUASOCKET_API int socket_send(p_socket ps, const char *data, size_t count, size_t *sent, p_timeout tm);
LUASOCKET_API int socket_sendto(p_socket ps, const char *data, size_t count, size_t *sent, SA *addr, socklen_t addr_len, p_timeout tm);
LUASOCKET_API int socket_recv(p_socket ps, char *data, size_t count, size_t *got, p_timeout tm);
LUASOCKET_API int socket_recvfrom(p_socket ps, char *data, size_t count, size_t *got, SA *addr, socklen_t *addr_len, p_timeout tm);
LUASOCKET_API int socket_write(p_socket ps, const char *data, size_t count, size_t *sent, p_timeout tm);
LUASOCKET_API int socket_read(p_socket ps, char *data, size_t count, size_t *got, p_timeout tm);
LUASOCKET_API void socket_setblocking(p_socket ps);
LUASOCKET_API void socket_setnonblocking(p_socket ps);
LUASOCKET_API int socket_gethostbyaddr(const char *addr, socklen_t len, struct hostent **hp);
LUASOCKET_API int socket_gethostbyname(const char *addr, struct hostent **hp);
LUASOCKET_API const char *socket_hoststrerror(int err);
LUASOCKET_API const char *socket_strerror(int err);
LUASOCKET_API const char *socket_ioerror(p_socket ps, int err);
LUASOCKET_API const char *socket_gaistrerror(int err);

#ifndef _WIN32
#pragma GCC visibility pop
#endif

#endif /* SOCKET_H */
