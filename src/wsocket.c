/*=========================================================================*\
* Socket compatibilization module for Win32
* LuaSocket toolkit
*
* The penalty of calling select to avoid busy-wait is only paid when
* the I/O call fail in the first place. 
*
* RCS ID: $Id$
\*=========================================================================*/
#include <string.h>

#include "socket.h"

/* WinSock doesn't have a strerror... */
static const char *wstrerror(int err);
static int wisclosed(int err);

/*-------------------------------------------------------------------------*\
* Initializes module 
\*-------------------------------------------------------------------------*/
int sock_open(void) {
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
int sock_close(void) {
    WSACleanup();
    return 1;
}

/*-------------------------------------------------------------------------*\
* Select with int timeout in ms
\*-------------------------------------------------------------------------*/
int sock_select(int n, fd_set *rfds, fd_set *wfds, fd_set *efds, p_tm tm) {
    struct timeval tv;
    double t = tm_get(tm);
    tv.tv_sec = (int) t;
    tv.tv_usec = (int) ((t - tv.tv_sec) * 1.0e6);
    return select(n, rfds, wfds, efds, t >= 0.0? &tv: NULL);
}

/*-------------------------------------------------------------------------*\
* Close and inutilize socket
\*-------------------------------------------------------------------------*/
void sock_destroy(p_sock ps) {
    if (*ps != SOCK_INVALID) {
        sock_setblocking(ps); /* close can take a long time on WIN32 */
        closesocket(*ps);
        *ps = SOCK_INVALID;
    }
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
    fd_set efds, wfds;
    /* don't call on closed socket */
    if (sock == SOCK_INVALID) return io_strerror(IO_CLOSED);
    /* ask system to connect */
    err = connect(sock, addr, addr_len);
    /* if no error, we're done */
    if (err == 0) return NULL;
    /* make sure the system is trying to connect */
    err = WSAGetLastError();
    if (err != WSAEWOULDBLOCK) return wstrerror(err);
    /* optimize for timeout=0 */
    if (tm_get(tm) == 0.0) return io_strerror(IO_TIMEOUT);
    /* wait for a timeout or for the system's answer */
    FD_ZERO(&wfds); FD_SET(sock, &wfds);
    FD_ZERO(&efds); FD_SET(sock, &efds);
    /* we run select to wait */
    err = sock_select(0, NULL, &wfds, &efds, tm);
    /* if select returned due to an event */
    if (err > 0) {
        /* if was in efds, we failed */
        if (FD_ISSET(sock, &efds)) {
            int why, len = sizeof(why);
            /* give windows time to set the error (disgusting) */
            Sleep(0);
            /* find out why we failed */
            getsockopt(sock, SOL_SOCKET, SO_ERROR, (char *)&why, &len); 
            /* we KNOW there was an error. if why is 0, we will return
             * "unknown error", but it's not really our fault */
            return wstrerror(why); 
        /* otherwise it must be in wfds, so we succeeded */
        } else return NULL;
    /* if no event happened, we timed out */
    } else if (err == 0) return io_strerror(IO_TIMEOUT);
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
const char *sock_listen(p_sock ps, int backlog) {
    const char *err = NULL;
    sock_setblocking(ps);
    if (listen(*ps, backlog) < 0) err = sock_strerror();
    sock_setnonblocking(ps);
    return err;
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
        fd_set rfds;
        int err;
        /* try to get client socket */
        *pa = accept(sock, addr, addr_len);
        /* if return is valid, we are done */
        if (*pa != SOCK_INVALID) return NULL;
        /* otherwise find out why we failed */
        err = WSAGetLastError(); 
        /* if we failed because there was no connectoin, keep trying */
        if (err != WSAEWOULDBLOCK) return wstrerror(err);
        /* optimize for the timeout=0 case */
        if (tm_get(tm) == 0.0) return io_strerror(IO_TIMEOUT);
        /* call select to avoid busy wait */
        FD_ZERO(&rfds);
        FD_SET(sock, &rfds);
        err = sock_select(0, &rfds, NULL, NULL, tm);
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
    for ( ;; ) {
        fd_set fds;
        int ret, put;
        /* try to send something */
        put = send(sock, data, (int) count, 0);
        /* if we sent something, we are done */
        if (put > 0) {
            *sent = put;
            return IO_DONE;
        }
        /* deal with failure */
        *sent = 0;
        ret = WSAGetLastError(); 
        /* check for connection closed */
        if (wisclosed(ret)) return IO_CLOSED;
        /* we can only proceed if there was no serious error */
        if (ret != WSAEWOULDBLOCK) return IO_USER;
        /* optimize for the timeout = 0 case */
        if (tm_get(tm) == 0.0) return IO_TIMEOUT;
        /* run select to avoid busy wait */
        FD_ZERO(&fds);
        FD_SET(sock, &fds);
        ret = sock_select(0, NULL, &fds, NULL, tm);
        if (ret == 0) return IO_TIMEOUT;
        else if (ret < 0) break;
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
    for ( ;; ) {
        fd_set fds;
        int ret, put;
        /* try to send something */
        put = sendto(sock, data, (int) count, 0, addr, addr_len);
        /* if we sent something, we are done */
        if (put > 0) {
            *sent = put;
            return IO_DONE;
        }
        /* deal with failure */
        *sent = 0;
        ret = WSAGetLastError(); 
        /* check for connection closed */
        if (wisclosed(ret)) return IO_CLOSED;
        /* we can only proceed if there was no serious error */
        if (ret != WSAEWOULDBLOCK) return IO_USER;
        /* optimize for the timeout = 0 case */
        if (tm_get(tm) == 0.0) return IO_TIMEOUT;
        /* run select to avoid busy wait */
        FD_ZERO(&fds);
        FD_SET(sock, &fds);
        ret = sock_select(0, NULL, &fds, NULL, tm);
        if (ret == 0) return IO_TIMEOUT;
        else if (ret < 0) break;
    } 
    return IO_USER;
}

/*-------------------------------------------------------------------------*\
* Receive with timeout
\*-------------------------------------------------------------------------*/
int sock_recv(p_sock ps, char *data, size_t count, size_t *got, p_tm tm)
{
    t_sock sock = *ps;
    if (sock == SOCK_INVALID) return IO_CLOSED;
    for ( ;; ) {
        fd_set fds;
        int ret, taken;
        taken = recv(sock, data, (int) count, 0);
        if (taken > 0) {
            *got = taken;
            return IO_DONE;
        }
        *got = 0;
        if (taken == 0 || wisclosed(ret = WSAGetLastError())) return IO_CLOSED;
        if (ret != WSAEWOULDBLOCK) return IO_USER;
        if (tm_get(tm) == 0.0) return IO_TIMEOUT;
        FD_ZERO(&fds);
        FD_SET(sock, &fds);
        ret = sock_select(0, &fds, NULL, NULL, tm);
        if (ret == 0) return IO_TIMEOUT;
        else if (ret < 0) break;
    }
    return IO_TIMEOUT;
}

/*-------------------------------------------------------------------------*\
* Recvfrom with timeout
\*-------------------------------------------------------------------------*/
int sock_recvfrom(p_sock ps, char *data, size_t count, size_t *got, 
        SA *addr, socklen_t *addr_len, p_tm tm)
{
    t_sock sock = *ps;
    if (sock == SOCK_INVALID) return IO_CLOSED;
    for ( ;; ) {
        fd_set fds;
        int ret, taken;
        taken = recvfrom(sock, data, (int) count, 0, addr, addr_len);
        if (taken > 0) {
            *got = taken;
            return IO_DONE;
        }
        *got = 0;
        if (taken == 0 || wisclosed(ret = WSAGetLastError())) return IO_CLOSED;
        if (ret != WSAEWOULDBLOCK) return IO_USER;
        if (tm_get(tm) == 0.0) return IO_TIMEOUT;
        FD_ZERO(&fds);
        FD_SET(sock, &fds);
        ret = sock_select(0, &fds, NULL, NULL, tm);
        if (ret == 0) return IO_TIMEOUT;
        else if (ret < 0) break;
    }
    return IO_TIMEOUT;
}

/*-------------------------------------------------------------------------*\
* Put socket into blocking mode
\*-------------------------------------------------------------------------*/
void sock_setblocking(p_sock ps) {
    u_long argp = 0;
    ioctlsocket(*ps, FIONBIO, &argp);
}

/*-------------------------------------------------------------------------*\
* Put socket into non-blocking mode
\*-------------------------------------------------------------------------*/
void sock_setnonblocking(p_sock ps) {
    u_long argp = 1;
    ioctlsocket(*ps, FIONBIO, &argp);
}

/*-------------------------------------------------------------------------*\
* Error translation functions
\*-------------------------------------------------------------------------*/
const char *sock_hoststrerror(void) {
    int err = WSAGetLastError();
    switch (err) {
        case WSAHOST_NOT_FOUND: 
            return "host not found";
        default: 
            return wstrerror(err); 
    }
}

const char *sock_strerror(void) {
    int err = WSAGetLastError();
    switch (err) {
        case WSAEADDRINUSE: 
            return "address already in use";
        default: 
            return wstrerror(err);
    }
}

const char *sock_geterr(p_sock ps, int code) {
    (void) ps;
    (void) code;
    return sock_strerror();
}

int wisclosed(int err) {
    switch (err) {
        case WSAECONNRESET:
        case WSAECONNABORTED:
        case WSAESHUTDOWN:
        case WSAENOTCONN:
            return 1;
        default:
            return 0;
    }
}

static const char *wstrerror(int err) {
    switch (err) {
        case WSAEINTR:
            return "WSAEINTR: Interrupted function call";
        case WSAEACCES:
            return "WSAEACCES: Permission denied";
        case WSAEFAULT:
            return "WSAEFAULT: Bad address";
        case WSAEINVAL:
            return "WSAEINVAL: Invalid argument";
        case WSAEMFILE:
            return "WSAEMFILE: Too many open files";
        case WSAEWOULDBLOCK:
            return "WSAEWOULDBLOCK: Resource temporarily unavailable";
        case WSAEINPROGRESS:
            return "WSAEINPROGRESS: Operation now in progress";
        case WSAEALREADY:
            return "WSAEALREADY: Operation already in progress";
        case WSAENOTSOCK:
            return "WSAENOTSOCK: Socket operation on nonsocket";
        case WSAEDESTADDRREQ:
            return "WSAEDESTADDRREQ: Destination address required";
        case WSAEMSGSIZE:
            return "WSAEMSGSIZE: Message too long";
        case WSAEPROTOTYPE:
            return "WSAEPROTOTYPE: Protocol wrong type for socket";
        case WSAENOPROTOOPT:
            return "WSAENOPROTOOPT: Bad protocol option";
        case WSAEPROTONOSUPPORT:
            return "WSAEPROTONOSUPPORT: Protocol not supported";
        case WSAESOCKTNOSUPPORT:
            return "WSAESOCKTNOSUPPORT: Socket type not supported";
        case WSAEOPNOTSUPP:
            return "WSAEOPNOTSUPP: Operation not supported";
        case WSAEPFNOSUPPORT:
            return "WSAEPFNOSUPPORT: Protocol family not supported";
        case WSAEAFNOSUPPORT:
            return "WSAEAFNOSUPPORT: Address family not supported by "
                "protocol family";
        case WSAEADDRINUSE:
            return "WSAEADDRINUSE: Address already in use";
        case WSAEADDRNOTAVAIL:
            return "WSAEADDRNOTAVAIL: Cannot assign requested address";
        case WSAENETDOWN:
            return "WSAENETDOWN: Network is down";
        case WSAENETUNREACH:
            return "WSAENETUNREACH: Network is unreachable";
        case WSAENETRESET:
            return "WSAENETRESET: Network dropped connection on reset";
        case WSAECONNABORTED:
            return "WSAECONNABORTED: Software caused connection abort";
        case WSAECONNRESET:
            return "WSAECONNRESET: Connection reset by peer";
        case WSAENOBUFS:
            return "WSAENOBUFS: No buffer space available";
        case WSAEISCONN:
            return "WSAEISCONN: Socket is already connected";
        case WSAENOTCONN:
            return "WSAENOTCONN: Socket is not connected";
        case WSAESHUTDOWN:
            return "WSAESHUTDOWN: Cannot send after socket shutdown";
        case WSAETIMEDOUT:
            return "WSAETIMEDOUT: Connection timed out";
        case WSAECONNREFUSED:
            return "WSAECONNREFUSED: Connection refused";
        case WSAEHOSTDOWN:
            return "WSAEHOSTDOWN: Host is down";
        case WSAEHOSTUNREACH:
            return "WSAEHOSTUNREACH: No route to host";
        case WSAEPROCLIM:
            return "WSAEPROCLIM: Too many processes";
        case WSASYSNOTREADY:
            return "WSASYSNOTREADY: Network subsystem is unavailable";
        case WSAVERNOTSUPPORTED:
            return "WSAVERNOTSUPPORTED: Winsock.dll version out of range";
        case WSANOTINITIALISED:
            return "WSANOTINITIALISED: Successful WSAStartup not yet performed";
        case WSAEDISCON:
            return "WSAEDISCON: Graceful shutdown in progress";
        case WSATYPE_NOT_FOUND:
            return "WSATYPE_NOT_FOUND: Class type not found";
        case WSAHOST_NOT_FOUND:
            return "WSAHOST_NOT_FOUND: Host not found";
        case WSATRY_AGAIN:
            return "WSATRY_AGAIN: Nonauthoritative host not found";
        case WSANO_RECOVERY:
            return "WSANO_RECOVERY: Nonrecoverable name lookup error"; 
        case WSANO_DATA:
            return "WSANO_DATA: Valid name, no data record of requested type";
        case WSASYSCALLFAILURE:
            return "WSASYSCALLFAILURE: System call failure";
        default:
            return "Unknown error";
    }
}
