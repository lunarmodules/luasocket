/*=========================================================================*\
* Network compatibilization module: Unix version
*
* RCS ID: $Id$
\*=========================================================================*/
#include <lua.h>
#include <lauxlib.h>
#include <string.h>

#include "lscompat.h"

/*=========================================================================*\
* Internal function prototypes
\*=========================================================================*/
static cchar *try_setoption(lua_State *L, COMPAT_FD sock);
static cchar *try_setbooloption(lua_State *L, COMPAT_FD sock, int name);

/*=========================================================================*\
* Exported functions.
\*=========================================================================*/
int compat_open(lua_State *L)
{
    /* Instals a handler to ignore sigpipe. */
    struct sigaction new;
    memset(&new, 0, sizeof(new));
    new.sa_handler = SIG_IGN;
    sigaction(SIGPIPE, &new, NULL);
    return 1;
}

COMPAT_FD compat_accept(COMPAT_FD s, struct  sockaddr  *addr,  
        size_t *len, int deadline)
{
    struct timeval tv;
    fd_set fds;
    tv.tv_sec = deadline / 1000;
    tv.tv_usec = (deadline % 1000) * 1000;
    FD_ZERO(&fds);
    FD_SET(s, &fds);
    select(s+1, &fds, NULL, NULL, deadline >= 0 ? &tv : NULL);
    return accept(s, addr, len);
}

int compat_send(COMPAT_FD c, cchar *data, size_t count, size_t *sent, 
        int deadline)
{
    struct timeval tv;
    fd_set fds;
    ssize_t put = 0;
    int err;
    int ret;
    tv.tv_sec = deadline / 1000;
    tv.tv_usec = (deadline % 1000) * 1000;
    FD_ZERO(&fds);
    FD_SET(c, &fds);
    ret = select(c+1, NULL, &fds, NULL, deadline >= 0 ? &tv : NULL);
    if (ret > 0) {
       put = write(c, data, count);  
       if (put <= 0) {
           err = PRIV_CLOSED;
#ifdef __CYGWIN__
           /* this is for CYGWIN, which is like Unix but has Win32 bugs */
           if (errno == EWOULDBLOCK) err = PRIV_DONE;
#endif
           *sent = 0;
       } else {
           *sent = put;
           err = PRIV_DONE;
       }
       return err;
    } else {
        *sent = 0;
        return PRIV_TIMEOUT;
    }
}

int compat_sendto(COMPAT_FD c, cchar *data, size_t count, size_t *sent, 
        int deadline, SA *addr, size_t len)
{
    struct timeval tv;
    fd_set fds;
    ssize_t put = 0;
    int err;
    int ret;
    tv.tv_sec = deadline / 1000;
    tv.tv_usec = (deadline % 1000) * 1000;
    FD_ZERO(&fds);
    FD_SET(c, &fds);
    ret = select(c+1, NULL, &fds, NULL, deadline >= 0 ? &tv : NULL);
    if (ret > 0) {
       put = sendto(c, data, count, 0, addr, len);  
       if (put <= 0) {
           err = PRIV_CLOSED;
#ifdef __CYGWIN__
           /* this is for CYGWIN, which is like Unix but has Win32 bugs */
           if (sent < 0 && errno == EWOULDBLOCK) err = PRIV_DONE;
#endif
           *sent = 0;
       } else {
           *sent = put;
           err = PRIV_DONE;
       }
       return err;
    } else {
        *sent = 0;
        return PRIV_TIMEOUT;
    }
}

int compat_recv(COMPAT_FD c, char *data, size_t count, size_t *got, 
        int deadline)
{
    struct timeval tv;
    fd_set fds;
    int ret;
    ssize_t taken = 0;
    tv.tv_sec = deadline / 1000;
    tv.tv_usec = (deadline % 1000) * 1000;
    FD_ZERO(&fds);
    FD_SET(c, &fds);
    ret = select(c+1, &fds, NULL, NULL, deadline >= 0 ? &tv : NULL);
    if (ret > 0) {
       taken = read(c, data, count);  
       if (taken <= 0) {
           *got = 0;
           return PRIV_CLOSED;
       } else {
           *got = taken;
           return PRIV_DONE;
       }
    } else {
        *got = 0;
        return PRIV_TIMEOUT;
    }
}

int compat_recvfrom(COMPAT_FD c, char *data, size_t count, size_t *got, 
        int deadline, SA *addr, size_t *len)
{
    struct timeval tv;
    fd_set fds;
    int ret;
    ssize_t taken = 0;
    tv.tv_sec = deadline / 1000;
    tv.tv_usec = (deadline % 1000) * 1000;
    FD_ZERO(&fds);
    FD_SET(c, &fds);
    ret = select(c+1, &fds, NULL, NULL, deadline >= 0 ? &tv : NULL);
    if (ret > 0) {
       taken = recvfrom(c, data, count, 0, addr, len);  
       if (taken <= 0) {
           *got = 0;
           return PRIV_CLOSED;
       } else {
           *got = taken;
           return PRIV_DONE;
       }
    } else {
        *got = 0;
        return PRIV_TIMEOUT;
    }
}

/*-------------------------------------------------------------------------*\
* Returns a string describing the last host manipulation error.
\*-------------------------------------------------------------------------*/
const char *compat_hoststrerror(void)
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
const char *compat_socketstrerror(void)
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
const char *compat_bindstrerror(void)
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
const char *compat_connectstrerror(void)
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
void compat_setreuseaddr(COMPAT_FD sock)
{
    int val = 1;
    setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, (char *)&val, sizeof(val));
}

COMPAT_FD compat_socket(int domain, int type, int protocol)
{
    COMPAT_FD sock = socket(domain, type, protocol);
    if (sock != COMPAT_INVALIDFD) {
        compat_setnonblocking(sock);
        compat_setreuseaddr(sock);
    }
    return sock;
}

/*-------------------------------------------------------------------------*\
* Put socket into blocking mode.
\*-------------------------------------------------------------------------*/
void compat_setblocking(COMPAT_FD sock)
{
    int flags = fcntl(sock, F_GETFL, 0);
    flags &= (~(O_NONBLOCK));
    fcntl(sock, F_SETFL, flags);
}

/*-------------------------------------------------------------------------*\
* Put socket into non-blocking mode.
\*-------------------------------------------------------------------------*/
void compat_setnonblocking(COMPAT_FD sock)
{
    int flags = fcntl(sock, F_GETFL, 0);
    flags |= O_NONBLOCK;
    fcntl(sock, F_SETFL, flags);
}

/*-------------------------------------------------------------------------*\
* Tries to set extended udp socket options
* Input
*   udp: udp structure
*   oldtop: top of stack
* Returns
*   NULL if successfull, error message on error
\*-------------------------------------------------------------------------*/
cchar *compat_trysetoptions(lua_State *L, COMPAT_FD sock)
{
    if (!lua_istable(L, 1)) luaL_argerror(L, 1, "invalid options table");
    lua_pushnil(L);
    while (lua_next(L, 1)) {
        cchar *err = try_setoption(L, sock);
        lua_pop(L, 1);
        if (err) return err;
    }
    return NULL;
}

/*=========================================================================*\
* Internal functions.
\*=========================================================================*/
static cchar *try_setbooloption(lua_State *L, COMPAT_FD sock, int name)
{
    int bool, res;
    if (!lua_isnumber(L, -1)) luaL_error(L, "invalid option value");
    bool = (int) lua_tonumber(L, -1);
    res = setsockopt(sock, SOL_SOCKET, name, (char *) &bool, sizeof(bool));
    if (res < 0) return "error setting option";
    else return NULL;
}


/*-------------------------------------------------------------------------*\
* Set socket options from a table on top of Lua stack.
* Supports SO_KEEPALIVE, SO_DONTROUTE, SO_BROADCAST, and SO_LINGER options.
* Input
*   L: Lua state to use
*   sock: socket descriptor
* Returns
*   1 if successful, 0 otherwise
\*-------------------------------------------------------------------------*/
static cchar *try_setoption(lua_State *L, COMPAT_FD sock)
{
    static cchar *options[] = {
        "SO_KEEPALIVE", "SO_DONTROUTE", "SO_BROADCAST", "SO_LINGER", NULL
    };
    cchar *option = lua_tostring(L, -2);
    if (!lua_isstring(L, -2)) return "invalid option";
    switch (luaL_findstring(option, options)) {
        case 0: return try_setbooloption(L, sock, SO_KEEPALIVE);
        case 1: return try_setbooloption(L, sock, SO_DONTROUTE);
        case 2: return try_setbooloption(L, sock, SO_BROADCAST);
        case 3: return "SO_LINGER is deprecated";
        default: return "unsupported option";
    }
}

