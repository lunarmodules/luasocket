/*=========================================================================*\
* Socket compatibilization module for Win32
* LuaSocket toolkit
*
* We also exchanged the order of the calls to send/recv and select.
* The idea is that the outer loop (whoever is calling sock_send/recv)
* will call the function again if we didn't time out, so we can
* call write and then select only if it fails. This moves the penalty
* to when data is not available, maximizing the bandwidth if data is 
* always available. 
*
* RCS ID: $Id$
\*=========================================================================*/
#include <string.h>

#include "socket.h"

static const char *sock_createstrerror(void);
static const char *sock_bindstrerror(void);
static const char *sock_connectstrerror(void);

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
const char *sock_connect(p_sock ps, SA *addr, socklen_t addr_len, p_tm tm)
{
    t_sock sock = *ps;
    int err, timeout = tm_getretry(tm);
    struct timeval tv;
    fd_set efds, wfds;
    /* don't call on closed socket */
    if (sock == SOCK_INVALID) return io_strerror(IO_CLOSED);
    /* ask system to connect */
    err = connect(sock, addr, addr_len);
    /* if no error, we're done */
    if (err == 0) return NULL;
    /* make sure the system is trying to connect */
    if (WSAGetLastError() != WSAEWOULDBLOCK) return sock_connectstrerror();
    /* wait for a timeout or for the system's answer */
    tv.tv_sec = timeout / 1000;
    tv.tv_usec = (timeout % 1000) * 1000;
    FD_ZERO(&wfds); FD_SET(sock, &wfds);
    FD_ZERO(&efds); FD_SET(sock, &efds);
    /* we run select to wait */
    err = select(0, NULL, &wfds, &efds, timeout >= 0? &tv: NULL);
    /* if select returned due to an event */
    if (err > 0 ) {
        /* if was in efds, we failed */
        if (FD_ISSET(sock,&efds) || !FD_ISSET(sock,&wfds)) {
            int why; 
            int len = sizeof(why);
            /* find out why we failed */
            getsockopt(sock, SOL_SOCKET, SO_ERROR, (char *)&why, &len); 
            WSASetLastError(why);
            return sock_connectstrerror(); 
        /* if was in wfds, we succeeded */
        } else return NULL;
        /* if nothing happened, we timed out */
    } else return io_strerror(IO_TIMEOUT);
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
int sock_accept(p_sock ps, p_sock pa, SA *addr, socklen_t *addr_len, p_tm tm)
{
    t_sock sock = *ps;
    SA dummy_addr;
    socklen_t dummy_len = sizeof(dummy_addr);
    if (sock == SOCK_INVALID) return IO_CLOSED;
    if (!addr) addr = &dummy_addr;
    if (!addr_len) addr_len = &dummy_len;
    for (;;) {
        int timeout = tm_getretry(tm);
        struct timeval tv;
        fd_set fds;
        *pa = accept(sock, addr, addr_len);
        if (*pa != SOCK_INVALID) return IO_DONE;
        if (timeout == 0) return IO_TIMEOUT;
        tv.tv_sec = timeout / 1000;
        tv.tv_usec = (timeout % 1000) * 1000;
        FD_ZERO(&fds);
        FD_SET(sock, &fds);
        /* call select just to avoid busy-wait. */
        select(0, &fds, NULL, NULL, timeout >= 0? &tv: NULL);
    } 
    return IO_TIMEOUT; /* can't get here */
}

/*-------------------------------------------------------------------------*\
* Send with timeout
\*-------------------------------------------------------------------------*/
int sock_send(p_sock ps, const char *data, size_t count, size_t *sent, 
        int timeout)
{
    t_sock sock = *ps;
    ssize_t put;
    int ret;
    /* avoid making system calls on closed sockets */
    if (sock == SOCK_INVALID) return IO_CLOSED;
    /* try to send something */
    put = send(sock, data, (int) count, 0);
    /* deal with failure */
    if (put <= 0) {
        /* in any case, nothing has been sent */
        *sent = 0;
        /* run select to avoid busy wait */
        if (WSAGetLastError() == WSAEWOULDBLOCK) {
            struct timeval tv;
            fd_set fds;
            tv.tv_sec = timeout / 1000;
            tv.tv_usec = (timeout % 1000) * 1000;
            FD_ZERO(&fds);
            FD_SET(sock, &fds);
            ret = select(0, NULL, &fds, NULL, timeout >= 0 ? &tv : NULL);
            /* tell the caller to call us again because there is more data */
            if (ret > 0) return IO_DONE;
            /* tell the caller there was no data before timeout */
            else return IO_TIMEOUT;
        /* here we know the connection has been closed */
        } else return IO_CLOSED;
    /* here we successfully sent something */
    } else {
        *sent = put;
        return IO_DONE;
    }
}

/*-------------------------------------------------------------------------*\
* Sendto with timeout
\*-------------------------------------------------------------------------*/
int sock_sendto(p_sock ps, const char *data, size_t count, size_t *sent, 
        SA *addr, socklen_t addr_len, int timeout)
{
    t_sock sock = *ps;
    ssize_t put;
    int ret;
    /* avoid making system calls on closed sockets */
    if (sock == SOCK_INVALID) return IO_CLOSED;
    /* try to send something */
    put = sendto(sock, data, (int) count, 0, addr, addr_len);
    /* deal with failure */
    if (put <= 0) {
        /* in any case, nothing has been sent */
        *sent = 0;
        /* run select to avoid busy wait */
        if (WSAGetLastError() == WSAEWOULDBLOCK) {
            struct timeval tv;
            fd_set fds;
            tv.tv_sec = timeout / 1000;
            tv.tv_usec = (timeout % 1000) * 1000;
            FD_ZERO(&fds);
            FD_SET(sock, &fds);
            ret = select(0, NULL, &fds, NULL, timeout >= 0 ? &tv : NULL);
            /* tell the caller to call us again because there is more data */
            if (ret > 0) return IO_DONE;
            /* tell the caller there was no data before timeout */
            else return IO_TIMEOUT;
        /* here we know the connection has been closed */
        } else return IO_CLOSED;
    /* here we successfully sent something */
    } else {
        *sent = put;
        return IO_DONE;
    }
}

/*-------------------------------------------------------------------------*\
* Receive with timeout
\*-------------------------------------------------------------------------*/
int sock_recv(p_sock ps, char *data, size_t count, size_t *got, int timeout)
{
    t_sock sock = *ps;
    ssize_t taken;
    if (sock == SOCK_INVALID) return IO_CLOSED;
    taken = recv(sock, data, (int) count, 0);
    if (taken <= 0) {
        struct timeval tv;
        fd_set fds;
        int ret;
        *got = 0;
        if (taken == 0) return IO_CLOSED;
        tv.tv_sec = timeout / 1000;
        tv.tv_usec = (timeout % 1000) * 1000;
        FD_ZERO(&fds);
        FD_SET(sock, &fds);
        ret = select(0, &fds, NULL, NULL, timeout >= 0 ? &tv : NULL);
        if (ret > 0) return IO_DONE;
        else return IO_TIMEOUT;
    } else {
        *got = taken;
        return IO_DONE;
    }
}

/*-------------------------------------------------------------------------*\
* Recvfrom with timeout
\*-------------------------------------------------------------------------*/
int sock_recvfrom(p_sock ps, char *data, size_t count, size_t *got, 
        SA *addr, socklen_t *addr_len, int timeout)
{
    t_sock sock = *ps;
    ssize_t taken;
    if (sock == SOCK_INVALID) return IO_CLOSED;
    taken = recvfrom(sock, data, (int) count, 0, addr, addr_len);
    if (taken <= 0) {
        struct timeval tv;
        fd_set fds;
        int ret;
        *got = 0;
        if (taken == 0) return IO_CLOSED;
        tv.tv_sec = timeout / 1000;
        tv.tv_usec = (timeout % 1000) * 1000;
        FD_ZERO(&fds);
        FD_SET(sock, &fds);
        ret = select(0, &fds, NULL, NULL, timeout >= 0 ? &tv : NULL);
        if (ret > 0) return IO_DONE;
        else return IO_TIMEOUT;
    } else {
        *got = taken;
        return IO_DONE;
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

static const char *sock_createstrerror(void)
{
    switch (WSAGetLastError()) {
        case WSANOTINITIALISED: return "not initialized";
        case WSAENETDOWN: return "network is down";
        case WSAEMFILE: return "descriptor table is full";
        case WSAENOBUFS: return "insufficient buffer space";
        default: return "unknown error";
    }
}

static const char *sock_bindstrerror(void)
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

static const char *sock_connectstrerror(void)
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
