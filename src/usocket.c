/*=========================================================================*\
* Socket compatibilization module for Unix
*
* RCS ID: $Id$
\*=========================================================================*/
#include <lua.h>
#include <lauxlib.h>
#include <string.h>

#include "sock.h"

/*=========================================================================*\
* Internal function prototypes
\*=========================================================================*/
static const char *try_setoption(lua_State *L, p_sock ps);
static const char *try_setbooloption(lua_State *L, p_sock ps, int name);

/*=========================================================================*\
* Exported functions.
\*=========================================================================*/
int sock_open(lua_State *L)
{
    /* instals a handler to ignore sigpipe. */
    struct sigaction new;
    memset(&new, 0, sizeof(new));
    new.sa_handler = SIG_IGN;
    sigaction(SIGPIPE, &new, NULL);
    return 1;
}

void sock_destroy(p_sock ps)
{
    close(*ps);
}

const char *sock_create(p_sock ps, int domain, int type, int protocol)
{
    t_sock sock = socket(domain, type, protocol);
    if (sock == SOCK_INVALID) return sock_createstrerror(); 
    *ps = sock;
    sock_setnonblocking(ps);
    sock_setreuseaddr(ps);
    return NULL;
}

const char *sock_connect(p_sock ps, SA *addr, size_t addr_len)
{
    if (connect(*ps, addr, addr_len) < 0) return sock_connectstrerror();
    else return NULL;
}

const char *sock_bind(p_sock ps, SA *addr, size_t addr_len)
{
    if (bind(*ps, addr, addr_len) < 0) return sock_bindstrerror();
    else return NULL;
}

void sock_listen(p_sock ps, int backlog)
{
    listen(*ps, backlog);
}

void sock_accept(p_sock ps, p_sock pa, SA *addr, size_t *addr_len, int timeout)
{
    t_sock sock = *ps;
    struct timeval tv;
    fd_set fds;
    tv.tv_sec = timeout / 1000;
    tv.tv_usec = (timeout % 1000) * 1000;
    FD_ZERO(&fds);
    FD_SET(sock, &fds);
    select(sock+1, &fds, NULL, NULL, timeout >= 0 ? &tv : NULL);
    *pa = accept(sock, addr, addr_len);
}

int sock_send(p_sock ps, const char *data, size_t count, size_t *sent, 
        int timeout)
{
    t_sock sock = *ps;
    struct timeval tv;
    fd_set fds;
    ssize_t put = 0;
    int err;
    int ret;
    tv.tv_sec = timeout / 1000;
    tv.tv_usec = (timeout % 1000) * 1000;
    FD_ZERO(&fds);
    FD_SET(sock, &fds);
    ret = select(sock+1, NULL, &fds, NULL, timeout >= 0 ? &tv : NULL);
    if (ret > 0) {
       put = write(sock, data, count);  
       if (put <= 0) {
           err = IO_CLOSED;
#ifdef __CYGWIN__
           /* this is for CYGWIN, which is like Unix but has Win32 bugs */
           if (errno == EWOULDBLOCK) err = IO_DONE;
#endif
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

int sock_sendto(p_sock ps, const char *data, size_t count, size_t *sent, 
        SA *addr, size_t addr_len, int timeout)
{
    t_sock sock = *ps;
    struct timeval tv;
    fd_set fds;
    ssize_t put = 0;
    int err;
    int ret;
    tv.tv_sec = timeout / 1000;
    tv.tv_usec = (timeout % 1000) * 1000;
    FD_ZERO(&fds);
    FD_SET(sock, &fds);
    ret = select(sock+1, NULL, &fds, NULL, timeout >= 0 ? &tv : NULL);
    if (ret > 0) {
       put = sendto(sock, data, count, 0, addr, addr_len);  
       if (put <= 0) {
           err = IO_CLOSED;
#ifdef __CYGWIN__
           /* this is for CYGWIN, which is like Unix but has Win32 bugs */
           if (sent < 0 && errno == EWOULDBLOCK) err = IO_DONE;
#endif
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

int sock_recv(p_sock ps, char *data, size_t count, size_t *got, int timeout)
{
    t_sock sock = *ps;
    struct timeval tv;
    fd_set fds;
    int ret;
    ssize_t taken = 0;
    tv.tv_sec = timeout / 1000;
    tv.tv_usec = (timeout % 1000) * 1000;
    FD_ZERO(&fds);
    FD_SET(sock, &fds);
    ret = select(sock+1, &fds, NULL, NULL, timeout >= 0 ? &tv : NULL);
    if (ret > 0) {
       taken = read(sock, data, count);  
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

int sock_recvfrom(p_sock ps, char *data, size_t count, size_t *got, 
        SA *addr, size_t *addr_len, int timeout)
{
    t_sock sock = *ps;
    struct timeval tv;
    fd_set fds;
    int ret;
    ssize_t taken = 0;
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
* Returns a string describing the last host manipulation error.
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

/*-------------------------------------------------------------------------*\
* Returns a string describing the last socket manipulation error.
\*-------------------------------------------------------------------------*/
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

/*-------------------------------------------------------------------------*\
* Returns a string describing the last bind command error.
\*-------------------------------------------------------------------------*/
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

/*-------------------------------------------------------------------------*\
* Returns a string describing the last connect error.
\*-------------------------------------------------------------------------*/
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

/*-------------------------------------------------------------------------*\
* Sets the SO_REUSEADDR socket option
* Input
*   sock: socket descriptor
\*-------------------------------------------------------------------------*/
void sock_setreuseaddr(p_sock ps)
{
    int val = 1;
    setsockopt(*ps, SOL_SOCKET, SO_REUSEADDR, (char *)&val, sizeof(val));
}

/*-------------------------------------------------------------------------*\
* Put socket into blocking mode.
\*-------------------------------------------------------------------------*/
void sock_setblocking(p_sock ps)
{
    int flags = fcntl(*ps, F_GETFL, 0);
    flags &= (~(O_NONBLOCK));
    fcntl(*ps, F_SETFL, flags);
}

/*-------------------------------------------------------------------------*\
* Put socket into non-blocking mode.
\*-------------------------------------------------------------------------*/
void sock_setnonblocking(p_sock ps)
{
    int flags = fcntl(*ps, F_GETFL, 0);
    flags |= O_NONBLOCK;
    fcntl(*ps, F_SETFL, flags);
}

/*-------------------------------------------------------------------------*\
* Tries to set extended udp socket options
* Input
*   udp: udp structure
*   oldtop: top of stack
* Returns
*   NULL if successfull, error message on error
\*-------------------------------------------------------------------------*/
const char *sock_trysetoptions(lua_State *L, p_sock ps)
{
    if (!lua_istable(L, 1)) luaL_argerror(L, 1, "invalid options table");
    lua_pushnil(L);
    while (lua_next(L, 1)) {
        const char *err = try_setoption(L, ps);
        lua_pop(L, 1);
        if (err) return err;
    }
    return NULL;
}

/*-------------------------------------------------------------------------*\
* Set socket options from a table on top of Lua stack.
* Supports SO_KEEPALIVE, SO_DONTROUTE, and SO_BROADCAST options.
* Input
*   sock: socket 
* Returns
*   1 if successful, 0 otherwise
\*-------------------------------------------------------------------------*/
static const char *try_setoption(lua_State *L, p_sock ps)
{
    static const char *options[] = {
        "SO_KEEPALIVE", "SO_DONTROUTE", "SO_BROADCAST", NULL
    };
    const char *option = lua_tostring(L, -2);
    if (!lua_isstring(L, -2)) return "invalid option";
    switch (luaL_findstring(option, options)) {
        case 0: return try_setbooloption(L, ps, SO_KEEPALIVE);
        case 1: return try_setbooloption(L, ps, SO_DONTROUTE);
        case 2: return try_setbooloption(L, ps, SO_BROADCAST);
        default: return "unsupported option";
    }
}

/*=========================================================================*\
* Internal functions.
\*=========================================================================*/
static const char *try_setbooloption(lua_State *L, p_sock ps, int name)
{
    int bool, res;
    if (!lua_isnumber(L, -1)) luaL_error(L, "invalid option value");
    bool = (int) lua_tonumber(L, -1);
    res = setsockopt(*ps, SOL_SOCKET, name, (char *) &bool, sizeof(bool));
    if (res < 0) return "error setting option";
    else return NULL;
}
