/*=========================================================================*\
* Socket compatibilization module for Unix
* LuaSocket toolkit
*
* We are now treating EINTRs, but if an interrupt happens in the middle of 
* a select function call, we don't guarantee values timeouts anymore.
* It's not a big deal, since we are not real-time anyways.
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
#include <signal.h>

#include "socket.h"

static const char *sock_createstrerror(void);
static const char *sock_bindstrerror(void);
static const char *sock_connectstrerror(void);

/*-------------------------------------------------------------------------*\
* Initializes module 
\*-------------------------------------------------------------------------*/
int sock_open(void)
{
#if DOESNT_COMPILE_TRY_THIS
    struct sigaction ignore;
    memset(&ignore, 0, sizeof(ignore));
    ignore.sa_handler = SIG_IGN;
    sigaction(SIGPIPE, &ignore, NULL);
#endif
    /* instals a handler to ignore sigpipe or it will crash us */
    signal(SIGPIPE, SIG_IGN);
    return 1;
}

/*-------------------------------------------------------------------------*\
* Close and inutilize socket
\*-------------------------------------------------------------------------*/
void sock_destroy(p_sock ps)
{
    if (*ps != SOCK_INVALID) {
        close(*ps);
        *ps = SOCK_INVALID;
    }
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
    int err;
    /* don't call on closed socket */
    if (sock == SOCK_INVALID) return io_strerror(IO_CLOSED);
    /* ask system to connect */
    err = connect(sock, addr, addr_len);
    /* if no error, we're done */
    if (err == 0) return NULL; 
    /* make sure the system is trying to connect */
    if (errno != EINPROGRESS) return io_strerror(IO_ERROR);
    /* wait for a timeout or for the system's answer */
    for ( ;; ) {
        struct timeval tv;
        fd_set rfds, wfds, efds;
        int timeout = tm_getretry(tm);
        tv.tv_sec = timeout / 1000;
        tv.tv_usec = (timeout % 1000) * 1000;
        FD_ZERO(&rfds); FD_SET(sock, &rfds);
        FD_ZERO(&wfds); FD_SET(sock, &wfds);
        FD_ZERO(&efds); FD_SET(sock, &efds);
        /* we run select to avoid busy waiting */
        err = select(sock+1, &rfds, &wfds, &efds, timeout >= 0? &tv: NULL);
        /* if select was interrupted, try again */
        if (err < 0 && errno == EINTR) continue;
        /* if selects readable, try reading */
        if (err > 0) {
            char dummy;
            /* recv will set errno to the value a blocking connect would set */
            if (recv(sock, &dummy, 0, 0) < 0 && errno != EAGAIN)
                return sock_connectstrerror();
            else 
                return NULL;
        /* if no event happened, there was a timeout */
        } else return io_strerror(IO_TIMEOUT);
    } 
    return io_strerror(IO_TIMEOUT); /* can't get here */
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
* 
\*-------------------------------------------------------------------------*/
void sock_shutdown(p_sock ps, int how)
{
    shutdown(*ps, how);
}

/*-------------------------------------------------------------------------*\
* Accept with timeout
\*-------------------------------------------------------------------------*/
int sock_accept(p_sock ps, p_sock pa, SA *addr, socklen_t *addr_len, p_tm tm)
{
    t_sock sock = *ps;
    SA dummy_addr;
    socklen_t dummy_len;
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
        select(sock+1, &fds, NULL, NULL, timeout >= 0? &tv: NULL);
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
    /* avoid making system calls on closed sockets */
    if (sock == SOCK_INVALID) return IO_CLOSED;
    /* make sure we repeat in case the call was interrupted */
    do put = send(sock, data, count, 0);  
    while (put < 0 && errno == EINTR);
    /* deal with failure */
    if (put <= 0) {
        struct timeval tv;
        fd_set fds;
        /* in any case, nothing has been sent */
        *sent = 0;
        /* here we know the connection has been closed */
        if (errno == EPIPE) return IO_CLOSED;
        /* run select to avoid busy wait */
        tv.tv_sec = timeout / 1000;
        tv.tv_usec = (timeout % 1000) * 1000;
        FD_ZERO(&fds);
        FD_SET(sock, &fds);
        if (select(sock+1, NULL, &fds, NULL, timeout >= 0? &tv: NULL) <= 0) {
            /* here the call was interrupted. calling again might work */
            if (errno == EINTR) return IO_RETRY;
            /* here there was no data before timeout */
            else return IO_TIMEOUT;
            /* here we didn't send anything, but now we can */
        } else return IO_DONE;
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
    if (sock == SOCK_INVALID) return IO_CLOSED;
    do put = sendto(sock, data, count, 0, addr, addr_len);  
    while (put < 0 && errno == EINTR);
    if (put <= 0) {
        struct timeval tv;
        fd_set fds;
        *sent = 0;
        if (errno == EPIPE) return IO_CLOSED;
        tv.tv_sec = timeout / 1000;
        tv.tv_usec = (timeout % 1000) * 1000;
        FD_ZERO(&fds);
        FD_SET(sock, &fds);
        if (select(sock+1, NULL, &fds, NULL, timeout >= 0? &tv: NULL) <= 0) {
            if (errno == EINTR) return IO_RETRY;
            else return IO_TIMEOUT;
        } else return IO_DONE;
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
    do taken = read(sock, data, count);  
    while (taken < 0 && errno == EINTR);
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
        ret = select(sock+1, &fds, NULL, NULL, timeout >= 0 ? &tv : NULL);
        if (ret < 0 && errno == EINTR) return IO_RETRY;
        if (ret == 0) return IO_TIMEOUT;
        else return IO_DONE;
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
    do taken = recvfrom(sock, data, count, 0, addr, addr_len);  
    while (taken < 0 && errno == EINTR);
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
        ret = select(sock+1, &fds, NULL, NULL, timeout >= 0 ? &tv : NULL);
        if (ret < 0 && errno == EINTR) return IO_RETRY;
        if (ret == 0) return IO_TIMEOUT;
        else return IO_DONE;
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
    int flags = fcntl(*ps, F_GETFL, 0);
    flags &= (~(O_NONBLOCK));
    fcntl(*ps, F_SETFL, flags);
}

/*-------------------------------------------------------------------------*\
* Put socket into non-blocking mode
\*-------------------------------------------------------------------------*/
void sock_setnonblocking(p_sock ps)
{
    int flags = fcntl(*ps, F_GETFL, 0);
    flags |= O_NONBLOCK;
    fcntl(*ps, F_SETFL, flags);
}

/*-------------------------------------------------------------------------*\
* Error translation functions
\*-------------------------------------------------------------------------*/
const char *sock_hoststrerror(void)
{
    switch (h_errno) {
        case HOST_NOT_FOUND: return "host not found";
        case NO_ADDRESS: return "unable to resolve host name";
        case NO_RECOVERY: return "name server error";
        case TRY_AGAIN: return "name server unavailable, try again later";
        default: return "unknown error";
    }
}

static const char *sock_createstrerror(void)
{
    switch (errno) {
        case EACCES: return "access denied";
        case EMFILE: return "descriptor table is full";
        case ENFILE: return "too many open files";
        case ENOBUFS: return "insuffucient buffer space";
        default: return "unknown error";
    }
}

static const char *sock_bindstrerror(void)
{
    switch (errno) {
        case EBADF: return "invalid descriptor";
        case EINVAL: return "socket already bound";
        case EACCES: return "access denied";
        case ENOTSOCK: return "not a socket descriptor";
        case EADDRINUSE: return "address already in use";
        case EADDRNOTAVAIL: return "address unavailable";
        case ENOMEM: return "out of memory";
        default: return "unknown error";
    }
}

static const char *sock_connectstrerror(void)
{
    switch (errno) {
        case EBADF: return "invalid descriptor";
        case ENOTSOCK: return "not a socket descriptor";
        case EADDRNOTAVAIL: return "address not availabe";
        case ETIMEDOUT: return "connection timed out";
        case ECONNREFUSED: return "connection refused";
        case EACCES: return "access denied";
        case ENETUNREACH: return "network is unreachable";
        case EADDRINUSE: return "address already in use";
        default: return "unknown error";
    }
}
