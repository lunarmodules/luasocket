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

static const char *sock_createstrerror(int err);
static const char *sock_bindstrerror(int err);
static const char *sock_connectstrerror(int err);
static const char *sock_acceptstrerror(int err);
static const char *sock_listenstrerror(int err);

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
* Close module 
\*-------------------------------------------------------------------------*/
int sock_close(void)
{
    WSACleanup();
    return 1;
}

/*-------------------------------------------------------------------------*\
* Select with int timeout in ms
\*-------------------------------------------------------------------------*/
int sock_select(int n, fd_set *rfds, fd_set *wfds, fd_set *efds, int timeout)
{
    struct timeval tv;
    tv.tv_sec = timeout / 1000;
    tv.tv_usec = (timeout % 1000) * 1000;
    return select(n, rfds, wfds, efds, timeout >= 0? &tv: NULL);
}

/*-------------------------------------------------------------------------*\
* Close and inutilize socket
\*-------------------------------------------------------------------------*/
void sock_destroy(p_sock ps)
{
    if (*ps != SOCK_INVALID) {
        sock_setblocking(ps); /* close can take a long time on WIN32 */
        closesocket(*ps);
        *ps = SOCK_INVALID;
    }
}

/*-------------------------------------------------------------------------*\
* 
\*-------------------------------------------------------------------------*/
void sock_shutdown(p_sock ps, int how)
{
    sock_setblocking(ps);
    shutdown(*ps, how);
    sock_setnonblocking(ps);
}

/*-------------------------------------------------------------------------*\
* Creates and sets up a socket
\*-------------------------------------------------------------------------*/
const char *sock_create(p_sock ps, int domain, int type, int protocol)
{
    t_sock sock = socket(domain, type, protocol);
    if (sock == SOCK_INVALID) 
        return sock_createstrerror(WSAGetLastError());
    *ps = sock;
    sock_setnonblocking(ps);
    return NULL;
}

/*-------------------------------------------------------------------------*\
* Connects or returns error message
\*-------------------------------------------------------------------------*/
const char *sock_connect(p_sock ps, SA *addr, socklen_t addr_len, p_tm tm)
{
    t_sock sock = *ps;
    int err, timeout = tm_getretry(tm);
    fd_set efds, wfds;
    /* don't call on closed socket */
    if (sock == SOCK_INVALID) return io_strerror(IO_CLOSED);
    /* ask system to connect */
    err = connect(sock, addr, addr_len);
    /* if no error, we're done */
    if (err == 0) return NULL;
    /* make sure the system is trying to connect */
    err = WSAGetLastError(); 
    if (err != WSAEWOULDBLOCK) return sock_connectstrerror(err);
    /* wait for a timeout or for the system's answer */
    FD_ZERO(&wfds); FD_SET(sock, &wfds);
    FD_ZERO(&efds); FD_SET(sock, &efds);
    /* we run select to wait */
    err = sock_select(0, NULL, &wfds, &efds, timeout);
    /* if select returned due to an event */
    if (err > 0 ) {
        /* if was in efds, we failed */
        if (FD_ISSET(sock, &efds)) {
            int why, len = sizeof(why);
            /* give windows time to set the error (disgusting) */
            Sleep(0);
            /* find out why we failed */
            getsockopt(sock, SOL_SOCKET, SO_ERROR, (char *)&why, &len); 
            /* we KNOW there was an error. if why is 0, we will return
             * "unknown error", but it's not really our fault */
            return sock_connectstrerror(why); 
        /* otherwise it must be in wfds, so we succeeded */
        } else return NULL;
    /* if no event happened, we timed out */
    } else return io_strerror(IO_TIMEOUT);
}

/*-------------------------------------------------------------------------*\
* Binds or returns error message
\*-------------------------------------------------------------------------*/
const char *sock_bind(p_sock ps, SA *addr, socklen_t addr_len)
{
    const char *err = NULL;
    sock_setblocking(ps);
    if (bind(*ps, addr, addr_len) < 0) 
        err = sock_bindstrerror(WSAGetLastError());
    sock_setnonblocking(ps);
    return err;
}

/*-------------------------------------------------------------------------*\
* 
\*-------------------------------------------------------------------------*/
const char *sock_listen(p_sock ps, int backlog)
{
    const char *err = NULL;
    sock_setblocking(ps);
    if (listen(*ps, backlog) < 0) 
        err = sock_listenstrerror(WSAGetLastError());
    sock_setnonblocking(ps);
    return err;
}

/*-------------------------------------------------------------------------*\
* Accept with timeout
\*-------------------------------------------------------------------------*/
const char *sock_accept(p_sock ps, p_sock pa, SA *addr, 
        socklen_t *addr_len, p_tm tm)
{
    t_sock sock = *ps;
    SA dummy_addr;
    socklen_t dummy_len = sizeof(dummy_addr);
    if (sock == SOCK_INVALID) return io_strerror(IO_CLOSED);
    if (!addr) addr = &dummy_addr;
    if (!addr_len) addr_len = &dummy_len;
    for (;;) {
        fd_set rfds;
        int timeout = tm_getretry(tm);
        int err;
        /* try to get client socket */
        *pa = accept(sock, addr, addr_len);
        /* if return is valid, we are done */
        if (*pa != SOCK_INVALID) {
            sock_setnonblocking(pa);
            return NULL;
        }
        /* optimization */
        if (timeout == 0) return io_strerror(IO_TIMEOUT);
        /* otherwise find out why we failed */
        err = WSAGetLastError(); 
        /* if we failed because there was no connectoin, keep trying*/
        if (err != WSAEWOULDBLOCK) return sock_acceptstrerror(err);
        /* call select to avoid busy wait */
        FD_ZERO(&rfds);
        FD_SET(sock, &rfds);
        err = sock_select(0, &rfds, NULL, NULL, timeout);
        if (err <= 0) return io_strerror(IO_TIMEOUT);
    } 
    return io_strerror(IO_TIMEOUT); /* can't get here */
}

/*-------------------------------------------------------------------------*\
* Send with timeout
\*-------------------------------------------------------------------------*/
int sock_send(p_sock ps, const char *data, size_t count, size_t *sent, 
        int timeout)
{
    t_sock sock = *ps;
    int put;
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
            fd_set fds;
            FD_ZERO(&fds);
            FD_SET(sock, &fds);
            ret = sock_select(0, NULL, &fds, NULL, timeout);
            /* tell the caller to call us again because now we can send */
            if (ret > 0) return IO_RETRY;
            /* tell the caller we can't send anything before timint out */
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
    int put;
    int ret;
    if (sock == SOCK_INVALID) return IO_CLOSED;
    put = sendto(sock, data, (int) count, 0, addr, addr_len);
    if (put <= 0) {
        *sent = 0;
        if (WSAGetLastError() == WSAEWOULDBLOCK) {
            fd_set fds;
            FD_ZERO(&fds);
            FD_SET(sock, &fds);
            ret = sock_select(0, NULL, &fds, NULL, timeout);
            if (ret > 0) return IO_RETRY;
            else return IO_TIMEOUT;
        } else return IO_CLOSED;
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
    int taken;
    if (sock == SOCK_INVALID) return IO_CLOSED;
    taken = recv(sock, data, (int) count, 0);
    if (taken <= 0) {
        fd_set fds;
        int ret;
        *got = 0;
        if (taken == 0 || WSAGetLastError() != WSAEWOULDBLOCK) return IO_CLOSED;
        FD_ZERO(&fds);
        FD_SET(sock, &fds);
        ret = sock_select(0, &fds, NULL, NULL, timeout);
        if (ret > 0) return IO_RETRY;
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
    int taken;
    if (sock == SOCK_INVALID) return IO_CLOSED;
    taken = recvfrom(sock, data, (int) count, 0, addr, addr_len);
    if (taken <= 0) {
        fd_set fds;
        int ret;
        *got = 0;
        if (taken == 0 || WSAGetLastError() != WSAEWOULDBLOCK) return IO_CLOSED;
        FD_ZERO(&fds);
        FD_SET(sock, &fds);
        ret = sock_select(0, &fds, NULL, NULL, timeout);
        if (ret > 0) return IO_RETRY;
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
/* return error messages for the known errors reported by gethostbyname */
const char *sock_hoststrerror(void)
{
    switch (WSAGetLastError()) {
        case WSANOTINITIALISED: return "not initialized";
        case WSAENETDOWN: return "network is down";
        case WSAHOST_NOT_FOUND: return "host not found";
        case WSATRY_AGAIN: return "name server unavailable, try again later";
        case WSANO_RECOVERY: return "name server error";
        case WSANO_DATA: return "host not found";
        case WSAEINPROGRESS: return "another call in progress";
        case WSAEFAULT: return "invalid memory address";
        case WSAEINTR: return "call interrupted";
        default: return "unknown error";
    }
}

/* return error messages for the known errors reported by socket */
static const char *sock_createstrerror(int err)
{
    switch (err) {
        case WSANOTINITIALISED: return "not initialized";
        case WSAENETDOWN: return "network is down";
        case WSAEAFNOSUPPORT: return "address family not supported";
        case WSAEINPROGRESS: return "another call in progress";
        case WSAEMFILE: return "descriptor table is full";
        case WSAENOBUFS: return "insufficient buffer space";
        case WSAEPROTONOSUPPORT: return "protocol not supported";
        case WSAEPROTOTYPE: return "wrong protocol type";
        case WSAESOCKTNOSUPPORT: return "socket type not supported by family";
        default: return "unknown error";
    }
}

/* return error messages for the known errors reported by accept */
static const char *sock_acceptstrerror(int err)
{
    switch (err) {
        case WSANOTINITIALISED: return "not initialized";
        case WSAENETDOWN: return "network is down";
        case WSAEFAULT: return "invalid memory address";
        case WSAEINTR: return "call interrupted";
        case WSAEINPROGRESS: return "another call in progress";
        case WSAEINVAL: return "not listening";
        case WSAEMFILE: return "descriptor table is full";
        case WSAENOBUFS: return "insufficient buffer space";
        case WSAENOTSOCK: return "descriptor not a socket";
        case WSAEOPNOTSUPP: return "not supported";
        case WSAEWOULDBLOCK: return "call would block";
        default: return "unknown error";
    }
}

/* return error messages for the known errors reported by bind */
static const char *sock_bindstrerror(int err)
{
    switch (err) {
        case WSANOTINITIALISED: return "not initialized";
        case WSAENETDOWN: return "network is down";
        case WSAEACCES: return "broadcast not enabled for socket";
        case WSAEADDRINUSE: return "address already in use";
        case WSAEADDRNOTAVAIL: return "address not available in local host";
        case WSAEFAULT: return "invalid memory address";
        case WSAEINPROGRESS: return "another call in progress";
        case WSAEINVAL: return "already bound";
        case WSAENOBUFS: return "insuficient buffer space";
        case WSAENOTSOCK: return "descriptor not a socket";
        default: return "unknown error";
    }
    
}

/* return error messages for the known errors reported by listen */
static const char *sock_listenstrerror(int err)
{
    switch (err) {
        case WSANOTINITIALISED: return "not initialized";
        case WSAENETDOWN: return "network is down";
        case WSAEADDRINUSE: return "local address already in use";
        case WSAEINPROGRESS: return "another call in progress";
        case WSAEINVAL: return "not bound";
        case WSAEISCONN: return "already connected";
        case WSAEMFILE: return "descriptor table is full";
        case WSAENOBUFS: return "insuficient buffer space";
        case WSAENOTSOCK: return "descriptor not a socket";
        case WSAEOPNOTSUPP: return "not supported";
        default: return "unknown error";
    }
}

/* return error messages for the known errors reported by connect */
static const char *sock_connectstrerror(int err)
{
    switch (err) {
        case WSANOTINITIALISED: return "not initialized";
        case WSAENETDOWN: return "network is down";
        case WSAEADDRINUSE: return "local address already in use";
        case WSAEINTR: return "call interrupted";
        case WSAEINPROGRESS: return "another call in progress";
        case WSAEALREADY: return "connect already in progress";
        case WSAEADDRNOTAVAIL: return "invalid remote address";
        case WSAEAFNOSUPPORT: return "address family not supported";
        case WSAECONNREFUSED: return "connection refused";
        case WSAEFAULT: return "invalid memory address";
        case WSAEINVAL: return "socket is listening";
        case WSAEISCONN: return "socket already connected";
        case WSAENETUNREACH: return "network is unreachable";
        case WSAENOTSOCK: return "descriptor not a socket";
        case WSAETIMEDOUT: return io_strerror(IO_TIMEOUT);
        case WSAEWOULDBLOCK: return "would block";
        case WSAEACCES: return "broadcast not enabled";
        default: return "unknown error";
    }
}
