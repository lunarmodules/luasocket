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

#include "socket.h"

/*-------------------------------------------------------------------------*\
* Initializes module 
\*-------------------------------------------------------------------------*/
int sock_open(void)
{
    /* instals a handler to ignore sigpipe or it will crash us */
    struct sigaction ignore;
    memset(&ignore, 0, sizeof(ignore));
    ignore.sa_handler = SIG_IGN;
    sigaction(SIGPIPE, &ignore, NULL);
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
const char *sock_connect(p_sock ps, SA *addr, socklen_t addr_len, int timeout)
{
    t_sock sock = *ps;
    if (sock == SOCK_INVALID) return "closed";
    if (connect(sock, addr, addr_len) < 0) {
        struct timeval tv;
        fd_set wfds, efds;
        int err;
        tv.tv_sec = timeout / 1000;
        tv.tv_usec = (timeout % 1000) * 1000;
        FD_ZERO(&wfds); FD_ZERO(&efds);
        FD_SET(sock, &wfds); FD_SET(sock, &efds);
        do err = select(sock+1, NULL, &wfds, &efds, timeout >= 0 ? &tv : NULL);
        while (err < 0 && errno == EINTR);
        if (err <= 0) return "timeout";
        if (FD_ISSET(sock, &efds)) {
            char dummy;
            recv(sock, &dummy, 0, 0);
            return sock_connectstrerror();
        } else return NULL;
    } else return NULL;
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
int sock_accept(p_sock ps, p_sock pa, SA *addr, socklen_t *addr_len, 
        int timeout)
{
    t_sock sock = *ps;
    struct timeval tv;
    SA dummy_addr;
    socklen_t dummy_len;
    fd_set fds;
    int err;
    if (sock == SOCK_INVALID) return IO_CLOSED;
    tv.tv_sec = timeout / 1000;
    tv.tv_usec = (timeout % 1000) * 1000;
    FD_ZERO(&fds);
    FD_SET(sock, &fds);
    *pa = SOCK_INVALID;
    do err = select(sock+1, &fds, NULL, NULL, timeout >= 0 ? &tv : NULL);
    while (err < 0 && errno == EINTR);
    if (err <= 0) return IO_TIMEOUT;
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
    ssize_t put;
    int ret;
    /* avoid making system calls on closed sockets */
    if (sock == SOCK_INVALID) return IO_CLOSED;
    /* make sure we repeat in case the call was interrupted */
    do put = write(sock, data, count);  
    while (put <= 0 && errno == EINTR);
    /* deal with failure */
    if (put <= 0) {
        /* in any case, nothing has been sent */
        *sent = 0;
        /* run select to avoid busy wait */
        if (errno != EPIPE) {
            struct timeval tv;
            fd_set fds;
            tv.tv_sec = timeout / 1000;
            tv.tv_usec = (timeout % 1000) * 1000;
            FD_ZERO(&fds);
            FD_SET(sock, &fds);
            do ret = select(sock+1, NULL, &fds, NULL, timeout >= 0 ?&tv : NULL);
            while (ret < 0 && errno == EINTR);
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
    /* make sure we repeat in case the call was interrupted */
    do put = sendto(sock, data, count, 0, addr, addr_len);  
    while (put <= 0 && errno == EINTR);
    /* deal with failure */
    if (put <= 0) {
        /* in any case, nothing has been sent */
        *sent = 0;
        /* run select to avoid busy wait */
        if (errno != EPIPE) {
            struct timeval tv;
            fd_set fds;
            tv.tv_sec = timeout / 1000;
            tv.tv_usec = (timeout % 1000) * 1000;
            FD_ZERO(&fds);
            FD_SET(sock, &fds);
            do ret = select(sock+1, NULL, &fds, NULL, timeout >= 0? &tv: NULL);
            while (ret < 0 && errno == EINTR);
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
* Here we exchanged the order of the calls to write and select
* The idea is that the outer loop (whoever is calling sock_send)
* will call the function again if we didn't time out, so we can
* call write and then select only if it fails.
* Should speed things up!
\*-------------------------------------------------------------------------*/
int sock_recv(p_sock ps, char *data, size_t count, size_t *got, int timeout)
{
    t_sock sock = *ps;
    ssize_t taken;
    if (sock == SOCK_INVALID) return IO_CLOSED;
    do taken = read(sock, data, count);  
    while (taken <= 0 && errno == EINTR);
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
        do ret = select(sock+1, &fds, NULL, NULL, timeout >= 0 ? &tv : NULL);
        while (ret < 0 && errno == EINTR);
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
    do taken = recvfrom(sock, data, count, 0, addr, addr_len);  
    while (taken <= 0 && errno == EINTR);
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
        do ret = select(sock+1, &fds, NULL, NULL, timeout >= 0 ? &tv : NULL);
        while (ret < 0 && errno == EINTR);
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

const char *sock_createstrerror(void)
{
    switch (errno) {
        case EACCES: return "access denied";
        case EMFILE: return "descriptor table is full";
        case ENFILE: return "too many open files";
        case ENOBUFS: return "insuffucient buffer space";
        default: return "unknown error";
    }
}

const char *sock_bindstrerror(void)
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

const char *sock_connectstrerror(void)
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
