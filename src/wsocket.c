/*=========================================================================*\
* Socket compatibilization module for Win32
* LuaSocket toolkit
*
* RCS ID: $Id$
\*=========================================================================*/
#include <string.h>

#include "socket.h"

/*-------------------------------------------------------------------------*\
* Initializes module 
\*-------------------------------------------------------------------------*/
int sock_open(void)
{
    WSADATA wsaData;
    WORD wVersionRequested = MAKEWORD(2, 0); 
    int err = WSAStartup(wVersionRequested, &wsaData );
    if (err != 0) return 0;
    if (LOBYTE(wsaData.wVersion) != 2 || HIBYTE(wsaData.wVersion) != 0) {
        WSACleanup();
        return 0; 
    }
    return 1;
}

/*-------------------------------------------------------------------------*\
* Close and inutilize socket
\*-------------------------------------------------------------------------*/
void sock_destroy(p_sock ps)
{
    if (*ps != SOCK_INVALID) {
        closesocket(*ps);
        *ps = SOCK_INVALID;
    }
}

/*-------------------------------------------------------------------------*\
* 
\*-------------------------------------------------------------------------*/
void sock_shutdown(p_sock ps, int how)
{
    shutdown(*ps, how);
}

/*-------------------------------------------------------------------------*\
* Creates and sets up a socket
\*-------------------------------------------------------------------------*/
const char *sock_create(p_sock ps, int domain, int type, int protocol)
{
    int val = 1;
    t_sock sock = socket(domain, type, protocol);
    if (sock == SOCK_INVALID) return sock_createstrerror(); 
    *ps = sock;
    sock_setnonblocking(ps);
    setsockopt(*ps, SOL_SOCKET, SO_REUSEADDR, (char *) &val, sizeof(val));
    return NULL;
}

/*-------------------------------------------------------------------------*\
* Connects or returns error message
\*-------------------------------------------------------------------------*/
const char *sock_connect(p_sock ps, SA *addr, socklen_t addr_len)
{
    if (connect(*ps, addr, addr_len) < 0) return sock_connectstrerror();
    else return NULL;
}

/*-------------------------------------------------------------------------*\
* Binds or returns error message
\*-------------------------------------------------------------------------*/
const char *sock_bind(p_sock ps, SA *addr, socklen_t addr_len)
{
    if (bind(*ps, addr, addr_len) < 0) return sock_bindstrerror();
    else return NULL;
}

/*-------------------------------------------------------------------------*\
* 
\*-------------------------------------------------------------------------*/
void sock_listen(p_sock ps, int backlog)
{
    listen(*ps, backlog);
}

/*-------------------------------------------------------------------------*\
* Accept with timeout
\*-------------------------------------------------------------------------*/
int sock_accept(p_sock ps, p_sock pa, SA *addr, socklen_t *addr_len, 
        int timeout)
{
    t_sock sock = *ps;
    struct timeval tv;
    SA dummy_addr;
    socklen_t dummy_len;
    fd_set fds;
    if (sock == SOCK_INVALID) return IO_CLOSED;
    tv.tv_sec = timeout / 1000;
    tv.tv_usec = (timeout % 1000) * 1000;
    FD_ZERO(&fds);
    FD_SET(sock, &fds);
    *pa = SOCK_INVALID;
    if (select(sock+1, &fds, NULL, NULL, timeout >= 0 ? &tv : NULL) <= 0)
        return IO_TIMEOUT;
    if (!addr) addr = &dummy_addr;
    if (!addr_len) addr_len = &dummy_len;
    *pa = accept(sock, addr, addr_len);
    if (*pa == SOCK_INVALID) return IO_ERROR;
    else return IO_DONE;
}

/*-------------------------------------------------------------------------*\
* Send with timeout
\*-------------------------------------------------------------------------*/
int sock_send(p_sock ps, const char *data, size_t count, size_t *sent, 
        int timeout)
{
    t_sock sock = *ps;
    struct timeval tv;
    fd_set fds;
    ssize_t put = 0;
    if (sock == SOCK_INVALID) return IO_CLOSED;
    int err;
    int ret;
    tv.tv_sec = timeout / 1000;
    tv.tv_usec = (timeout % 1000) * 1000;
    FD_ZERO(&fds);
    FD_SET(sock, &fds);
    ret = select(sock+1, NULL, &fds, NULL, timeout >= 0 ? &tv : NULL);
    if (ret > 0) {
       put = send(sock, data, count, 0);  
       if (put <= 0) {
           /* a bug in WinSock forces us to do a busy wait until we manage
           ** to write, because select returns immediately even though it
           ** should have blocked us until we could write... */
           if (WSAGetLastError() == WSAEWOULDBLOCK) err = IO_DONE;
           else err = IO_CLOSED;
           *sent = 0;
       } else {
           *sent = put;
           err = IO_DONE;
       }
       return err;
    } else {
        *sent = 0;
        return IO_TIMEOUT;
    }
}

/*-------------------------------------------------------------------------*\
* Sendto with timeout
\*-------------------------------------------------------------------------*/
int sock_sendto(p_sock ps, const char *data, size_t count, size_t *sent, 
        SA *addr, socklen_t addr_len, int timeout)
{
    t_sock sock = *ps;
    struct timeval tv;
    fd_set fds;
    ssize_t put = 0;
    int err;
    int ret;
    if (sock == SOCK_INVALID) return IO_CLOSED;
    tv.tv_sec = timeout / 1000;
    tv.tv_usec = (timeout % 1000) * 1000;
    FD_ZERO(&fds);
    FD_SET(sock, &fds);
    ret = select(sock+1, NULL, &fds, NULL, timeout >= 0 ? &tv : NULL);
    if (ret > 0) {
       put = sendto(sock, data, count, 0, addr, addr_len);  
       if (put <= 0) {
           /* a bug in WinSock forces us to do a busy wait until we manage
           ** to write, because select returns immediately even though it
           ** should have blocked us until we could write... */
           if (WSAGetLastError() == WSAEWOULDBLOCK) err = IO_DONE;
           else err = IO_CLOSED;
           *sent = 0;
       } else {
           *sent = put;
           err = IO_DONE;
       }
       return err;
    } else {
        *sent = 0;
        return IO_TIMEOUT;
    }
}

/*-------------------------------------------------------------------------*\
* Receive with timeout
\*-------------------------------------------------------------------------*/
int sock_recv(p_sock ps, char *data, size_t count, size_t *got, int timeout)
{
    t_sock sock = *ps;
    struct timeval tv;
    fd_set fds;
    int ret;
    ssize_t taken = 0;
    if (sock == SOCK_INVALID) return IO_CLOSED;
    tv.tv_sec = timeout / 1000;
    tv.tv_usec = (timeout % 1000) * 1000;
    FD_ZERO(&fds);
    FD_SET(sock, &fds);
    ret = select(sock+1, &fds, NULL, NULL, timeout >= 0 ? &tv : NULL);
    if (ret > 0) {
       taken = recv(sock, data, count, 0);  
       if (taken <= 0) {
           *got = 0;
           return IO_CLOSED;
       } else {
           *got = taken;
           return IO_DONE;
       }
    } else {
        *got = 0;
        return IO_TIMEOUT;
    }
}

/*-------------------------------------------------------------------------*\
* Recvfrom with timeout
\*-------------------------------------------------------------------------*/
int sock_recvfrom(p_sock ps, char *data, size_t count, size_t *got, 
        SA *addr, socklen_t *addr_len, int timeout)
{
    t_sock sock = *ps;
    struct timeval tv;
    fd_set fds;
    int ret;
    ssize_t taken = 0;
    if (sock == SOCK_INVALID) return IO_CLOSED;
    tv.tv_sec = timeout / 1000;
    tv.tv_usec = (timeout % 1000) * 1000;
    FD_ZERO(&fds);
    FD_SET(sock, &fds);
    ret = select(sock+1, &fds, NULL, NULL, timeout >= 0 ? &tv : NULL);
    if (ret > 0) {
       taken = recvfrom(sock, data, count, 0, addr, addr_len);  
       if (taken <= 0) {
           *got = 0;
           return IO_CLOSED;
       } else {
           *got = taken;
           return IO_DONE;
       }
    } else {
        *got = 0;
        return IO_TIMEOUT;
    }
}

/*-------------------------------------------------------------------------*\
* Put socket into blocking mode
\*-------------------------------------------------------------------------*/
void sock_setblocking(p_sock ps)
{
    u_long argp = 0;
    ioctlsocket(*ps, FIONBIO, &argp);
}

/*-------------------------------------------------------------------------*\
* Put socket into non-blocking mode
\*-------------------------------------------------------------------------*/
void sock_setnonblocking(p_sock ps)
{
    u_long argp = 1;
    ioctlsocket(*ps, FIONBIO, &argp);
}

/*-------------------------------------------------------------------------*\
* Error translation functions
\*-------------------------------------------------------------------------*/
const char *sock_hoststrerror(void)
{
    switch (WSAGetLastError()) {
        case HOST_NOT_FOUND: return "host not found";
        case NO_ADDRESS: return "unable to resolve host name";
        case NO_RECOVERY: return "name server error";
        case TRY_AGAIN: return "name server unavailable, try again later.";
        default: return "unknown error";
    }
}

const char *sock_createstrerror(void)
{
    switch (WSAGetLastError()) {
        case WSANOTINITIALISED: return "not initialized";
        case WSAENETDOWN: return "network is down";
        case WSAEMFILE: return "descriptor table is full";
        case WSAENOBUFS: return "insufficient buffer space";
        default: return "unknown error";
    }
}

const char *sock_bindstrerror(void)
{
    switch (WSAGetLastError()) {
        case WSANOTINITIALISED: return "not initialized";
        case WSAENETDOWN: return "network is down";
        case WSAEADDRINUSE: return "address already in use";
        case WSAEINVAL: return "socket already bound";
        case WSAENOBUFS: return "too many connections";
        case WSAEFAULT: return "invalid address";
        case WSAENOTSOCK: return "not a socket descriptor";
        default: return "unknown error";
    }
}

const char *sock_connectstrerror(void)
{
    switch (WSAGetLastError()) {
        case WSANOTINITIALISED: return "not initialized";
        case WSAENETDOWN: return "network is down";
        case WSAEADDRINUSE: return "address already in use";
        case WSAEADDRNOTAVAIL: return "address unavailable";
        case WSAECONNREFUSED: return "connection refused";
        case WSAENETUNREACH: return "network is unreachable";
        default: return "unknown error";
    }
}
