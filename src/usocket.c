/*=========================================================================*\
* Socket compatibilization module for Unix
* LuaSocket toolkit
*
* The code is now interrupt-safe.
* The penalty of calling select to avoid busy-wait is only paid when
* the I/O call fail in the first place. 
*
* RCS ID: $Id$
\*=========================================================================*/
#include <string.h> 
#include <signal.h>

#include "socket.h"

/*-------------------------------------------------------------------------*\
* Initializes module 
\*-------------------------------------------------------------------------*/
int sock_open(void) {
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
int sock_close(void) {
    return 1;
}

/*-------------------------------------------------------------------------*\
* Close and inutilize socket
\*-------------------------------------------------------------------------*/
void sock_destroy(p_sock ps) {
    if (*ps != SOCK_INVALID) {
        sock_setblocking(ps);
        close(*ps);
        *ps = SOCK_INVALID;
    }
}

/*-------------------------------------------------------------------------*\
* Select with timeout control
\*-------------------------------------------------------------------------*/
int sock_select(int n, fd_set *rfds, fd_set *wfds, fd_set *efds, p_tm tm) {
    int ret;
    do {
        struct timeval tv;
        double t = tm_getretry(tm);
        tv.tv_sec = (int) t;
        tv.tv_usec = (int) ((t - tv.tv_sec) * 1.0e6);
        ret = select(n, rfds, wfds, efds, t >= 0.0? &tv: NULL);
    } while (ret < 0 && errno == EINTR);
    return ret;
}

/*-------------------------------------------------------------------------*\
* Creates and sets up a socket
\*-------------------------------------------------------------------------*/
const char *sock_create(p_sock ps, int domain, int type, int protocol) {
    t_sock sock = socket(domain, type, protocol);
    if (sock == SOCK_INVALID) return sock_strerror();
    *ps = sock;
    return NULL;
}

/*-------------------------------------------------------------------------*\
* Connects or returns error message
\*-------------------------------------------------------------------------*/
const char *sock_connect(p_sock ps, SA *addr, socklen_t addr_len, p_tm tm) {
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
    if (errno != EINPROGRESS) return sock_strerror();
    /* optimize for timeout = 0 */
    if (tm_get(tm) == 0.0) return io_strerror(IO_TIMEOUT);
    /* wait for a timeout or for the system's answer */
    for ( ;; ) {
        fd_set rfds, wfds;
        FD_ZERO(&rfds); FD_SET(sock, &rfds);
        FD_ZERO(&wfds); FD_SET(sock, &wfds);
        /* we run select to avoid busy waiting */
        err = sock_select(sock+1, &rfds, &wfds, NULL, tm);
        /* if there was an event, check what happened */
        if (err > 0) {
            char dummy;
            /* recv will set errno to the value a blocking connect would set */
            if (err > 1 && FD_ISSET(sock, &rfds) && 
                    recv(sock, &dummy, 0, 0) < 0 && errno != EAGAIN)
                return sock_strerror();
            else 
                return NULL;
        /* if no event happened, there was a timeout */
        } else if (err == 0) return io_strerror(IO_TIMEOUT);
    } 
    return sock_strerror();
}

/*-------------------------------------------------------------------------*\
* Binds or returns error message
\*-------------------------------------------------------------------------*/
const char *sock_bind(p_sock ps, SA *addr, socklen_t addr_len) {
    const char *err = NULL;
    sock_setblocking(ps);
    if (bind(*ps, addr, addr_len) < 0) err = sock_strerror();
    sock_setnonblocking(ps);
    return err;
}

/*-------------------------------------------------------------------------*\
* 
\*-------------------------------------------------------------------------*/
const char* sock_listen(p_sock ps, int backlog) {
    const char *err = NULL;
    sock_setblocking(ps);
    if (listen(*ps, backlog)) err = sock_strerror();
    sock_setnonblocking(ps);
    return err;
}

/*-------------------------------------------------------------------------*\
* 
\*-------------------------------------------------------------------------*/
void sock_shutdown(p_sock ps, int how) {
    sock_setblocking(ps);
    shutdown(*ps, how);
    sock_setnonblocking(ps);
}

/*-------------------------------------------------------------------------*\
* Accept with timeout
\*-------------------------------------------------------------------------*/
const char *sock_accept(p_sock ps, p_sock pa, SA *addr, 
        socklen_t *addr_len, p_tm tm) {
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
        /* if connection was aborted, we can try again if we have time */
        if (errno != EAGAIN && errno != ECONNABORTED) return sock_strerror();
        /* optimize for timeout = 0 case */
        if (tm_get(tm) == 0.0) return io_strerror(IO_TIMEOUT);
        /* call select to avoid busy-wait. */
        FD_ZERO(&fds);
        FD_SET(sock, &fds);
        err = sock_select(sock+1, &fds, NULL, NULL, tm);
        if (err == 0) return io_strerror(IO_TIMEOUT);
        else if (err < 0) break; 
    } 
    return sock_strerror();
}

/*-------------------------------------------------------------------------*\
* Send with timeout
\*-------------------------------------------------------------------------*/
int sock_send(p_sock ps, const char *data, size_t count, size_t *sent, p_tm tm)
{
    t_sock sock = *ps;
    /* avoid making system calls on closed sockets */
    if (sock == SOCK_INVALID) return IO_CLOSED;
    /* loop until we send something or we give up on error */
    for ( ;; ) {
        int ret;
        fd_set fds;
        ssize_t put;
        /* make sure we repeat in case the call was interrupted */
        do put = send(sock, data, count, 0);  
        while (put < 0 && errno == EINTR);
        /* if we sent something, get out */ 
        if (put > 0) { 
            *sent = put;
            return IO_DONE;
        }
        /* deal with failure */
        *sent = 0;
        /* here we know the connection has been closed */
        if (put < 0 && errno == EPIPE) return IO_CLOSED;
        /* send shouldn't return zero and we can only proceed if
         * there was no serious error */
        if (put == 0 || errno != EAGAIN) return IO_USER;
        /* optimize for the timeout = 0 case */
        if (tm_get(tm) == 0.0) return IO_TIMEOUT;
        /* run select to avoid busy wait */
        FD_ZERO(&fds);
        FD_SET(sock, &fds);
        ret = sock_select(sock+1, NULL, &fds, NULL, tm);
        if (ret == 0) return IO_TIMEOUT;
        else if (ret < 0) break; 
        /* otherwise, try sending again */
    } 
    return IO_USER;
}

/*-------------------------------------------------------------------------*\
* Sendto with timeout
\*-------------------------------------------------------------------------*/
int sock_sendto(p_sock ps, const char *data, size_t count, size_t *sent, 
        SA *addr, socklen_t addr_len, p_tm tm)
{
    t_sock sock = *ps;
    /* avoid making system calls on closed sockets */
    if (sock == SOCK_INVALID) return IO_CLOSED;
    /* loop until we send something or we give up on error */
    for ( ;; ) {
        int ret;
        fd_set fds;
        ssize_t put;
        do put = sendto(sock, data, count, 0, addr, addr_len);  
        while (put < 0 && errno == EINTR);
        if (put > 0) { 
            *sent = put;
            return IO_DONE;
        }
        *sent = 0;
        if (put < 0 && errno == EPIPE) return IO_CLOSED;
        if (put == 0 || errno != EAGAIN) return IO_USER;
        if (tm_get(tm) == 0.0) return IO_TIMEOUT;
        FD_ZERO(&fds);
        FD_SET(sock, &fds);
        ret = sock_select(sock+1, NULL, &fds, NULL, tm);
        if (ret == 0) return IO_TIMEOUT;
        else if (ret < 0) break;
    } 
    return IO_USER;
}

/*-------------------------------------------------------------------------*\
* Receive with timeout
\*-------------------------------------------------------------------------*/
int sock_recv(p_sock ps, char *data, size_t count, size_t *got, p_tm tm) {
    t_sock sock = *ps;
    if (sock == SOCK_INVALID) return IO_CLOSED;
    for ( ;; ) {
        fd_set fds;
        int ret;
        ssize_t taken;
        do taken = read(sock, data, count);  
        while (taken < 0 && errno == EINTR);
        if (taken > 0) {
            *got = taken;
            return IO_DONE;
        }
        *got = 0;
        if (taken == 0) return IO_CLOSED;
        if (errno != EAGAIN) return IO_USER;
        if (tm_get(tm) == 0.0) return IO_TIMEOUT;
        FD_ZERO(&fds);
        FD_SET(sock, &fds);
        ret = sock_select(sock+1, &fds, NULL, NULL, tm);
        if (ret == 0) return IO_TIMEOUT;
        else if (ret < 0) break; 
    } 
    return IO_USER;
}

/*-------------------------------------------------------------------------*\
* Recvfrom with timeout
\*-------------------------------------------------------------------------*/
int sock_recvfrom(p_sock ps, char *data, size_t count, size_t *got, 
        SA *addr, socklen_t *addr_len, p_tm tm) {
    t_sock sock = *ps;
    if (sock == SOCK_INVALID) return IO_CLOSED;
    for ( ;; ) {
        fd_set fds;
        int ret;
        ssize_t taken;
        do taken = recvfrom(sock, data, count, 0, addr, addr_len);  
        while (taken < 0 && errno == EINTR);
        if (taken > 0) {
            *got = taken;
            return IO_DONE;
        }
        *got = 0;
        if (taken == 0) return IO_CLOSED;
        if (errno != EAGAIN) return IO_USER;
        if (tm_get(tm) == 0.0) return IO_TIMEOUT;
        FD_ZERO(&fds);
        FD_SET(sock, &fds);
        ret = sock_select(sock+1, &fds, NULL, NULL, tm);
        if (ret == 0) return IO_TIMEOUT;
        else if (ret < 0) break;
    } 
    return IO_USER;
}

/*-------------------------------------------------------------------------*\
* Put socket into blocking mode
\*-------------------------------------------------------------------------*/
void sock_setblocking(p_sock ps) {
    int flags = fcntl(*ps, F_GETFL, 0);
    flags &= (~(O_NONBLOCK));
    fcntl(*ps, F_SETFL, flags);
}

/*-------------------------------------------------------------------------*\
* Put socket into non-blocking mode
\*-------------------------------------------------------------------------*/
void sock_setnonblocking(p_sock ps) {
    int flags = fcntl(*ps, F_GETFL, 0);
    flags |= O_NONBLOCK;
    fcntl(*ps, F_SETFL, flags);
}

/*-------------------------------------------------------------------------*\
* Error translation functions
\*-------------------------------------------------------------------------*/
const char *sock_hoststrerror(void) {
    switch (h_errno) {
        case HOST_NOT_FOUND:
            return "host not found";
        default:
            return hstrerror(h_errno);
    }
}

/* make sure important error messages are standard */
const char *sock_strerror(void) {
    switch (errno) {
        case EADDRINUSE:
            return "address already in use";
        default:
            return strerror(errno);
    }
}

const char *sock_geterr(p_sock ps, int code) {
    (void) ps;
    (void) code;
    return sock_strerror();
}
