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
* Close module 
\*-------------------------------------------------------------------------*/
int sock_close(void)
{
    return 1;
}

/*-------------------------------------------------------------------------*\
* Close and inutilize socket
\*-------------------------------------------------------------------------*/
void sock_destroy(p_sock ps)
{
    if (*ps != SOCK_INVALID) {
        sock_setblocking(ps);
        close(*ps);
        *ps = SOCK_INVALID;
    }
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
* Creates and sets up a socket
\*-------------------------------------------------------------------------*/
const char *sock_create(p_sock ps, int domain, int type, int protocol)
{
    t_sock sock = socket(domain, type, protocol);
    if (sock == SOCK_INVALID) return sock_createstrerror(errno);
    *ps = sock;
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
    do err = connect(sock, addr, addr_len);
    while (err < 0 && errno == EINTR);
    /* if no error, we're done */
    if (err == 0) return NULL; 
    /* make sure the system is trying to connect */
    if (errno != EINPROGRESS) return sock_connectstrerror(errno);
    /* wait for a timeout or for the system's answer */
    for ( ;; ) {
        fd_set rfds, wfds, efds;
        FD_ZERO(&rfds); FD_SET(sock, &rfds);
        FD_ZERO(&wfds); FD_SET(sock, &wfds);
        FD_ZERO(&efds); FD_SET(sock, &efds);
        /* we run select to avoid busy waiting */
        do err = sock_select(sock+1, &rfds, &wfds, &efds, tm_getretry(tm));
        while (err < 0 && errno == EINTR); 
        /* if selects readable, try reading */
        if (err > 0) {
            char dummy;
            /* recv will set errno to the value a blocking connect would set */
            if (recv(sock, &dummy, 0, 0) < 0 && errno != EAGAIN)
                return sock_connectstrerror(errno);
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
    const char *err = NULL;
    sock_setblocking(ps);
    if (bind(*ps, addr, addr_len) < 0) err = sock_bindstrerror(errno);
    sock_setnonblocking(ps);
    return err;
}

/*-------------------------------------------------------------------------*\
* 
\*-------------------------------------------------------------------------*/
const char* sock_listen(p_sock ps, int backlog)
{
    const char *err = NULL;
    sock_setblocking(ps);
    if (listen(*ps, backlog))
        err = sock_listenstrerror(errno);
    sock_setnonblocking(ps);
    return err;
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
        int err;
        fd_set fds;
        /* try to accept */
        do *pa = accept(sock, addr, addr_len);
        while (*pa < 0 && errno == EINTR);
        /* if result is valid, we are done */
        if (*pa != SOCK_INVALID) return NULL;
        /* find out if we failed for a fatal reason */
        if (errno != EAGAIN && errno != ECONNABORTED)
            return sock_acceptstrerror(errno);
        /* call select to avoid busy-wait. */
        FD_ZERO(&fds);
        FD_SET(sock, &fds);
        do err = sock_select(sock+1, &fds, NULL, NULL, tm_getretry(tm));
        while (err < 0 && errno == EINTR);
        if (err == 0) return io_strerror(IO_TIMEOUT);
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
    ssize_t put;
    /* avoid making system calls on closed sockets */
    if (sock == SOCK_INVALID) return IO_CLOSED;
    /* make sure we repeat in case the call was interrupted */
    do put = send(sock, data, count, 0);  
    while (put < 0 && errno == EINTR);
    /* deal with failure */
    if (put <= 0) {
        int ret;
        fd_set fds;
        /* in any case, nothing has been sent */
        *sent = 0;
        /* only proceed to select if no error happened */
        if (errno != EAGAIN) return IO_ERROR;
        /* optimize for the timeout = 0 case */
        if (timeout == 0) return IO_TIMEOUT;
        /* here we know the connection has been closed */
        if (errno == EPIPE) return IO_CLOSED;
        /* run select to avoid busy wait */
        FD_ZERO(&fds);
        FD_SET(sock, &fds);
        ret = sock_select(sock+1, NULL, &fds, NULL, timeout);
        if (ret == 0) return IO_TIMEOUT;
        else if (ret > 0 || errno == EINTR) return IO_RETRY;
        else return IO_ERROR;
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
        int ret;
        fd_set fds;
        *sent = 0;
        if (errno != EAGAIN) return IO_ERROR;
        if (timeout == 0) return IO_TIMEOUT;
        if (errno == EPIPE) return IO_CLOSED;
        FD_ZERO(&fds);
        FD_SET(sock, &fds);
        ret = sock_select(sock+1, NULL, &fds, NULL, timeout);
        if (ret == 0) return IO_TIMEOUT;
        else if (ret > 0 || errno == EINTR) return IO_RETRY;
        else return IO_ERROR;
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
        fd_set fds;
        int ret;
        *got = 0;
        if (taken == 0) return IO_CLOSED;
        if (errno != EAGAIN) return IO_ERROR;
        if (timeout == 0) return IO_TIMEOUT;
        FD_ZERO(&fds);
        FD_SET(sock, &fds);
        ret = sock_select(sock+1, &fds, NULL, NULL, timeout);
        if (ret == 0) return IO_TIMEOUT;
        else if (ret > 0 || errno == EINTR) return IO_RETRY;
        else return IO_ERROR;
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
        fd_set fds;
        int ret;
        *got = 0;
        if (taken == 0) return IO_CLOSED;
        if (errno != EAGAIN) return IO_ERROR;
        if (timeout == 0) return IO_TIMEOUT;
        FD_ZERO(&fds);
        FD_SET(sock, &fds);
        ret = sock_select(sock+1, &fds, NULL, NULL, timeout);
        if (ret == 0) return IO_TIMEOUT;
        else if (ret > 0 || errno == EINTR) return IO_RETRY;
        else return IO_ERROR;
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
/* return error messages for the known errors reported by gethostbyname */
const char *sock_hoststrerror(void)
{
    switch (h_errno) {
        case HOST_NOT_FOUND: return "host not found";
        case NO_ADDRESS: return "valid host but no ip found";
        case NO_RECOVERY: return "name server error";
        case TRY_AGAIN: return "name server unavailable, try again later";
        default: return "unknown error";
    }
}

/* return error messages for the known errors reported by socket */
static const char *sock_createstrerror(int err)
{
    switch (err) {
        case EPROTONOSUPPORT: return "protocol not supported";
        case EACCES: return "access denied";
        case EMFILE: return "process file table is full";
        case ENFILE: return "kernel file table is full";
        case EINVAL: return "unknown protocol or family";
        case ENOBUFS: return "insuffucient buffer space";
        default: return "unknown error";
    }
}

/* return error messages for the known errors reported by accept */
static const char *sock_acceptstrerror(int err)
{
    switch (err) {
        case EAGAIN: return io_strerror(IO_RETRY);
        case EBADF: return "invalid descriptor";
        case ENOBUFS: case ENOMEM: return "insuffucient buffer space";
        case ENOTSOCK: return "descriptor not a socket";
        case EOPNOTSUPP: return "not supported";
        case EINTR: return "call interrupted";
        case ECONNABORTED: return "connection aborted";
        case EINVAL: return "not listening";
        case EMFILE: return "process file table is full";
        case ENFILE: return "kernel file table is full";
        case EFAULT: return "invalid memory address";
        default: return "unknown error";
    }
}


/* return error messages for the known errors reported by bind */
static const char *sock_bindstrerror(int err)
{
    switch (err) {
        case EBADF: return "invalid descriptor";
        case ENOTSOCK: return "descriptor not a socket";
        case EADDRNOTAVAIL: return "address unavailable in local host";
        case EADDRINUSE: return "address already in use";
        case EINVAL: return "already bound";
        case EACCES: return "access denied";
        case EFAULT: return "invalid memory address";
        case ENOMEM: return "out of memory";
        default: return "unknown error";
    }
}

/* return error messages for the known errors reported by listen */
static const char *sock_listenstrerror(int err)
{
    switch (err) {
        case EADDRINUSE: return "local address already in use";
        case EBADF: return "invalid descriptor";
        case ENOTSOCK: return "descriptor not a socket";
        case EOPNOTSUPP: return "not supported";
        default: return "unknown error";
    }
}

/* return error messages for the known errors reported by connect */
static const char *sock_connectstrerror(int err)
{
    switch (err) {
        case EBADF: return "invalid descriptor";
        case EFAULT: return "invalid memory address";
        case ENOTSOCK: return "descriptor not a socket";
        case EADDRNOTAVAIL: return "address not available in local host";
        case EISCONN: return "already connected";
        case ECONNREFUSED: return "connection refused";
        case ETIMEDOUT: return io_strerror(IO_TIMEOUT);
        case ENETUNREACH: return "network is unreachable";
        case EADDRINUSE: return "local address already in use";
        case EINPROGRESS: return "would block";
        case EALREADY: return "connect already in progress";
        case EAGAIN: return "not enough free ports";
        case EAFNOSUPPORT: return "address family not supported";
        case EPERM: return "broadcast not enabled or firewall block";
        default: return "unknown error";
    }
}
