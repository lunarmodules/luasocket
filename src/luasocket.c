/*=========================================================================*\
* IPv4 Sockets for the Lua language
* Diego Nehab
* 26/11/1999
*
* Module: luasocket.c
*
* This module is part of an effort to make the most important features
* of the IPv4 Socket layer available to Lua scripts.
* The Lua interface to TCP/IP follows the BSD TCP/IP API closely, 
* trying to simplify all tasks involved in setting up both client 
* and server connections.
* The provided IO routines, send and receive, follow the Lua style, being 
* very similar to the standard Lua read and write functions.
* The module implements both a BSD bind and a Winsock2 bind, and has 
* been tested on several Unix flavors, as well as Windows 98 and NT. 
*
* RCS ID: $Id$
\*=========================================================================*/

/*=========================================================================*\
* Common include files
\*=========================================================================*/
#include <errno.h>
#include <signal.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

#include <lauxlib.h>
#include <lua.h>

#include "luasocket.h"

/*=========================================================================*\
* WinSock2 include files
\*=========================================================================*/
#ifdef WIN32
#include <winsock2.h>
#include <winbase.h>
#else

/*=========================================================================*\
* BSD include files
\*=========================================================================*/
/* close function */
#include <unistd.h>
/* fnctnl function and associated constants */
#include <fcntl.h>
/* struct timeval and CLK_TCK */
#include <sys/time.h>
/* times function and struct tms */
#include <sys/times.h>
/* internet protocol definitions */
#include <netinet/in.h>
#include <arpa/inet.h>
/* struct sockaddr */
#include <sys/types.h>
/* socket function */
#include <sys/socket.h>
/* gethostbyname and gethostbyaddr functions */
#include <netdb.h>
#endif

/*=========================================================================*\
* Datatype compatibilization and some simple changes
\*=========================================================================*/
#ifndef WIN32
/* WinSock2 has a closesock function instead of the regular close */
#define closesocket close
/* it defines a SOCKET type instead of using an integer file descriptor */
#define SOCKET int
/* and uses the this macro to represent and invalid socket */
#define INVALID_SOCKET (-1)
/* SunOS, does not define CLK_TCK */
#ifndef CLK_TCK                  
#define CLK_TCK 60               
#endif
#endif

/*=========================================================================*\
* Module definitions
\*=========================================================================*/
/*-------------------------------------------------------------------------*\
* The send and receive function can return one of the following return
* codes. The values are mapped into Lua values by the function
* push_error.
\*-------------------------------------------------------------------------*/
#define NET_DONE -1              /* operation completed successfully */
#define NET_TIMEOUT 0            /* operation timed out */
#define NET_CLOSED 1             /* the connection has been closed */
#define NET_REFUSED 2            /* the data transfer has been refused */

/*-------------------------------------------------------------------------*\
* Time out mode to be checked
\*-------------------------------------------------------------------------*/
#define TM_RECEIVE 1
#define TM_SEND 2

/*-------------------------------------------------------------------------*\
* Each socket is represented by a table with the supported methods and
* the p_sock structure as fields.
\*-------------------------------------------------------------------------*/
#define P_SOCK "(p_sock)sock"

/*-------------------------------------------------------------------------*\
* Both socket types are stored in the same structure to simplify
* implementation. The tag value used is different, though. 
* The buffer parameters are not used by server and UDP sockets.
\*-------------------------------------------------------------------------*/
typedef struct t_sock {
    /* operating system socket object */
    SOCKET sock;
    /* start time of the current operation */    
    int tm_start;
    /* return and blocking timeout values (-1 if no limit) */
    int tm_return, tm_block;
    /* buffered I/O storage */
    unsigned char bf_buffer[LUASOCKET_TCPBUFFERSIZE];
    /* first and last red bytes not yet passed to application */
    int bf_first, bf_last;
    /* is this udp socket in "connected" state? */
    int is_connected;
#ifdef _DEBUG
    /* end time of current operation, for debug purposes */
    int tm_end;
#endif
} t_sock;
typedef t_sock *p_sock;

/*-------------------------------------------------------------------------*\
* Tags passed as closure values to global LuaSocket API functions
\*-------------------------------------------------------------------------*/
typedef struct t_tags {
    int client, server, table, udp;
} t_tags;
typedef t_tags *p_tags;

/*-------------------------------------------------------------------------*\
* Macros and internal declarations
\*-------------------------------------------------------------------------*/
/* min and max macros */
#ifndef MIN
#define MIN(x, y) ((x) < (y) ? x : y)
#endif
#ifndef MAX
#define MAX(x, y) ((x) > (y) ? x : y)
#endif

/* we are lazy.. */
typedef struct sockaddr SA;

/*=========================================================================*\
* Internal function prototypes
\*=========================================================================*/
/* luasocket global API functions */
static int global_tcpconnect(lua_State *L);
static int global_tcpbind(lua_State *L);
static int global_select(lua_State *L);
static int global_toip(lua_State *L);
static int global_tohostname(lua_State *L);
static int global_udpsocket(lua_State *L);

#ifndef LUASOCKET_NOGLOBALS
static int global_callfromtable(lua_State *L);
#endif

/* luasocket table method API functions */
static int table_tcpaccept(lua_State *L);
static int table_tcpsend(lua_State *L);
static int table_tcpreceive(lua_State *L);
static int table_udpsendto(lua_State *L);
static int table_udpreceivefrom(lua_State *L);
static int table_udpsetpeername(lua_State *L);
static int table_timeout(lua_State *L);
static int table_close(lua_State *L);
static int table_getpeername(lua_State *L);
static int table_getsockname(lua_State *L);

/* buffered I/O management */
static const unsigned char *bf_receive(p_sock sock, int *length);
static void bf_skip(p_sock sock, int length);
static int bf_isempty(p_sock sock);

/* timeout management */
static int tm_timedout(p_sock sock, int mode);
static int tm_gettimeleft(p_sock sock);
static int tm_gettime(void);
static void tm_markstart(p_sock sock);

/* I/O */
static int send_raw(p_sock sock, const char *data, int wanted, int *err);
static int receive_raw(lua_State *L, p_sock sock, int wanted);
static int receive_word(lua_State *L, p_sock sock);
static int receive_dosline(lua_State *L, p_sock sock);
static int receive_unixline(lua_State *L, p_sock sock);
static int receive_all(lua_State *L, p_sock sock);

/* parameter manipulation functions */
static p_tags pop_tags(lua_State *L);
static p_sock pop_sock(lua_State *L);
static p_sock get_sock(lua_State *L, int s, p_tags tags, int *tag);
static p_sock get_selfsock(lua_State *L, p_tags tags, int *tag);
static p_sock push_servertable(lua_State *L, p_tags tags);
static p_sock push_clienttable(lua_State *L, p_tags tags);
static p_sock push_udptable(lua_State *L, p_tags tags);
static void push_error(lua_State *L, int err);
static void push_resolved(lua_State *L, struct hostent *hp);

/* error code translations functions */
static char *host_strerror(void);
static char *bind_strerror(void);
static char *socket_strerror(void);
static char *connect_strerror(void);

/* socket auxiliary functions */
static const char *tcp_trybind(p_sock sock, const char *address, 
    unsigned short port, int backlog);
static const char *tcp_tryconnect(p_sock sock, const char *address, 
    unsigned short port);
static const char *udp_setpeername(p_sock sock, const char *address, 
    unsigned short port);
static const char *udp_setsockname(p_sock sock, const char *address, 
    unsigned short port);
static int set_option(lua_State *L, p_sock sock);
static void set_reuseaddr(p_sock sock);
static void set_blocking(p_sock sock);
static void set_nonblocking(p_sock sock);

#ifdef WIN32
static int winsock_open(void);
#define LUASOCKET_ATON
#endif

#ifdef LUASOCKET_ATON
static int inet_aton(const char *cp, struct in_addr *inp);
#endif

/* tag methods */
static int gc_table(lua_State *L);

/*=========================================================================*\
* Test support functions
\*=========================================================================*/
#ifdef _DEBUG
/*-------------------------------------------------------------------------*\
* Returns the time the system has been up, in secconds.
\*-------------------------------------------------------------------------*/
static int global_time(lua_State *L);
static int global_time(lua_State *L)
{
    lua_pushnumber(L, tm_gettime()/1000.0);
    return 1;
}

/*-------------------------------------------------------------------------*\
* Causes a Lua script to sleep for the specified number of secconds
\*-------------------------------------------------------------------------*/
static int global_sleep(lua_State *L);
static int global_sleep(lua_State *L)
{
    int sec = (int) luaL_check_number(L, 1);
#ifdef WIN32
    Sleep(1000*sec);
#else
    sleep(sec);
#endif
    return 0;
}

#endif

/*=========================================================================*\
* Lua exported functions
* These functions can be accessed from a Lua script.
\*=========================================================================*/
/*-------------------------------------------------------------------------*\
* Creates a client socket and returns it to the Lua script. The timeout
* values are initialized as -1 so that the socket will block at any
* IO operation.
* Lua Input: address, port
*   address: host name or ip address to connect to 
*   port: port number on host
* Lua Returns
*   On success: client socket object
*   On error: nil, followed by an error message
\*-------------------------------------------------------------------------*/
static int global_tcpconnect(lua_State *L)
{
    p_tags tags = pop_tags(L);
    const char *address = luaL_check_string(L, 1);
    unsigned short port = (unsigned short) luaL_check_number(L, 2);
    p_sock sock = push_clienttable(L, tags);
    const char *err = tcp_tryconnect(sock, address, port);
    if (err) {
        lua_pushnil(L);
        lua_pushstring(L, err);
        return 2;
    }
    set_nonblocking(sock);
    return 1;
}

/*-------------------------------------------------------------------------*\
* Creates a udp socket object and returns it to the Lua script. 
* Lua Returns
*   On success: udp socket
*   On error: nil, followed by an error message
\*-------------------------------------------------------------------------*/
static int global_udpsocket(lua_State *L)
{
    p_tags tags = pop_tags(L);
    int top = lua_gettop(L);
    p_sock sock = push_udptable(L, tags);
    if (!sock) return 2;
    if (top >= 1 ) {
        if  (lua_istable(L, 1)) {
            lua_pushnil(L);
            while (lua_next(L, 1)) {
                if (!set_option(L, sock)) lua_error(L, "error setting option");
                lua_pop(L, 1);
            }
        } else luaL_argerror(L, 1, "invalid options");
    }
    return 1;
}

/*-------------------------------------------------------------------------*\
* Waits for and returns a client socket object attempting connection 
* with a server socket. The function blocks until a client shows up or 
* until a timeout condition is met.
* Lua Input: sock
*   sock: server socket created by the bind function
* Lua Returns
*   On success: client socket attempting connection
*   On error: nil followed by an error message
\*-------------------------------------------------------------------------*/
static int table_tcpaccept(lua_State *L)
{
    struct sockaddr_in client_addr;
    size_t client_len = sizeof(client_addr);
    p_sock server = pop_sock(L);
    p_tags tags = pop_tags(L);
    p_sock client = push_clienttable(L, tags);
    tm_markstart(server);
    if (tm_gettimeleft(server) >= 0) {
        set_nonblocking(server);
        do {
            if (tm_timedout(server, TM_RECEIVE)) {
                lua_pushnil(L);
                push_error(L, NET_TIMEOUT);
                return 2;
            }
            client->sock = accept(server->sock, (SA *) &client_addr, 
                &client_len);
        } while (client->sock == INVALID_SOCKET);

    } else {
        set_blocking(server);
        client->sock = accept(server->sock, (SA *) &client_addr, &client_len);
    }
    set_nonblocking(client);
    return 1;
}

/*-------------------------------------------------------------------------*\
* Associates an address to a server socket.
* Lua Input: address, port [, backlog]
*   address: host name or ip address to bind to 
*   port: port to bind to
*   backlog: connection queue length (default: 1)
* Lua Returns
*   On success: server socket bound to address
*   On error: nil, followed by an error message
\*-------------------------------------------------------------------------*/
static int global_tcpbind(lua_State *L)
{
    p_tags tags = pop_tags(L);
    const char *address = luaL_check_string(L, 1);
    unsigned short port = (unsigned short) luaL_check_number(L, 2);
    int backlog = (int) luaL_opt_number(L, 3, 1);
    p_sock sock = push_servertable(L, tags);
    const char *err;
    if (!sock) {
        lua_pushnil(L);
        lua_pushstring(L, "out of memory");
        return 2;
    }
    err = tcp_trybind(sock, address, port, backlog);
    if (err) {
        lua_pushnil(L);
        lua_pushstring(L, err);
        return 2;
    }
    return 1;
}

/*-------------------------------------------------------------------------*\
* Associates a local address to UDP socket
* Lua Input: address, port
*   address: host name or ip address to bind to 
*   port: port to bind to
* Lua Returns
*   On success: nil
*   On error: error message
\*-------------------------------------------------------------------------*/
static int table_udpsetsockname(lua_State *L)
{
    p_sock sock = pop_sock(L);
    const char *address = luaL_check_string(L, 2);
    unsigned short port = (unsigned short) luaL_check_number(L, 3);
    const char *err = udp_setsockname(sock, address, port);
    if (err) {
        lua_pushstring(L, err);
        return 1;
    }
    lua_pushnil(L);
    return 1;
}

/*-------------------------------------------------------------------------*\
* Sets a peer for a UDP socket
* Lua Input: address, port
*   address: remote host name
*   port: remote host port
* Lua Returns
*   On success: nil
*   On error: error message
\*-------------------------------------------------------------------------*/
static int table_udpsetpeername(lua_State *L)
{
    p_sock sock = pop_sock(L);
    const char *address = luaL_check_string(L, 2);
    unsigned short port = (unsigned short) luaL_check_number(L, 3);
    const char *err = udp_setpeername(sock, address, port);
    if (err) {
        lua_pushstring(L, err);
        return 1;
    }
    sock->is_connected = 1;
    lua_pushnil(L);
    return 1;
}

/*-------------------------------------------------------------------------*\
* Sets timeout values for IO operations on a socket
* Lua Input: sock, time [, mode]
*   sock: client socket created by the connect function
*   time: time out value in seconds
*   mode: "b" for block timeout, "r" for return timeout. (default: b)
\*-------------------------------------------------------------------------*/
static int table_timeout(lua_State *L)
{
    p_sock sock = pop_sock(L);
    int ms = lua_isnil(L, 2) ? -1 : (int) (luaL_check_number(L, 2)*1000.0);
    const char *mode = luaL_opt_string(L, 3, "b");
    switch (*mode) {
        case 'b':
            sock->tm_block = ms;
            break;
        case 'r':
            sock->tm_return = ms;
            break;
        default:
            luaL_arg_check(L, 0, 3, "invalid timeout mode");
            break;
    }
    return 0;
}

/*-------------------------------------------------------------------------*\
* Send data through a TCP socket
* Lua Input: sock, a_1 [, a_2, a_3 ... a_n]
*   sock: client socket created by the connect function
*   a_i: strings to be sent. The strings will be sent on the order they
*     appear as parameters
* Lua Returns
*   On success: nil, followed by the total number of bytes sent
*   On error: error message
\*-------------------------------------------------------------------------*/
static int table_tcpsend(lua_State *L)
{
    int arg;
    p_sock sock = pop_sock(L);
    int top = lua_gettop(L);
    int total = 0;
    int err = NET_DONE;
    tm_markstart(sock);
    for (arg = 2; arg <= top; arg++) { /* skip self table */
        int sent;
        size_t wanted;
        const char *data = luaL_opt_lstr(L, arg, NULL, &wanted);
        if (!data || err != NET_DONE) break;
        err = send_raw(sock, data, wanted, &sent);
        total += sent;
    }
    push_error(L, err);
    lua_pushnumber(L, total);
#ifdef _DEBUG
    /* push time elapsed during operation as the last return value */
    lua_pushnumber(L, (sock->tm_end - sock->tm_start)/1000.0);
#endif
    return lua_gettop(L) - top;
}

/*-------------------------------------------------------------------------*\
* Send data through a unconnected UDP socket
* Lua Input: sock, data, ip, port
*   sock: udp socket
*   data: data to be sent
*   ip: ip address of target
*   port: port in target
* Lua Returns
*   On success: nil, followed by the total number of bytes sent
*   On error: error message
\*-------------------------------------------------------------------------*/
static int table_udpsendto(lua_State *L)
{
    p_sock sock = pop_sock(L);
    size_t wanted;
     const char *data = luaL_check_lstr(L, 2, &wanted);
    const char *ip = luaL_check_string(L, 3);
    unsigned short port = (unsigned short) luaL_check_number(L, 4);
    struct sockaddr_in peer;
    int sent;
    if (sock->is_connected) lua_error(L, "sendto on connected socket");
    tm_markstart(sock);
    if (tm_timedout(sock, TM_SEND)) {
        push_error(L, NET_TIMEOUT);
        return 1;
    }
    memset(&peer, 0, sizeof(peer));
    peer.sin_family = AF_INET;
    peer.sin_port = htons(port);
    if (!inet_aton(ip, &peer.sin_addr)) lua_error(L, "invalid ip address");
    sent = sendto(sock->sock, data, wanted, 0, (SA *) &peer, sizeof(peer));
    if (sent >= 0) {
        lua_pushnil(L);
        lua_pushnumber(L, sent);
        return 2;
    } else {
        push_error(L, NET_REFUSED);
        return 1;
    }
}

/*-------------------------------------------------------------------------*\
* Global function that calls corresponding table method.
\*-------------------------------------------------------------------------*/
#ifndef LUASOCKET_NOGLOBALS
int global_callfromtable(lua_State *L)
{
    p_tags tags = pop_tags(L);
    if (lua_tag(L, 1) != tags->table) lua_error(L, "invalid socket object");
    lua_gettable(L, 1);
    lua_insert(L, 1);
    lua_call(L, lua_gettop(L)-1, LUA_MULTRET);
    return lua_gettop(L);
}
#endif

/*-------------------------------------------------------------------------*\
* Waits for a set of sockets until a condition is met or timeout.
* Lua Input: {input}, {output} [, timeout]
*   {input}: table of sockets to be tested for input
*   {output}: table of sockets to be tested for output
*   timeout: maximum amount of time to wait for condition, in seconds
* Lua Returns: {input}, {output}, err
*   {input}: table with sockets ready for input
*   {output}: table with sockets ready for output
*   err: "timeout" or nil
\*-------------------------------------------------------------------------*/
int global_select(lua_State *L)
{
    p_tags tags = pop_tags(L);
    int ms = lua_isnil(L, 3) ? -1 : (int) (luaL_opt_number(L, 3, -1) * 1000);
    fd_set readfds, *prfds = NULL, writefds, *pwfds = NULL;
    struct timeval tm, *ptm = NULL;
    int ret, dirty = 0;
    unsigned max = 0;
    SOCKET s;
    int byfds, canread, canwrite;
    /* reset the file descriptor sets */
    FD_ZERO(&readfds); FD_ZERO(&writefds); 
    /* all sockets, indexed by socket number, for internal use */
    lua_newtable(L); byfds = lua_gettop(L);
    /* readable sockets table to be returned */
    lua_newtable(L); canread = lua_gettop(L);
    /* writable sockets table to be returned */
    lua_newtable(L); canwrite = lua_gettop(L);
    /* get sockets we will test for readability into fd_set */
    if (lua_istable(L, 1)) {
        lua_pushnil(L);
        while (lua_next(L, 1)) {
            if (lua_tag(L, -1) == tags->table) { /* skip strange fields */
                p_sock sock = get_sock(L, -1, tags, NULL);
                if (sock->sock != INVALID_SOCKET) { /* skip closed sockets */
                    lua_pushnumber(L, sock->sock);
                    lua_pushvalue(L, -2);
                    lua_settable(L, byfds);
                    if (sock->sock > max) max = sock->sock;
                    /* a socket can have unread data in our internal 
                    buffer. in that case, we only call select to find 
                    out which of the other sockets can be written to 
                    or read from immediately. */
                    if (!bf_isempty(sock)) {
                        ms = 0; dirty = 1;
                        lua_pushnumber(L, lua_getn(L, canread) + 1);
                        lua_pushvalue(L, -2);
                        lua_settable(L, canread);
                    } else {
                        FD_SET(sock->sock, &readfds);
                        prfds = &readfds;
                    }
                }
            }
            /* get rid of lua_next value and expose index */
            lua_pop(L, 1);
        }
    } else if (!lua_isnil(L, 1)) luaL_argerror(L, 1, "expected table or nil");
    /* get sockets we will test for writability into fd_set */
    if (lua_istable(L, 2)) {
        lua_pushnil(L);
        while (lua_next(L, 2)) {
            if (lua_tag(L, -1) == tags->table) { /* skip strange fields */
                p_sock sock = get_sock(L, -1, tags, NULL);
                if (sock->sock != INVALID_SOCKET) { /* skip closed sockets */
                    lua_pushnumber(L, sock->sock);
                    lua_pushvalue(L, -2);
                    lua_settable(L, byfds);
                    if (sock->sock > max) max = sock->sock;
                    FD_SET(sock->sock, &writefds);
                    pwfds = &writefds;
                }
            }
            /* get rid of lua_next value and expose index */
            lua_pop(L, 1);
        }
    } else if (!lua_isnil(L, 2)) luaL_argerror(L, 2, "expected table or nil");
    max++;
    /* configure timeout value */
    if (ms >= 0) {
        ptm = &tm; /* ptm == NULL when we don't have timeout */
        /* fill timeval structure */
        tm.tv_sec = ms / 1000;
        tm.tv_usec = (ms % 1000) * 1000;
    }
    /* see if we can read, write or if we timedout */
    ret = select(max, prfds, pwfds, NULL, ptm);
    /* did we timeout? */
    if (ret <= 0 && ms >= 0 && !dirty) { 
        push_error(L, NET_TIMEOUT);
        return 3;
    }
    /* collect readable sockets */
    if (prfds) {
        for (s = 0; s < max; s++) {
            if (FD_ISSET(s, prfds)) {
                lua_pushnumber(L, lua_getn(L, canread) + 1);
                lua_pushnumber(L, s);
                lua_gettable(L, byfds);
                lua_settable(L, canread);
            }
        }
    }
    /* collect writable sockets */
    if (pwfds) {
        for (s = 0; s < max; s++) {
            if (FD_ISSET(s, pwfds)) {
                lua_pushnumber(L, lua_getn(L, canwrite) + 1);
                lua_pushnumber(L, s);
                lua_gettable(L, byfds);
                lua_settable(L, canwrite);
            }
        }
    }
    lua_pushnil(L);
    return 3;
}

/*-------------------------------------------------------------------------*\
* Returns the list of ip addresses associated with a host name
* Lua Input: address
*   address: ip address or hostname to dns lookup
* Lua Returns
*   On success: first IP address followed by a resolved table
*   On error: nil, followed by an error message
\*-------------------------------------------------------------------------*/
static int global_toip(lua_State *L)
{
    const char *address = luaL_check_string(L, 1);
    struct in_addr addr;
    struct hostent *hp;
    if (inet_aton(address, &addr))
        hp = gethostbyaddr((char *) &addr, sizeof(addr), AF_INET);
    else hp = gethostbyname(address);
    if (!hp) {
        lua_pushnil(L);
        lua_pushstring(L, host_strerror());
        return 2;
    }
    addr = *((struct in_addr *) hp->h_addr);
    lua_pushstring(L, inet_ntoa(addr));
    push_resolved(L, hp);
    return 2;
}

/*-------------------------------------------------------------------------*\
* Returns the list of host names associated with an ip address
* Lua Input: address
*   address: ip address or host name to reverse dns lookup
* Lua Returns
*   On success: canonic name followed by a resolved table
*   On error: nil, followed by an error message
\*-------------------------------------------------------------------------*/
static int global_tohostname(lua_State *L)
{
    const char *address = luaL_check_string(L, 1);
    struct in_addr addr;
    struct hostent *hp;
    if (inet_aton(address, &addr)) 
        hp = gethostbyaddr((char *) &addr, sizeof(addr), AF_INET);
    else hp = gethostbyname(address);
    if (!hp) {
        lua_pushnil(L);
        lua_pushstring(L, host_strerror());
        return 2;
    }
    lua_pushstring(L, hp->h_name);
    push_resolved(L, hp);
    return 2;
}

/*-------------------------------------------------------------------------*\
* Send data through a connected UDP socket
* Lua Input: sock, data
*   sock: udp socket
*   data: data to be sent
* Lua Returns
*   On success: nil, followed by the total number of bytes sent
*   On error: error message
\*-------------------------------------------------------------------------*/
static int table_udpsend(lua_State *L)
{
    p_sock sock = pop_sock(L);
    size_t wanted;
    int sent;
    const char *data = luaL_check_lstr(L, 2, &wanted);
    if (!sock->is_connected) lua_error(L, "send on unconnected socket");
    tm_markstart(sock);
    if (tm_timedout(sock, TM_SEND)) {
        push_error(L, NET_TIMEOUT);
        return 1;
    }
    sent = send(sock->sock, data, wanted, 0);
    if (sent >= 0) {
        lua_pushnil(L);
        lua_pushnumber(L, sent);
        return 2;
    } else {
        push_error(L, NET_REFUSED);
        return 1;
    }
}

/*-------------------------------------------------------------------------*\
* Receives a datagram from a UDP socket
* Lua Input: sock [, wanted]
*   sock: client socket created by the connect function
*   wanted: the number of bytes expected (default: LUASOCKET_UDPBUFFERSIZE)
* Lua Returns
*   On success: datagram received, ip and port of sender
*   On error: nil, followed by an error message
\*-------------------------------------------------------------------------*/
static int table_udpreceivefrom(lua_State *L)
{
    p_sock sock = pop_sock(L);
    size_t wanted = (int) luaL_opt_number(L, 2, LUASOCKET_UDPBUFFERSIZE);
    struct sockaddr_in peer;
    size_t peer_len = sizeof(peer);
    unsigned char buffer[LUASOCKET_UDPBUFFERSIZE];
    int got;
    if (sock->is_connected) lua_error(L, "receivefrom on connected socket");
    tm_markstart(sock);
    if (tm_timedout(sock, TM_RECEIVE)) {
        lua_pushnil(L);
        push_error(L, NET_TIMEOUT);
        return 2;
    }
    wanted = MIN(wanted, sizeof(buffer));
    got = recvfrom(sock->sock, buffer, wanted, 0, (SA *) &peer, &peer_len);
    if (got >= 0) {
        lua_pushlstring(L, buffer, got);
        lua_pushstring(L, inet_ntoa(peer.sin_addr));
        lua_pushnumber(L, ntohs(peer.sin_port));
        return 3;
    } else {
        lua_pushnil(L);
        push_error(L, NET_REFUSED);
        return 2;
    }
}

/*-------------------------------------------------------------------------*\
* Receives data from a UDP socket
* Lua Input: sock [, wanted]
*   sock: client socket created by the connect function
*   wanted: the number of bytes expected (default: LUASOCKET_UDPBUFFERSIZE)
* Lua Returns
*   On success: datagram received
*   On error: nil, followed by an error message
\*-------------------------------------------------------------------------*/
static int table_udpreceive(lua_State *L)
{
    p_sock sock = pop_sock(L);
    size_t wanted = (size_t) luaL_opt_number(L, 2, LUASOCKET_UDPBUFFERSIZE);
    unsigned char buffer[LUASOCKET_UDPBUFFERSIZE];
    int got;
    tm_markstart(sock);
    if (tm_timedout(sock, TM_RECEIVE)) {
        lua_pushnil(L);
        push_error(L, NET_TIMEOUT);
        return 2;
    }
    got = recv(sock->sock, buffer, MIN(wanted, sizeof(buffer)), 0);
    if (got >= 0) {
        lua_pushlstring(L, buffer, got);
        return 1;
    } else {
        lua_pushnil(L);
           push_error(L, NET_REFUSED);
        return 2;
    }
}

/*-------------------------------------------------------------------------*\
* Receive data from a TCP socket
* Lua Input: sock [pat_1, pat_2 ... pat_n]
*   sock: client socket created by the connect function
*   pat_i: may be one of the following 
*     "*l": reads a text line, defined as a string of caracters terminates
*       by a LF character, preceded or not by a CR character. This is
*       the default pattern
*     "*lu": reads a text line, terminanted by a CR character only. (Unix mode)
*     "*a": reads until connection closed
*     number: reads 'number' characters from the socket
* Lua Returns
*   On success: one string for each pattern
*   On error: all strings for which there was no error, followed by one
*     nil value for the remaining strings, followed by an error code
\*-------------------------------------------------------------------------*/
static int table_tcpreceive(lua_State *L)
{
    static const char *const modenames[] = {"*l", "*lu", "*a", "*w", NULL};
    const char *mode;
    int err = NET_DONE;
    int arg;
    p_sock sock = pop_sock(L);
    int top = lua_gettop(L);
    tm_markstart(sock);
    /* push default pattern if need be */
    if (top < 2) {
        lua_pushstring(L, "*l");
        top++;
    }
    /* make sure we have enough stack space */
    luaL_checkstack(L, top+LUA_MINSTACK, "too many arguments");
    /* receive all patterns */
    for (arg = 2; arg <= top; arg++) {
        /* if one pattern fails, we just skip all other patterns */
        if (err != NET_DONE) {
            lua_pushnil(L);
            continue;
        }
         if (lua_isnumber(L, arg)) {
            int size = (int) lua_tonumber(L, arg);
            err = receive_raw(L, sock, size);
        } else {
            mode = luaL_opt_string(L, arg, NULL);
            /* get next pattern */
            switch (luaL_findstring(mode, modenames)) {
                /* DOS line mode */
                case 0: err = receive_dosline(L, sock); break;
                /* Unix line mode */
                case 1: err = receive_unixline(L, sock); break;
                /* until closed mode */
                case 2: err = receive_all(L, sock); break;
                /* word */
                case 3: err = receive_word(L, sock); break;
                /* else it is an error */
                default: 
                    luaL_arg_check(L, 0, arg, "invalid receive pattern");
                    break;
            }
        }
    } 
    /* last return is an error code */
    push_error(L, err);
#ifdef _DEBUG
    /* push time elapsed during operation as the last return value */
    lua_pushnumber(L, (sock->tm_end - sock->tm_start)/1000.0);
#endif
    return lua_gettop(L) - top;
}

/*-------------------------------------------------------------------------*\
* Retrieves socket peer name
* Lua Input: sock 
*   sock: socket
* Lua Returns
*   On success: ip address and port of peer
*   On error: nil
\*-------------------------------------------------------------------------*/
static int table_getpeername(lua_State *L)
{
    p_sock sock = pop_sock(L);
    struct sockaddr_in peer;
    size_t peer_len = sizeof(peer);
    if (getpeername(sock->sock, (SA *) &peer, &peer_len) < 0) {
        lua_pushnil(L);
        return 1;
    }
    lua_pushstring(L, inet_ntoa(peer.sin_addr));
    lua_pushnumber(L, ntohs(peer.sin_port));
    return 2;
}

/*-------------------------------------------------------------------------*\
* Retrieves socket local name
* Lua Input: sock 
*   sock: socket
* Lua Returns
*   On success: local ip address and port
*   On error: nil
\*-------------------------------------------------------------------------*/
static int table_getsockname(lua_State *L)
{
    p_sock sock = pop_sock(L);
    struct sockaddr_in local;
    size_t local_len = sizeof(local);
    if (getsockname(sock->sock, (SA *) &local, &local_len) < 0) {
        lua_pushnil(L);
        return 1;
    }
    lua_pushstring(L, inet_ntoa(local.sin_addr));
    lua_pushnumber(L, ntohs(local.sin_port));
    return 2;
}

/*-------------------------------------------------------------------------*\
* Closes a socket.
* Lua Input 
*   sock: socket to be closed
\*-------------------------------------------------------------------------*/
static int table_close(lua_State *L)
{
    /* close socket and set value to INVALID_SOCKET so that 
    ** pop_sock can later detect the use of a closed socket */
    p_sock sock = (p_sock) lua_touserdata(L, -1);
    if (!sock) lua_error(L, "invalid socket object");
    if (sock->sock != INVALID_SOCKET) closesocket(sock->sock);
    sock->sock = INVALID_SOCKET;
    return 0;
}

/*-------------------------------------------------------------------------*\
* Garbage collection fallback for the socket objects. This function 
* makes sure that all collected sockets are closed.
\*-------------------------------------------------------------------------*/
static int gc_table(lua_State *L)
{
    p_tags tags = pop_tags(L);
    p_sock sock = get_selfsock(L, tags, NULL);
    /* sock might have been closed before */
    if (sock->sock != INVALID_SOCKET) {
        closesocket(sock->sock);
        sock->sock = INVALID_SOCKET;
    }
    return 0;
}

/*=========================================================================*\
* Internal functions
\*=========================================================================*/
/*-------------------------------------------------------------------------*\
* Instals a handler to ignore sigpipe. That is, unless the signal had
* already been redefined. This function is not needed on the WinSock2,
* since it's sockets don't raise this signal.
\*-------------------------------------------------------------------------*/
#ifndef WIN32
static void handle_sigpipe(void);
static void handle_sigpipe(void)
{
    struct sigaction new;
    memset(&new, 0, sizeof(new));
    new.sa_handler = SIG_IGN;
    sigaction(SIGPIPE, &new, NULL);
}
#endif

/*-------------------------------------------------------------------------*\
* Tries to create a TCP socket and connect to remote address (address, port)
* Input
*   address: host name or ip address
*   port: port number to bind to
* Returns
*   NULL in case of success, error message otherwise
\*-------------------------------------------------------------------------*/
static const char *tcp_tryconnect(p_sock sock, const char *address, 
    unsigned short port)
{
    struct sockaddr_in remote;
    memset(&remote, 0, sizeof(remote));
    if (inet_aton(address, &remote.sin_addr)) {
        remote.sin_family = AF_INET;
        remote.sin_port = htons(port);
        sock->sock = socket(AF_INET, SOCK_STREAM, 0);
        if (sock->sock == INVALID_SOCKET) return socket_strerror();
        if (connect(sock->sock, (SA *) &remote, sizeof(remote)) < 0) {
            closesocket(sock->sock);
            sock->sock = INVALID_SOCKET;
            return connect_strerror();
        }
    /* go ahead and try by hostname resolution */
    } else {
        struct hostent *hp = gethostbyname(address);
        struct in_addr **addr;
        if (!hp) return host_strerror();
        addr = (struct in_addr **) hp->h_addr_list;
        for (; *addr != NULL; addr++) {
            memcpy(&remote.sin_addr, *addr, sizeof(struct in_addr));
            remote.sin_family = AF_INET;
            remote.sin_port = htons(port);
            sock->sock = socket(AF_INET, SOCK_STREAM, 0);
            if (sock->sock == INVALID_SOCKET) return socket_strerror();
            if (connect(sock->sock, (SA *) &remote, sizeof(remote)) == 0) 
                break;
            closesocket(sock->sock);
            sock->sock = INVALID_SOCKET;
            memset(&remote, 0, sizeof(remote));
        }
    }
    if (sock->sock == INVALID_SOCKET) return connect_strerror();
    return NULL;
}

/*-------------------------------------------------------------------------*\
* Sets the SO_REUSEADDR socket option
* Input
*   sock: socket to set option
\*-------------------------------------------------------------------------*/
void set_reuseaddr(p_sock sock)
{
    int val = 1;
    setsockopt(sock->sock, SOL_SOCKET, SO_REUSEADDR, (char *)&val, sizeof(val));
}

/*-------------------------------------------------------------------------*\
* Set socket options from a table on top of Lua stack.
* Supports SO_KEEPALIVE, SO_DONTROUTE, SO_BROADCAST, and SO_LINGER options.
* Input
*   L: Lua state to use
*   sock: socket to set option
* Returns
*   1 if successful, 0 otherwise
\*-------------------------------------------------------------------------*/
static int set_option(lua_State *L, p_sock sock)
{
    static const char *const optionnames[] = {
        "SO_KEEPALIVE", "SO_DONTROUTE", "SO_BROADCAST", "SO_LINGER", NULL
    };
    const char *option;
    int err;
    if (!lua_isstring(L, -2)) return 0;
    option = lua_tostring(L, -2);
    switch (luaL_findstring(option, optionnames)) {
        case 0: {
            int bool;
            if (!lua_isnumber(L, -1)) 
                lua_error(L, "invalid SO_KEEPALIVE value");
            bool = (int) lua_tonumber(L, -1);
            err = setsockopt(sock->sock, SOL_SOCKET, SO_KEEPALIVE, 
                (char *) &bool, sizeof(bool));
            return err >= 0;
        }
        case 1: {
            int bool;
            if (!lua_isnumber(L, -1))
                lua_error(L, "invalid SO_DONTROUTE value");
            bool = (int) lua_tonumber(L, -1);
            err = setsockopt(sock->sock, SOL_SOCKET, SO_DONTROUTE, 
                (char *) &bool, sizeof(bool));
            return err >= 0;
        }
        case 2: {
            int bool;
            if (!lua_isnumber(L, -1))
                lua_error(L, "invalid SO_BROADCAST value");
            bool = (int) lua_tonumber(L, -1);
            err = setsockopt(sock->sock, SOL_SOCKET, SO_BROADCAST, 
                (char *) &bool, sizeof(bool));
            return err >= 0;
        }
        case 3: {
            struct linger linger;
            if (!lua_istable(L, -1))
                lua_error(L, "invalid SO_LINGER value");
            lua_pushstring(L, "l_onoff");
            lua_gettable(L, -2);
            if (!lua_isnumber(L, -1))
                lua_error(L, "invalid SO_LINGER (l_onoff) value");
            linger.l_onoff = (int) lua_tonumber(L, -1);
            lua_pop(L, 1);
            lua_pushstring(L, "l_linger");
            lua_gettable(L, -2);
            if (!lua_isnumber(L, -1))
                lua_error(L, "invalid SO_LINGER (l_linger) value");
            linger.l_linger = (int) lua_tonumber(L, -1);
            lua_pop(L, 1);
            err = setsockopt(sock->sock, SOL_SOCKET, SO_LINGER, 
                (char *) &linger, sizeof(linger));
            return err >= 0;
        }
        default: return 0;
    }
}


/*-------------------------------------------------------------------------*\
* Tries to create a TCP socket and bind it to (address, port)
* Input
*   address: host name or ip address
*   port: port number to bind to
*   backlog: backlog to set
* Returns
*   NULL in case of success, error message otherwise
\*-------------------------------------------------------------------------*/
static const char *tcp_trybind(p_sock sock, const char *address, 
    unsigned short port, int backlog)
{
    struct sockaddr_in local;
    memset(&local, 0, sizeof(local));
    local.sin_port = htons(port);
    local.sin_family = AF_INET;
    local.sin_addr.s_addr = htonl(INADDR_ANY);
    sock->sock = socket(AF_INET, SOCK_STREAM, 0);
    if (sock->sock == INVALID_SOCKET) return socket_strerror();
    set_reuseaddr(sock);
    /* address is either wildcard or a valid ip address */
    if (!strcmp(address, "*") || inet_aton(address, &local.sin_addr)) {
        if (bind(sock->sock, (SA *) &local, sizeof(local)) < 0) {
            closesocket(sock->sock);
            sock->sock = INVALID_SOCKET;
            return bind_strerror();
        }
    /* otherwise, proceed with domain name resolution */
    } else {
        struct hostent *hp = gethostbyname(address);
        struct in_addr **addr;
        if (!hp) return host_strerror();
        addr = (struct in_addr **) hp->h_addr_list;
        for (; *addr != NULL; addr++) {
            memcpy(&local.sin_addr, *addr, sizeof(struct in_addr));
            if (bind(sock->sock, (SA *) &local, sizeof(local)) < 0) {
                closesocket(sock->sock);
                sock->sock = socket(AF_INET, SOCK_DGRAM, 0);
                if (sock->sock == INVALID_SOCKET) return socket_strerror();
                set_reuseaddr(sock);
            } else break;
        }
        if (*addr == NULL) return bind_strerror();
    }
    /* set connection queue length */
    if (listen(sock->sock, backlog) < 0) {
        closesocket(sock->sock);
        sock->sock = INVALID_SOCKET;
        return "listen error";
    }
    /* no errors found */
    return NULL;
}

/*-------------------------------------------------------------------------*\
* Tries to bind the UDP socket to (address, port)
* Input
*   address: host name or ip address
*   port: port number to bind to
* Returns
*   NULL in case of success, error message otherwise
\*-------------------------------------------------------------------------*/
static const char *udp_setsockname(p_sock sock, const char *address, 
    unsigned short port)
{
    struct sockaddr_in local;
    memset(&local, 0, sizeof(local));
    local.sin_port = htons(port);
    local.sin_family = AF_INET;
    local.sin_addr.s_addr = htonl(INADDR_ANY);
    set_reuseaddr(sock);
    /* address is either wildcard or a valid ip address */
    if (!strcmp(address, "*") || inet_aton(address, &local.sin_addr)) {
        if (bind(sock->sock, (SA *) &local, sizeof(local)) < 0) {
            closesocket(sock->sock);
            sock->sock = INVALID_SOCKET;
            return bind_strerror();
        }
    /* otherwise, proceed with domain name resolution */
    } else {
        struct hostent *hp = gethostbyname(address);
        struct in_addr **addr;
        if (!hp) return host_strerror();
        addr = (struct in_addr **) hp->h_addr_list;
        for (; *addr != NULL; addr++) {
            memcpy(&local.sin_addr, *addr, sizeof(struct in_addr));
            if (bind(sock->sock, (SA *) &local, sizeof(local)) < 0) {
                closesocket(sock->sock);
                sock->sock = socket(AF_INET, SOCK_DGRAM, 0);
                if (sock->sock == INVALID_SOCKET) return socket_strerror();
                set_reuseaddr(sock);
            } else break;
        }
        if (*addr == NULL) return bind_strerror();
    }
    /* no errors found */
    return NULL;
}

/*-------------------------------------------------------------------------*\
* Tries to connect a UDP to remote address (address, port)
* Input
*   address: host name or ip address
*   port: port number to bind to
* Returns
*   NULL in case of success, error message otherwise
\*-------------------------------------------------------------------------*/
static const char *udp_setpeername(p_sock sock, const char *address, 
    unsigned short port)
{
    struct sockaddr_in local;
    memset(&local, 0, sizeof(local));
    local.sin_port = htons(port);
    local.sin_family = AF_INET;
    local.sin_addr.s_addr = htonl(INADDR_ANY);
    /* address is a valid ip address */
    if (inet_aton(address, &local.sin_addr)) {
        if (connect(sock->sock, (SA *) &local, sizeof(local)) < 0) {
            closesocket(sock->sock);
            sock->sock = INVALID_SOCKET;
            return connect_strerror();
        }
    /* otherwise, proceed with domain name resolution */
    } else {
        struct hostent *hp = gethostbyname(address);
        struct in_addr **addr;
        if (!hp) return host_strerror();
        addr = (struct in_addr **) hp->h_addr_list;
        for (; *addr != NULL; addr++) {
            memcpy(&local.sin_addr, *addr, sizeof(struct in_addr));
            if (connect(sock->sock, (SA *) &local, sizeof(local)) < 0) {
                closesocket(sock->sock);
                sock->sock = socket(AF_INET, SOCK_DGRAM, 0);
                if (sock->sock == INVALID_SOCKET) return socket_strerror();
            } else break;
        }
        if (*addr == NULL) return connect_strerror();
    }
    /* no errors found */
    return NULL;
}

/*=========================================================================*\
* Timeout management functions
\*=========================================================================*/
/*-------------------------------------------------------------------------*\
* Determines how much time we have left for the current io operation
* an IO write operation.
* Input
*   sock: socket structure being used in operation
* Returns
*   the number of ms left or -1 if there is no time limit
\*-------------------------------------------------------------------------*/
static int tm_gettimeleft(p_sock sock)
{
    /* no timeout */
    if (sock->tm_block < 0 && sock->tm_return < 0)
        return -1;
    /* there is no block timeout, we use the return timeout */
    else if (sock->tm_block < 0)
        return MAX(sock->tm_return - tm_gettime() + sock->tm_start, 0);
    /* there is no return timeout, we use the block timeout */
    else if (sock->tm_return < 0)
        return sock->tm_block;
    /* both timeouts are specified */
    else return MIN(sock->tm_block, 
            MAX(sock->tm_return - tm_gettime() + sock->tm_start, 0));
}

/*-------------------------------------------------------------------------*\
* Determines if we have a timeout condition or if we can proceed with
* an IO operation.
* Input
*   sock: socket structure being used in operation
*   mode: TM_RECEIVE or TM_SEND
* Returns
*   1 if we can proceed, 0 if a timeout has occured
\*-------------------------------------------------------------------------*/
static int tm_timedout(p_sock sock, int mode)
{
    fd_set fds;
    int ret;
    fd_set *preadfds = NULL, *pwritefds = NULL;
    struct timeval tm;
    struct timeval *ptm = NULL;
    /* find out how much time we have left, in ms */
    int ms = tm_gettimeleft(sock);
    /* fill file descriptor set */
    FD_ZERO(&fds); FD_SET(sock->sock, &fds);
    /* fill timeval structure */
    tm.tv_sec = ms / 1000;
    tm.tv_usec = (ms % 1000) * 1000;
    /* define function parameters */
    if (ms >= 0) ptm = &tm; /* ptm == NULL when we don't have timeout */
    if (mode == TM_RECEIVE) preadfds = &fds;
    else pwritefds = &fds;
    /* see if we can read, write or if we timedout */
    ret = select(sock->sock+1, preadfds, pwritefds, NULL, ptm);
#ifdef _DEBUG
    /* store end time for this operation next call to OS */
    sock->tm_end = tm_gettime();
#endif
    return ret <= 0;
}

/*-------------------------------------------------------------------------*\
* Marks the operation start time in sock structure
* Input
*   sock: socket structure being used in operation
\*-------------------------------------------------------------------------*/
static void tm_markstart(p_sock sock)
{
    sock->tm_start = tm_gettime();
#ifdef _DEBUG
    sock->tm_end = sock->tm_start;
#endif
}

/*-------------------------------------------------------------------------*\
* Gets time in ms, relative to system startup.
* Returns
*   time in ms.
\*-------------------------------------------------------------------------*/
static int tm_gettime(void) 
{
#ifdef WIN32
    return GetTickCount();
#else
    struct tms t;
    return (times(&t)*1000)/CLK_TCK;
#endif
}

/*=========================================================================*\
* Buffered I/O management functions
\*=========================================================================*/
/*-------------------------------------------------------------------------*\
* Determines of there is any data in the read buffer
* Input
*   sock: socket structure being used in operation
* Returns
*   1 if empty, 0 if there is data
\*-------------------------------------------------------------------------*/
static int bf_isempty(p_sock sock)
{
    return sock->bf_first >= sock->bf_last;
}

/*-------------------------------------------------------------------------*\
* Skip a given number of bytes in read buffer
* Input
*   sock: socket structure being used in operation
*   length: number of bytes to skip
\*-------------------------------------------------------------------------*/
static void bf_skip(p_sock sock, int length)
{
    sock->bf_first += length;
    if (bf_isempty(sock)) sock->bf_first = sock->bf_last = 0;
}

/*-------------------------------------------------------------------------*\
* Return any data avilable in buffer, or get more data from transport layer
* if buffer is empty.
* Input
*   sock: socket structure being used in operation
* Output
*   length: number of bytes available in buffer
* Returns
*   pointer to start of data
\*-------------------------------------------------------------------------*/
static const unsigned char *bf_receive(p_sock sock, int *length)
{
    if (bf_isempty(sock)) {
        int got = recv(sock->sock, sock->bf_buffer, LUASOCKET_TCPBUFFERSIZE, 0);
        sock->bf_first = 0;
        if (got >= 0) sock->bf_last = got;
        else sock->bf_last = 0;
    }
    *length = sock->bf_last - sock->bf_first;
    return sock->bf_buffer + sock->bf_first;
}

/*=========================================================================*\
* These are the function that are called for each I/O pattern
* The read patterns leave their result on the Lua stack
\*=========================================================================*/
/*-------------------------------------------------------------------------*\
* Sends a raw block of data through a socket. The operations are all
* non-blocking and the function respects the timeout values in sock.
* Input
*   sock: socket structure being used in operation
*   data: buffer to be sent
*   wanted: number of bytes in buffer
* Output
*   total: Number of bytes written
* Returns
*   operation error code. NET_DONE, NET_TIMEOUT or NET_CLOSED
\*-------------------------------------------------------------------------*/
static int send_raw(p_sock sock, const char *data, int wanted, int *total)
{
    int put = 0;
    *total = 0;
    while (wanted > 0) {
        if (tm_timedout(sock, TM_SEND)) return NET_TIMEOUT;
        put = send(sock->sock, data, wanted, 0);
        if (put <= 0) {
#ifdef WIN32
            /* a bug in WinSock forces us to do a busy wait until we manage
            ** to write, because select returns immediately even though it
            ** should have blocked us until we could write... */
            if (put < 0 && WSAGetLastError() == WSAEWOULDBLOCK)
                continue;
#endif
#ifdef __CYGWIN__
            /* this is for CYGWIN, which is like Unix but with Win32 Bugs */
            if (put < 0 && errno == EWOULDBLOCK)
                continue;
#endif
            
            return NET_CLOSED;
        }
        wanted -= put;
        data += put;
        *total += put;
    }
    return NET_DONE;
}

/*-------------------------------------------------------------------------*\
* Reads a raw block of data from a socket. The operations are all
* non-blocking and the function respects the timeout values in sock.
* Input
*   sock: socket structure being used in operation
*   wanted: number of bytes to be read
* Returns
*   operation error code. NET_DONE, NET_TIMEOUT or NET_CLOSED
\*-------------------------------------------------------------------------*/
static int receive_raw(lua_State *L, p_sock sock, int wanted)
{
    int got = 0;
    const unsigned char *buffer = NULL;
    luaL_Buffer b;
    luaL_buffinit(L, &b);
    while (wanted > 0) {
        if (bf_isempty(sock) && tm_timedout(sock, TM_RECEIVE)) {
            luaL_pushresult(&b);
            return NET_TIMEOUT;
        }
        buffer = bf_receive(sock, &got);
        if (got <= 0) {
            luaL_pushresult(&b);
            return NET_CLOSED;
        }
        got = MIN(got, wanted);
        luaL_addlstring(&b, buffer, got);
        bf_skip(sock, got);
        wanted -= got;
    }
    luaL_pushresult(&b);
    return NET_DONE;
}

/*-------------------------------------------------------------------------*\
* Reads everything until the connection is closed
* Input
*   sock: socket structure being used in operation
* Result
*   operation error code. NET_DONE, NET_TIMEOUT
\*-------------------------------------------------------------------------*/
static int receive_all(lua_State *L, p_sock sock)
{
    int got = 0;
    const unsigned char *buffer = NULL;
    luaL_Buffer b;
    luaL_buffinit(L, &b);
    for ( ;; ) {
        if (bf_isempty(sock) && tm_timedout(sock, TM_RECEIVE)) {
            luaL_pushresult(&b);
            return NET_TIMEOUT;
        } 
        buffer = bf_receive(sock, &got);
        if (got <= 0) { 
            luaL_pushresult(&b);
            return NET_DONE;
        }
        luaL_addlstring(&b, buffer, got);
        bf_skip(sock, got);
    }
}

/*-------------------------------------------------------------------------*\
* Reads a line terminated by a CR LF pair or just by a LF. The CR and LF 
* are not returned by the function and are discarded from the stream. All 
* operations are non-blocking and the function respects the timeout 
* values in sock.
* Input
*   sock: socket structure being used in operation
* Result
*   operation error code. NET_DONE, NET_TIMEOUT or NET_CLOSED
\*-------------------------------------------------------------------------*/
static int receive_dosline(lua_State *L, p_sock sock)
{
    int got, pos;
    const unsigned char *buffer = NULL;
    luaL_Buffer b;
    luaL_buffinit(L, &b);
    for ( ;; ) {
        if (bf_isempty(sock) && tm_timedout(sock, TM_RECEIVE)) {
            luaL_pushresult(&b);
            return NET_TIMEOUT;
        }
        buffer = bf_receive(sock, &got);
        if (got <= 0) {
            luaL_pushresult(&b);
            return NET_CLOSED;
        }
        pos = 0;
        while (pos < got && buffer[pos] != '\n') {
            /* we ignore all \r's */
            if (buffer[pos] != '\r') luaL_putchar(&b, buffer[pos]);
            pos++;
        }
        if (pos < got) {
            luaL_pushresult(&b);
            bf_skip(sock, pos+1); /* skip '\n' too */
            return NET_DONE;
        } else bf_skip(sock, pos);
    }
}

/*-------------------------------------------------------------------------*\
* Reads a line terminated by a LF character, which is not returned by
* the function, and is skipped in the stream. All operations are 
* non-blocking and the function respects the timeout values in sock.
* Input
*   sock: socket structure being used in operation
* Returns
*   operation error code. NET_DONE, NET_TIMEOUT or NET_CLOSED
\*-------------------------------------------------------------------------*/
static int receive_unixline(lua_State *L, p_sock sock)
{
    int got, pos;
    const unsigned char *buffer = NULL;
    luaL_Buffer b;
    luaL_buffinit(L, &b);
    for ( ;; ) {
        if (bf_isempty(sock) && tm_timedout(sock, TM_RECEIVE)) {
            luaL_pushresult(&b);
            return NET_TIMEOUT;
        }
        buffer = bf_receive(sock, &got);
        if (got <= 0) {
            luaL_pushresult(&b);
            return NET_CLOSED;
        }
        pos = 0;
        while (pos < got && buffer[pos] != '\n') pos++;
           luaL_addlstring(&b, buffer, pos);
        if (pos < got) {
            luaL_pushresult(&b);
            bf_skip(sock, pos+1); /* skip '\n' too */
            return NET_DONE;
        } else bf_skip(sock, pos);
    }
}

/*-------------------------------------------------------------------------*\
* Reads a word (maximal sequence of non--white-space characters), skipping
* white-spaces if needed.
* Input
*   sock: socket structure being used in operation
* Result
*   operation error code. NET_DONE, NET_TIMEOUT or NET_CLOSED
\*-------------------------------------------------------------------------*/
static int receive_word(lua_State *L, p_sock sock)
{
    int pos, got;
    const unsigned char *buffer = NULL;
    luaL_Buffer b;
    luaL_buffinit(L, &b);
    /* skip leading white-spaces */
    for ( ;; ) {
        if (bf_isempty(sock) && tm_timedout(sock, TM_RECEIVE)) {
            lua_pushstring(L, "");
            return NET_TIMEOUT;
        }
        buffer = bf_receive(sock, &got);
        if (got <= 0) {
            lua_pushstring(L, "");
            return NET_CLOSED;
        }
        pos = 0;
        while (pos < got && isspace(buffer[pos])) pos++;
        bf_skip(sock, pos);
        if (pos < got) { 
            buffer += pos;
            got -= pos;
            pos = 0;
            break;
        }
    }
    /* capture word */
    for ( ;; ) {
        while (pos < got && !isspace(buffer[pos])) pos++;
        luaL_addlstring(&b, buffer, pos);
        bf_skip(sock, pos);
        if (pos < got) {
           luaL_pushresult(&b);
           return NET_DONE;
        }
        if (bf_isempty(sock) && tm_timedout(sock, TM_RECEIVE)) {
            luaL_pushresult(&b);
            return NET_TIMEOUT;
        }
        buffer = bf_receive(sock, &got);
        if (got <= 0) {
            luaL_pushresult(&b);
            return NET_CLOSED;
        }
        pos = 0;
    }
}

/*=========================================================================*\
* Module exported functions
\*=========================================================================*/
/*-------------------------------------------------------------------------*\
* Initializes the library interface with Lua and the socket library.
* Defines the symbols exported to Lua.
\*-------------------------------------------------------------------------*/
LUASOCKET_API int lua_socketlibopen(lua_State *L)
{
    struct luaL_reg funcs[] = {
        {"bind", global_tcpbind},
        {"connect", global_tcpconnect},
        {"select", global_select},
        {"toip", global_toip},
        {"tohostname", global_tohostname},
        {"udpsocket", global_udpsocket},
    };
    unsigned int i;
    /* declare new Lua tags for used userdata values */
    p_tags tags = (p_tags) lua_newuserdata(L, sizeof(t_tags));
    tags->client = lua_newtag(L);
    tags->server = lua_newtag(L);
    tags->table = lua_newtag(L);
    tags->udp = lua_newtag(L);
    /* global functions exported */
    for (i = 0; i < sizeof(funcs)/sizeof(funcs[0]); i++) {
        lua_pushvalue(L, -1);
        lua_pushcclosure(L, funcs[i].func, 1);
        lua_setglobal(L, funcs[i].name);
    }
    /* socket garbage collection */
    lua_pushvalue(L, -1);
    lua_pushcclosure(L, gc_table, 1);
    lua_settagmethod(L, tags->table, "gc");
#ifdef WIN32
    /* WinSock needs special initialization */
    if (!winsock_open()) return 0;
#else
    /* avoid getting killed by a SIGPIPE signal thrown by send */
    handle_sigpipe();
#endif
#ifdef _DEBUG
    /* test support functions */
    lua_pushcfunction(L, global_sleep); lua_setglobal(L, "_sleep");
    lua_pushcfunction(L, global_time); lua_setglobal(L, "_time");
#endif
#ifndef LUASOCKET_NOGLOBALS
    {
        char *global[] = {
            "accept", "close", "getpeername", 
            "getsockname", "receive", "send", 
            "receivefrom", "sendto"
        };
        unsigned int i;
        for (i = 0; i < sizeof(global)/sizeof(char *); i++) {
            lua_pushstring(L, global[i]);
            lua_pushvalue(L, -2);
            lua_pushcclosure(L, global_callfromtable, 2);
            lua_setglobal(L, global[i]);
        }
    }
#endif
    /* remove tags userdatum from stack */
    lua_pop(L, 1);
    return 1;
}

/*=========================================================================*\
* Lua Stack manipulation functions 
\*=========================================================================*/
/*-------------------------------------------------------------------------*\
* Creates a t_sock structure with default values for a client sock.
* Pushes the Lua table with sock fields and appropriate methods
* Input
*   tags: tags structure
* Returns
*   pointer to allocated t_sock structure, NULL in case of error
\*-------------------------------------------------------------------------*/
static p_sock push_clienttable(lua_State *L, p_tags tags)
{
    static struct luaL_reg funcs[] = {
        {"close", table_close},
        {"getsockname", table_getsockname},
        {"getpeername", table_getpeername},
        {"receive", table_tcpreceive},
        {"send", table_tcpsend},
        {"timeout", table_timeout},
    };
    unsigned int i;
    p_sock sock = (p_sock) lua_newuserdata(L, sizeof(t_sock));
    lua_settag(L, tags->client);
    lua_newtable(L); lua_settag(L, tags->table);
    lua_pushstring(L, P_SOCK);
    lua_pushvalue(L, -3);
    lua_settable(L, -3);
    sock->sock = INVALID_SOCKET;
    sock->is_connected = 0;
    sock->tm_block = -1;
    sock->tm_return = -1;
    sock->bf_first = sock->bf_last = 0;
    for (i = 0; i < sizeof(funcs)/sizeof(funcs[0]); i++) {
        lua_pushstring(L, funcs[i].name);
        lua_pushvalue(L, -3);
        lua_pushcclosure(L, funcs[i].func, 1);
        lua_settable(L, -3);
    }
    return sock;
}

/*-------------------------------------------------------------------------*\
* Creates a t_sock structure with default values for a server sock.
* Pushes the Lua table with sock fields and appropriate methods
* Input
*   tags: tags structure
* Returns
*   pointer to allocated t_sock structure, NULL in case of error
\*-------------------------------------------------------------------------*/
static p_sock push_servertable(lua_State *L, p_tags tags)
{
    static struct luaL_reg funcs[] = {
        {"close", table_close},
        {"getsockname", table_getsockname},
        {"timeout", table_timeout},
    };
    unsigned int i;
    p_sock sock = (p_sock) lua_newuserdata(L, sizeof(t_sock));
    lua_settag(L, tags->server);
    lua_newtable(L); lua_settag(L, tags->table);
    lua_pushstring(L, P_SOCK);
    lua_pushvalue(L, -3);
    lua_settable(L, -3);
    sock->sock = INVALID_SOCKET;
    sock->tm_block = -1;
    sock->tm_return = -1;
    sock->bf_first = sock->bf_last = 0;
    for (i = 0; i < sizeof(funcs)/sizeof(funcs[0]); i++) {
        lua_pushstring(L, funcs[i].name);
        lua_pushvalue(L, -3);
        lua_pushcclosure(L, funcs[i].func, 1);
        lua_settable(L, -3);
    }
    /* the accept method is different, it needs the tags closure too */
    lua_pushstring(L, "accept");
#ifdef LUASOCKET_41FRIENDLY
    lua_newuserdatabox(L, tags);
#else
    lua_pushuserdata(L, tags);
#endif
    lua_pushvalue(L, -4);
    lua_pushcclosure(L, table_tcpaccept, 2);
    lua_settable(L, -3);
    return sock;
}

/*-------------------------------------------------------------------------*\
* Creates a t_sock structure with default values for a udp sock.
* Pushes the Lua table with sock fields and appropriate methods
* Input
*   tags: tags structure
* Returns
*   pointer to allocated t_sock structure, NULL in case of error
\*-------------------------------------------------------------------------*/
static p_sock push_udptable(lua_State *L, p_tags tags)
{
    static struct luaL_reg funcs[] = {
        {"sendto", table_udpsendto},
        {"setpeername", table_udpsetpeername},
        {"setsockname", table_udpsetsockname},
        {"getpeername", table_getpeername},
        {"getsockname", table_getsockname},
        {"receivefrom", table_udpreceivefrom},
        {"receive", table_udpreceive},
        {"send", table_udpsend},
        {"close", table_close},
        {"timeout", table_timeout},
    };
    unsigned int i;
    p_sock sock = (p_sock) lua_newuserdata(L, sizeof(t_sock));
    lua_settag(L, tags->udp);
    lua_newtable(L); lua_settag(L, tags->table);
    lua_pushstring(L, P_SOCK);
    lua_pushvalue(L, -3);
    lua_settable(L, -3);
    sock->sock = socket(AF_INET, SOCK_DGRAM, 0);
    if (sock->sock == INVALID_SOCKET) {
        lua_pushnil(L);
        lua_pushstring(L, socket_strerror());
        return NULL;
    }
    sock->is_connected = 0;
    sock->tm_block = -1;
    sock->tm_return = -1;
    sock->bf_first = sock->bf_last = 0;
    for (i = 0; i < sizeof(funcs)/sizeof(funcs[0]); i++) {
        lua_pushstring(L, funcs[i].name);
        lua_pushvalue(L, -3);
        lua_pushcclosure(L, funcs[i].func, 1);
        lua_settable(L, -3);
    }
    return sock;
}

/*-------------------------------------------------------------------------*\
* Passes all resolver information to Lua as a table
* Input
*   hp: hostent structure returned by resolver
\*-------------------------------------------------------------------------*/
static void push_resolved(lua_State *L, struct hostent *hp)
{
    char **alias;
    struct in_addr **addr;
    int i, resolved;

    lua_newtable(L); resolved = lua_gettop(L);

    lua_pushstring(L, "name");
    lua_pushstring(L, hp->h_name);
    lua_settable(L, resolved);

    lua_pushstring(L, "ip");
    lua_pushstring(L, "alias");

    i = 1;
    alias = hp->h_aliases;
    lua_newtable(L);
    while (*alias) {
        lua_pushnumber(L, i);
        lua_pushstring(L, *alias);
        lua_settable(L, -3);
        i++; alias++;
    }
    lua_settable(L, resolved);

    i = 1;
    lua_newtable(L);
    addr = (struct in_addr **) hp->h_addr_list;
    while (*addr) {
        lua_pushnumber(L, i);
        lua_pushstring(L, inet_ntoa(**addr));
        lua_settable(L, -3);
        i++; addr++;
    }
    lua_settable(L, resolved);
}

/*-------------------------------------------------------------------------*\
* Passes an error code to Lua. The NET_DONE error is translated to nil.
* Input
*   err: error code to be passed to Lua
\*-------------------------------------------------------------------------*/
static void push_error(lua_State *L, int err)
{
    switch (err) { 
        case NET_DONE:
            lua_pushnil(L);
            break;
        case NET_TIMEOUT:    
            lua_pushstring(L, "timeout");
            break;
        case NET_CLOSED:    
            lua_pushstring(L, "closed");
            break;
        case NET_REFUSED:    
            lua_pushstring(L, "refused");
            break;
    }
}

static p_tags pop_tags(lua_State *L)
{
    p_tags tags = (p_tags) lua_touserdata(L, -1);
    if (!tags) lua_error(L, "invalid closure! (probably misuse of library)");
    lua_pop(L, 1);
    return tags;
}

static p_sock pop_sock(lua_State *L)
{
    p_sock sock = (p_sock) lua_touserdata(L, -1);
    if (!sock) lua_error(L, "invalid socket object");
    if (sock->sock == INVALID_SOCKET) 
        lua_error(L, "operation on closed socket");
    lua_pop(L, 1);
    return sock;
}

static p_sock get_sock(lua_State *L, int s, p_tags tags, int *tag)
{
    p_sock sock;
    if (lua_tag(L, s) != tags->table) lua_error(L, "invalid socket object");
    lua_pushstring(L, P_SOCK);
    lua_gettable(L, s > 0 ? s : s-1);
    sock = lua_touserdata(L, -1);
    if (!sock) lua_error(L, "invalid socket object");
    if (tag) *tag = lua_tag(L, -1);
    lua_pop(L, 1);
    return sock;
}

static p_sock get_selfsock(lua_State *L, p_tags tags, int *tag)
{
    return get_sock(L, 1, tags, tag);
}

/*=========================================================================*\
* WinSock2 specific functions.
\*=========================================================================*/
#ifdef WIN32
/*-------------------------------------------------------------------------*\
* Initializes WinSock2 library.
* Returns
*   1 in case of success. 0 in case of error.
\*-------------------------------------------------------------------------*/
static int winsock_open(void)
{
    WORD wVersionRequested;
    WSADATA wsaData;
    int err; 
    wVersionRequested = MAKEWORD(2, 0); 
    err = WSAStartup(wVersionRequested, &wsaData );
    if (err != 0) {
        return 0;
    } 
    if (LOBYTE(wsaData.wVersion) != 2 || HIBYTE(wsaData.wVersion) != 0) {
        WSACleanup();
        return 0; 
    }
    return 1;
}

/*-------------------------------------------------------------------------*\
* Put socket into blocking mode.
\*-------------------------------------------------------------------------*/
static void set_blocking(p_sock sock)
{
    u_long argp = 0;
    ioctlsocket(sock->sock, FIONBIO, &argp);
}

/*-------------------------------------------------------------------------*\
* Put socket into non-blocking mode.
\*-------------------------------------------------------------------------*/
static void set_nonblocking(p_sock sock)
{
    u_long argp = 1;
    ioctlsocket(sock->sock, FIONBIO, &argp);
}

/*-------------------------------------------------------------------------*\
* Returns a string describing the last host manipulation error.
\*-------------------------------------------------------------------------*/
static char *host_strerror(void)
{
    switch (WSAGetLastError()) {
        case HOST_NOT_FOUND: return "host not found";
        case NO_ADDRESS: return "unable to resolve host name";
        case NO_RECOVERY: return "name server error";
        case TRY_AGAIN: return "name server unavailable, try again later.";
        default: return "unknown error";
    }
}

/*-------------------------------------------------------------------------*\
* Returns a string describing the last socket manipulation error.
\*-------------------------------------------------------------------------*/
static char *socket_strerror(void)
{
    switch (WSAGetLastError()) {
        case WSANOTINITIALISED: return "not initialized";
        case WSAENETDOWN: return "network is down";
        case WSAEMFILE: return "descriptor table is full";
        case WSAENOBUFS: return "insufficient buffer space";
        default: return "unknown error";
    }
}

/*-------------------------------------------------------------------------*\
* Returns a string describing the last bind operation error.
\*-------------------------------------------------------------------------*/
static char *bind_strerror(void)
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

/*-------------------------------------------------------------------------*\
* Returns a string describing the last connect operationerror.
\*-------------------------------------------------------------------------*/
static char *connect_strerror(void)
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
#else

/*=========================================================================*\
* BSD specific functions.
\*=========================================================================*/
/*-------------------------------------------------------------------------*\
* Put socket into blocking mode.
\*-------------------------------------------------------------------------*/
static void set_blocking(p_sock sock)
{
    int flags = fcntl(sock->sock, F_GETFL, 0);
    flags &= (~(O_NONBLOCK));
    fcntl(sock->sock, F_SETFL, flags);
}

/*-------------------------------------------------------------------------*\
* Put socket into non-blocking mode.
\*-------------------------------------------------------------------------*/
static void set_nonblocking(p_sock sock)
{
    int flags = fcntl(sock->sock, F_GETFL, 0);
    flags |= O_NONBLOCK;
    fcntl(sock->sock, F_SETFL, flags);
}

/*-------------------------------------------------------------------------*\
* Returns a string describing the last host manipulation error.
\*-------------------------------------------------------------------------*/
static char *host_strerror(void)
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
static char *socket_strerror(void)
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
static char *bind_strerror(void)
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
static char *connect_strerror(void)
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
#endif

/*-------------------------------------------------------------------------*\
* Some systems do not provide this so that we provide our own. It's not
* marvelously fast, but it works just fine.
\*-------------------------------------------------------------------------*/
#ifdef LUASOCKET_ATON
static int inet_aton(const char *cp, struct in_addr *inp)
{
    unsigned int a = 0, b = 0, c = 0, d = 0;
    int n = 0, r;
    unsigned long int addr = 0;
    r = sscanf(cp, "%u.%u.%u.%u%n", &a, &b, &c, &d, &n);
    if (r == 0 || n == 0) return 0;
    cp += n; 
    if (*cp) return 0;
    if (a > 255 || b > 255 || c > 255 || d > 255) return 0;
    if (inp) {
        addr += a; addr <<= 8;
        addr += b; addr <<= 8;
        addr += c; addr <<= 8;
        addr += d;
        inp->s_addr = htonl(addr);
    }
    return 1;
}
#endif

