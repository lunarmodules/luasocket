/*=========================================================================*\
* TCP/IP bind for the Lua language
* Diego Nehab
* 26/11/1999
*
* Module: LSOCK.C
*
* This module is part of an effort to make the most important features
* of the TCP/IP protocol available for Lua scripts.
* The main intent of the project was the distribution with the CGILua
* toolkit, in which is is used to implement the SMTP client functions.
* The Lua interface to TCP/IP follows the BSD TCP/IP API closely, 
* trying to simplify all tasks involved in setting up a client connection 
* and simple server connections. 
* The provided IO routines, send and receive, follow the Lua style, being 
* very similar to the read and write functions found in that language.
* The module implements both a BSD bind and a Winsock2 bind, and has 
* been tested on several Unix flavors, as well as Windows 98 and NT. 
\*=========================================================================*/

/*=========================================================================*\
* Common include files
\*=========================================================================*/
#include <stdio.h>
#include <stdlib.h>
#include <errno.h>
#include <string.h>
#include <signal.h>

#include <assert.h>

#define LUA_REENTRANT

#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>

#include "lsock.h"

/*=========================================================================*\
* WinSock2 include files
\*=========================================================================*/
#ifdef WIN32
#include <winsock2.h>
#include <winbase.h>

/*=========================================================================*\
* BSD include files
\*=========================================================================*/
#else
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
/* for some reason, bcopy and it's friends are not defined automatically
** on the IRIX plataforms... */
#ifdef __sgi
#include <bstring.h>
#endif
#endif

/*=========================================================================*\
* Datatype compatibilization and some simple changes
\*=========================================================================*/
#ifndef WIN32
#define closesocket close		/* WinSock2 has a closesock function instead 
								** of using the regular close function */
#define SOCKET int				/* it defines a SOCKET type instead of
								** using an integer file descriptor */
#define INVALID_SOCKET (-1)		/* and uses the this macro to represent and 
								** invalid socket */
#ifndef INADDR_NONE				/* some unix flavours don't define this */
#define INADDR_NONE (-1)
#endif
#ifndef CLK_TCK					/* SunOS, for instance, does not define */
#define CLK_TCK 60				/* CLK_TCK */
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
#define NET_DONE -1				/* operation completed successfully */
#define NET_TIMEOUT 0			/* operation timed out */
#define NET_CLOSED 1			/* the connection has been closed */

/*-------------------------------------------------------------------------*\
* As far as a Lua script is concerned, there are two kind of objects
* representing a socket.  A client socket is an object created by the
* function connect, and implementing the methods send, receive, timeout
* and close.  A server socket is an object created by the function bind,
* and implementing the methods listen, accept and close.  Lua tag values
* for these objects are created in the lua_socklibopen function, and 
* passed as closure values (first argumnents to every library function, 
# because we can't have any global variables.
\*-------------------------------------------------------------------------*/
#define CLIENT_TAG 1 
#define SERVER_TAG 2
#define FIRST_PAR 3

/*-------------------------------------------------------------------------*\
* Both socket types are stored in the same structure to simplify
* implementation. The tag value used is different, though. The timeout
* fields are not used for the server socket object.
* There are two timeout values. The block timeout specifies the maximum
* time the any IO operation performed by luasock can be blocked waiting 
* for completion. The return timeout specifies the maximum time a Lua script 
* can be blocked waiting for an luasock IO operation to complete.
\*-------------------------------------------------------------------------*/
typedef struct t_sock {
	SOCKET sock;				/* operating system socket object */
	int b;						/* block timeout in ms */
	int r;						/* return timeout in ms */
	int blocking;				/* is this socket in blocking mode? */
} t_sock;
typedef t_sock *p_sock;

/*-------------------------------------------------------------------------*\
* Macros and internal declarations
\*-------------------------------------------------------------------------*/
/* internal function prototypes */
#include "sock.h"

/* return time since marked start in ms */
#define time_since(start) (get_time()-start)

/* min and max macros */
#ifndef min
#define min(x, y) ((x) < (y) ? x : y)
#endif
#ifndef max
#define max(x, y) ((x) > (y) ? x : y)
#endif

/*=========================================================================*\
* Test support functions
\*=========================================================================*/
#ifdef _DEBUG
/*-------------------------------------------------------------------------*\
* Returns the time the system has been up, in secconds.
\*-------------------------------------------------------------------------*/
static void net_time(lua_State *L);
static void net_time(lua_State *L)
{
	lua_pushnumber(L, get_time()/1000.0);
}

/*-------------------------------------------------------------------------*\
* Causes a Lua script to sleep for the specified number of secconds
\*-------------------------------------------------------------------------*/
static void net_sleep(lua_State *L);
static void net_sleep(lua_State *L)
{
    int sec = (int) luaL_check_number(L, 1);
#ifdef WIN32
    Sleep(1000*sec);
#else
    sleep(sec);
#endif
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
* Input
*   host: host name or ip address to connect to 
*   port: port number on host
* Returns
*   On success: client socket
*   On error: nil, followed by an error message
\*-------------------------------------------------------------------------*/
static void net_connect(lua_State *L)
{
	const char *hostname = luaL_check_string(L, FIRST_PAR);
	unsigned short port = (unsigned short) luaL_check_number(L, FIRST_PAR+1);
	struct sockaddr_in server;
	p_sock sock = create_tcpsock();
	if (!sock) {
		lua_pushnil(L);
		lua_pushstring(L, sock_strerror());
	}
	/* fills the sockaddr structure with the information needed to
	** connect our socket with the remote host */
	if (!fill_sockaddr(&server, hostname, port)) {
		free(sock);
		lua_pushnil(L);
		lua_pushstring(L, host_strerror());
		return;
	}
	if (connect(sock->sock,(struct sockaddr *)&server,sizeof(server)) < 0) {
		/* no connection? we close the socket to free the descriptor */
		closesocket(sock->sock);
		lua_pushnil(L);
		lua_pushstring(L, connect_strerror());
		return;
	}
	push_client(L, sock);
	/* no need to push second return value, since it would be nil anyways */
}

/*-------------------------------------------------------------------------*\
* Specifies the number of connections that can be queued on a server
* socket.
* Input
*   sock: server socket created by the bind function
* Returns
*   On success: nil
*   On error: an error message
\*-------------------------------------------------------------------------*/
static void net_listen(lua_State *L)
{
	p_sock sock = check_server(L, FIRST_PAR);
	unsigned int backlog = (unsigned int) luaL_check_number(L, FIRST_PAR+1);	

	if (listen(sock->sock, backlog) < 0) 
		lua_pushstring(L, "listen error");
	/* no need to push return value, since it would be nil anyways */
}

/*-------------------------------------------------------------------------*\
* Returns a client socket attempting to connect to a server socket.
* The function blocks until a client shows up.
* Input
*   sock: server socket created by the bind function
* Returns
*   On success: client socket attempting connection
*   On error: nil followed by an error message
\*-------------------------------------------------------------------------*/
static void net_accept(lua_State *L)
{
	struct sockaddr_in client_addr;
	p_sock server = check_server(L, FIRST_PAR);
	int client_sock = -1;
	unsigned int client_len = sizeof(client_addr);
	p_sock client;
	/* waits for a connection */
	client_sock = accept(server->sock, (struct sockaddr *) &client_addr,
		&client_len);
	/* we create and return a client socket object, passing the received 
	** socket to Lua, as a client socket */
	client = create_sock();
	if (!client) {
		lua_pushnil(L);
		lua_pushstring(L, "out of memory");
		return;
	}
	client->sock = client_sock;
	push_client(L, client);
}

/*-------------------------------------------------------------------------*\
* Associates an address to a server socket.
* Input
*   host: host name or ip address to bind to 
*   port: port to bind to
*   backlog: optional parameter specifying the number of connections
*     to keep waiting before refuse a connection. the default value is 1.
* Returns
*   On success: server socket bound to address
*   On error: nil, followed by an error message
\*-------------------------------------------------------------------------*/
static void net_bind(lua_State *L)
{
	const char *hostname = luaL_check_string(L, FIRST_PAR);
	unsigned short port = (unsigned short) luaL_check_number(L, FIRST_PAR+1);
	unsigned int backlog = (unsigned int) luaL_opt_number(L, FIRST_PAR+2, 1.0);	
	struct sockaddr_in server;
	p_sock sock = create_tcpsock();
	if (!sock) {
		lua_pushnil(L);
		lua_pushstring(L, sock_strerror());
	}
	/* fills the sockaddr structure with the information needed to
	** connect our socket with local address */
	if (!fill_sockaddr(&server, hostname, port)) {
		free(sock);
		lua_pushnil(L);
		lua_pushstring(L, host_strerror());
		return;
	}
	if (bind(sock->sock,(struct sockaddr *)&server,sizeof(server)) < 0) {
		lua_pushnil(L);
		lua_pushstring(L, bind_strerror());
		return;
	}
	/* define the connection waiting queue length */
	if (listen(sock->sock, backlog) < 0) {
		lua_pushnil(L);
		lua_pushstring(L, "listen error");
		return;
	}
	/* pass the created socket to Lua, as a server socket */
	push_server(L, sock);
	/* no need to push return value, since it would be nil anyways */
}

/*-------------------------------------------------------------------------*\
* Sets timeout values for IO operations on a client socket
* Input
*   sock: client socket created by the connect function
*   time: time out value in seconds
*   mode: optional timeout mode. "block" specifies the upper bound on
*     the time any IO operation on sock can cause the program to block.
*     "return" specifies the upper bound on the time elapsed before the
*     function returns control to the script. "block" is the default.
* Returns
*   no return value
\*-------------------------------------------------------------------------*/
static void net_timeout(lua_State *L)
{
	p_sock sock = check_client(L, FIRST_PAR);
	int ms = (int) (luaL_check_number(L, FIRST_PAR+1)*1000.0);
	const char *mode = luaL_opt_string(L, FIRST_PAR+2, "b");
	switch (*mode) {
		case 'b':
			sock->b = ms;
			break;
		case 'r':
			sock->r = ms;
			break;
		default:
			luaL_arg_check(L, 0, FIRST_PAR+2, "invalid timeout mode");
			break;
	}
}

/*-------------------------------------------------------------------------*\
* Send data through a socket
* Input: sock, a_1 [, a_2, a_3 ... a_n]
*   sock: client socket created by the connect function
*   a_i: strings to be sent. The strings will be sent on the order they
*     appear as parameters
* Returns
*   On success: nil, followed by the total number of bytes sent
*   On error: NET_TIMEOUT if the connection timedout, or NET_CLOSED if
*     the connection has been closed
\*-------------------------------------------------------------------------*/
static void net_send(lua_State *L)
{
	p_sock sock = check_client(L, FIRST_PAR);
	const char *data;
	long size;
	int start = get_time();
	long total = 0;
	int arg = FIRST_PAR+1;
	int err = NET_DONE;
	int end;
#ifdef _DEBUG_BLOCK
printf("luasock: send start\n");
#endif
	while ((data = luaL_opt_lstr(L, arg++, NULL, &size)) && err == NET_DONE)
		total += send_raw(sock, data, size, start, &err, &end);
	push_error(L, err);
	lua_pushnumber(L, (double) total);
#ifdef _DEBUG_BLOCK
printf("luasock: send end\n");
#endif
#ifdef _DEBUG
/* pass the time elapsed during function execution to Lua, so that
** the test script can make sure we respected the timeouts */
lua_pushnumber(L, (end-start)/1000.0);
#endif
}

/*-------------------------------------------------------------------------*\
* Receive data from a socket
* Input: sock [pat_1, pat_2 ... pat_n]
*   sock: client socket created by the connect function
*   pat_i: may be one of the following 
*     "*l": reads a text line, defined as a string of caracters terminates
*       by a LF character, preceded or not by a CR character. This is
*       the default pattern
*     "*lu": reads a text line, terminanted by a CR character only. (Unix mode)
*     number: reads 'number' characters from the socket
* Returns
*   On success: one string for each pattern
*   On error: all strings for which there was no error, followed by on
*     nil value for each failed string, followed by an error code
\*-------------------------------------------------------------------------*/
static void net_receive(lua_State *L)
{
	static const char *const modenames[] = {"*l", "*lu", NULL};
	p_sock sock = check_client(L, FIRST_PAR);
	int err = NET_DONE, arg = FIRST_PAR+1, got = 0;
	char *data = NULL;
	int start = get_time();
	const char *mode = luaL_opt_string(L, arg++, "*l");
	int end;
#ifdef _DEBUG_BLOCK
printf("luasock: receive start\n");
#endif
	do {
		/* if one pattern failed, we just skip all other patterns */
		if (err != NET_DONE) {
			lua_pushnil(L);
			continue;
		}
		/* get next pattern */
		switch (luaL_findstring(mode, modenames)) {
			/* DOS line mode */
			case 0:
				got = receive_dosline(L, sock, &data, start, &err, &end);
				break;
			/* Unix line mode */
			case 2:
				got = receive_unixline(L, sock, &data, start, &err, &end);
				break;
			/* else it must be a number, raw mode */
			default: {
				long size = (long) luaL_check_number(L, arg-1);
				got = receive_raw(L, sock, size, &data, start, &err, &end);
				break;
			}
		}
		/* pass result */
		lua_pushlstring(L, data, got);
	} while ((mode = luaL_opt_string(L, arg++, NULL)));
	/* last return is an error code */
	push_error(L, err);
#ifdef _DEBUG_BLOCK
printf("luasock: receive end\n");
#endif
#ifdef _DEBUG
/* pass the time elapsed during function execution to Lua, so that
** the test script can make sure we respected the timeouts */
lua_pushnumber(L, (end-start)/1000.0);
#endif
}

/*-------------------------------------------------------------------------*\
* Closes a socket.
* Input 
*   sock: socket to be closed
\*-------------------------------------------------------------------------*/
static void net_close(lua_State *L)
{
	p_sock sock = check_sock(L, FIRST_PAR);
	closesocket(sock->sock);
	/* set value to -1 so that we can later detect the use of a 
	** closed socket */
	sock->sock = -1;
}

/*-------------------------------------------------------------------------*\
* Gettable fallback for the client socket. This function provides the 
* alternative interface client:receive, client:send etc for the client 
* socket methods.
\*-------------------------------------------------------------------------*/
static void client_gettable(lua_State *L)
{
	static const char *const net_api[] = {"receive","send","timeout","close",
		"connect", NULL};
    const char *idx = luaL_check_string(L, FIRST_PAR+1);
	switch (luaL_findstring(idx, net_api)) {
		case 0: 
			lua_pushnumber(L, get_tag(L, CLIENT_TAG));
			lua_pushnumber(L, get_tag(L, SERVER_TAG));
			lua_pushcclosure(L, net_receive, 2); 
			break;
		case 1: 
			lua_pushnumber(L, get_tag(L, CLIENT_TAG));
			lua_pushnumber(L, get_tag(L, SERVER_TAG));
			lua_pushcclosure(L, net_send, 2); 
			break;
		case 2: 
			lua_pushnumber(L, get_tag(L, CLIENT_TAG));
			lua_pushnumber(L, get_tag(L, SERVER_TAG));
			lua_pushcclosure(L, net_timeout, 2); 
			break;
		case 3: 
			lua_pushnumber(L, get_tag(L, CLIENT_TAG));
			lua_pushnumber(L, get_tag(L, SERVER_TAG));
			lua_pushcclosure(L, net_close, 2); 
			break;
		default: 
			lua_pushnil(L); 
			break;
	}
}

/*-------------------------------------------------------------------------*\
* Gettable fallback for the server socket. This function provides the 
* alternative interface server:listen, server:accept etc for the server 
* socket methods.
\*-------------------------------------------------------------------------*/
static void server_gettable(lua_State *L)
{
	static const char *const net_api[] = {"listen","accept","close", NULL};
    const char *idx = luaL_check_string(L, FIRST_PAR+1);
	switch (luaL_findstring(idx, net_api)) {
		case 0: 
			lua_pushnumber(L, get_tag(L, CLIENT_TAG));
			lua_pushnumber(L, get_tag(L, SERVER_TAG));
			lua_pushcclosure(L, net_listen, 2); 
			break;
		case 1: 
			lua_pushnumber(L, get_tag(L, CLIENT_TAG));
			lua_pushnumber(L, get_tag(L, SERVER_TAG));
			lua_pushcclosure(L, net_accept, 2); 
			break;
		case 2: 
			lua_pushnumber(L, get_tag(L, CLIENT_TAG));
			lua_pushnumber(L, get_tag(L, SERVER_TAG));
			lua_pushcclosure(L, net_close, 2); 
			break;
		default: 
			lua_pushnil(L); 
			break;
	}
}

/*-------------------------------------------------------------------------*\
* Garbage collection fallback for the socket objects. This function 
* makes sure that all collected sockets are closed and that the memory
* used by the C structure t_sock is properly released. 
\*-------------------------------------------------------------------------*/
static void sock_gc(lua_State *L)
{
	p_sock sock = check_sock(L, FIRST_PAR);
	if (sock->sock >= 0) 
		closesocket(sock->sock);
	free(sock);
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
	struct sigaction old, new;
	bzero(&new, sizeof new);
	new.sa_handler = SIG_IGN;
	sigaction(SIGPIPE, &new, &old);
	/* test if the signal had been before, and restore it if so */
	if (old.sa_handler != SIG_DFL) {
#ifdef _DEBUG
/* this is a somewhat dangerous situation. we can only hope the
** installed signal handler understands that this signal can be
** raised by a socket operation */
printf("SIGPIPE ALREADY REDEFINED!!!\n");
#endif
		sigaction(SIGPIPE, &old, NULL);
	}
}
#endif

/*-------------------------------------------------------------------------*\
* Creates a t_sock structure with default values.
\*-------------------------------------------------------------------------*/
static p_sock create_sock(void)
{
	p_sock sock = (p_sock) malloc(sizeof(t_sock));
	if (!sock) 
		return NULL;
	sock->sock = -1;
	sock->r = -1;
	sock->b = -1;
	sock->blocking = 1;
	return sock;
}

/*-------------------------------------------------------------------------*\
* Creates a TCP/IP socket.
* Returns
*   A pointer to a t_sock structure or NULL in case of error
\*-------------------------------------------------------------------------*/
static p_sock create_tcpsock(void)
{
	p_sock sock = create_sock();
	if (!sock) 
		return NULL;
	sock->sock = socket(AF_INET, SOCK_STREAM, 0);
	if (sock->sock < 0) {
		free(sock);
		sock = NULL;
	}
#ifdef _DEBUG
/* this allow us to re-bind onto an address even if there is still
** a TIME_WAIT condition. debugging is much more confortable, because
** we don't get "address already in use" errors all the time we
** re-run the program before the OS is ready. in real life, though
** there could be data pending on the socket and this could lead to
** some weird errors. */
{
	int val = 1;
	setsockopt(sock->sock, SOL_SOCKET, SO_REUSEADDR, (char *) &val, 
		sizeof(val));
}
#endif
	return sock;
}

/*-------------------------------------------------------------------------*\
* Fills a sockaddr structure according to a given host name of ip
* address and a port number.
* Input
*   address: pointer to sockaddr structure to be filled
*   hostname: host name or ip address
*   port: port number
* Returns
*   1 in case of success, 0 otherwise
\*-------------------------------------------------------------------------*/
static int fill_sockaddr(struct sockaddr_in *address, const char *hostname, 
	unsigned short port)
{
	struct hostent *host = NULL;
	unsigned long addr = inet_addr(hostname);
	/* BSD says we could have used gethostbyname even if the hostname is
	** in ip address form, but WinSock2 says we can't. Therefore we
	** choose a method that works on both plataforms */
	if (addr == INADDR_NONE)
		host = gethostbyname(hostname);
	else
		host = gethostbyaddr((char * ) &addr, sizeof(unsigned long), AF_INET);
	if (!host) 
		return 0;
	memset(address, 0, sizeof(struct sockaddr_in));
	address->sin_family = AF_INET;
	address->sin_port = htons(port);
	memcpy(&(address->sin_addr), host->h_addr, (unsigned) host->h_length);
	return 1;
}

/*-------------------------------------------------------------------------*\
* Determine the time limit to be passed to the select function, given
* the time elapsed since the beginning of the operation.
* Input
*   sock: socket structure being used in operation
*   elapsed: time elapsed since operation started
* Returns
*   time limit before function return in ms or -1 in case there is no
*     time limit
\*-------------------------------------------------------------------------*/
static int get_timeout(p_sock sock, int elapsed) 
{
	/* no timeout */
	if (sock->b < 0 && sock->r < 0)
		return -1;
	/* there is no block timeout, we use the return timeout */
	if (sock->b < 0)
		return max(0, sock->r - elapsed);
	/* there is no return timeout, we use the block timeout */
	else if (sock->r < 0)
		return sock->b;
	/* both timeouts are specified */
	else 
		return min(sock->b, max(0, sock->r - elapsed));
}

/*-------------------------------------------------------------------------*\
* Determines if we have a timeout condition or if we can proceed with
* an IO read operation.
* Input
*   sock: socket structure being used in operation
*   elapsed: time elapsed since operation started
* Returns
*   1 if we can proceed, 0 if a timeou has occured
\*-------------------------------------------------------------------------*/
static int read_or_timeout(p_sock sock, int elapsed)
{
	fd_set set; 				/* file descriptor set */
	struct timeval to; 			/* timeout structure */
	int ms = get_timeout(sock, elapsed);
	int err;
	/* got timeout */
	if (ms == 0)
		return 0;
	FD_ZERO(&set);
	FD_SET(sock->sock, &set);
	/* we have a limit on the time we can wait */
	if (ms > 0) {
		to.tv_sec = ms / 1000;
		to.tv_usec = (ms % 1000) * 1000;
		err = select(sock->sock+1, &set, NULL, NULL, &to);
		set_nonblocking(sock);
	/* we can wait forever */
	} else {
		err = select(sock->sock+1, &set, NULL, NULL, NULL);
		set_blocking(sock);
	}
	return (err > 0);
}

/*-------------------------------------------------------------------------*\
* Determines if we have a timeout condition or if we can proceed with
* an IO write operation.
* Input
*   sock: socket structure being used in operation
*   elapsed: time elapsed since operation started
* Returns
*   1 if we can proceed, 0 if a timeou has occured
\*-------------------------------------------------------------------------*/
static int write_or_timeout(p_sock sock, int elapsed)
{
	fd_set set; 				/* file descriptor set */
	struct timeval to; 			/* timeout structure */
	int ms = get_timeout(sock, elapsed);
	int err;
	/* got timeout */
	if (ms == 0)
		return 0;
	FD_ZERO(&set);
	FD_SET(sock->sock, &set);
	/* we have a limit on the time we can wait */
	if (ms > 0) {
		to.tv_sec = ms / 1000;
		to.tv_usec = (ms % 1000) * 1000;
		err = select(sock->sock+1, NULL, &set, NULL, &to);
		set_nonblocking(sock);
	/* we can wait forever */
	} else {
		err = select(sock->sock+1, NULL, &set, NULL, NULL);
		set_blocking(sock);
	}
	return (err > 0);
}

/*-------------------------------------------------------------------------*\
* Sends a raw block of data through a socket. The operations are all
* non-blocking and the function respects the timeout values in sock.
* Input
*   sock: socket structure being used in operation
*   data: buffer to be sent
*   wanted: number of bytes in buffer
*   start: time the operation started, in ms
* Output
*   err: operation error code. NET_DONE, NET_TIMEOUT or NET_CLOSED
* Returns
*   Number of bytes written
\*-------------------------------------------------------------------------*/
static int send_raw(p_sock sock, const char *data, int wanted, 
	int start, int *err, int *end)
{
	int put = 0, total = 0;
	*end = start;
	while (wanted > 0) {
		if(!write_or_timeout(sock, time_since(start))) {
#ifdef _DEBUG
*end = get_time();
#endif
			*err = NET_TIMEOUT;
			return total;
		}
#ifdef _DEBUG
/* the lua_pushlstring function can take a long time to pass a large block 
** to Lua, therefore, we mark the time before passing the result.
** also, the call to write of read might take longer then the time we had 
** left, so that the end of the operation is marked before the last call 
** to the OS */
*end = get_time();
#endif
		put = send(sock->sock, data, wanted, 0);
		if (put <= 0) {
#ifdef WIN32
			/* on WinSock, a select over a socket on which there is a 
			** non-blocking operation pending returns immediately, even
			** if the call would block. therefore, we have to do a busy
			** wait here. */
			if (WSAGetLastError() == WSAEWOULDBLOCK)
				continue;
#endif
			*err = NET_CLOSED;
			return total;
		}
#ifdef _DEBUG_BLOCK
printf("luasock: sent %d bytes, %dms elapsed\n", put, time_since(start));
#endif
		wanted -= put;
		data += put;
		total += put;
	}
	*err = NET_DONE;
	return total;
}

/*-------------------------------------------------------------------------*\
* Reads a raw block of data from a socket. The operations are all
* non-blocking and the function respects the timeout values in sock.
* Input
*   sock: socket structure being used in operation
*   wanted: number of bytes to be read
*   start: time the operation started, in ms
* Output
*   data: pointer to an internal buffer containing the data read
*   err: operation error code. NET_DONE, NET_TIMEOUT or NET_CLOSED
* Returns
*   Number of bytes read
\*-------------------------------------------------------------------------*/
static int receive_raw(lua_State *L, p_sock sock, int wanted, char **data, 
	int start, int *err, int *end)
{
	int got = 0;
	char *buffer = NULL;
	*end = start;
	luaL_resetbuffer(L);
	while (wanted > 0) {
		buffer = luaL_openspace(L, wanted);
		if(!read_or_timeout(sock, time_since(start))) {
#ifdef _DEBUG
*end = get_time();
#endif
			*data = luaL_buffer(L);
			*err = NET_TIMEOUT;
			return luaL_getsize(L);
		}
#ifdef _DEBUG
*end = get_time();
#endif
		got = recv(sock->sock, buffer, wanted, 0);
#ifdef _DEBUG_BLOCK
printf("luasock: wanted %d, got %d, %dms elapsed\n", wanted, got, time_since(start));
#endif
		if (got <= 0) {
			*data = luaL_buffer(L);
			*err = NET_CLOSED;
			return luaL_getsize(L);
		}
		wanted -= got;
		luaL_addsize(L,got);
	}
	*data = luaL_buffer(L);
	*err = NET_DONE;
	return luaL_getsize(L);
}

/*-------------------------------------------------------------------------*\
* Reads a line terminated by a CR LF pair or just by a LF. The CR and LF 
* are not returned by the function. All operations are non-blocking and the
* function respects the timeout values in sock.
* Input
*   sock: socket structure being used in operation
*   wanted: number of bytes in buffer
*   start: time the operation started, in ms
* Output
*   data: pointer to an internal buffer containing the data read
*   err: operation error code. NET_DONE, NET_TIMEOUT or NET_CLOSED
* Returns
*   Number of bytes read
\*-------------------------------------------------------------------------*/
static long receive_dosline(lua_State *L, p_sock sock, char **data, 
	int start, int *err, int *end)
{
	char c = ' ';
	long got = 0;
  	*end = start;
	luaL_resetbuffer(L);
	while (c != '\n') {
		if (read_or_timeout(sock, time_since(start))) {
#ifdef _DEBUG
*end = get_time();
#endif
			got = recv(sock->sock, &c, 1, 0); 
			if (got <= 0) {
				*err = NET_CLOSED;
				*data = luaL_buffer(L);
				return luaL_getsize(L);
			}
			luaL_addchar(L, c);
		} else {
			*err = NET_TIMEOUT;
			*data = luaL_buffer(L);
			return luaL_getsize(L);
		}
	}
	*err = NET_DONE;
	*data = luaL_buffer(L);
	got = luaL_getsize(L);
	if ((*data)[got-2] == '\r') return got-2;
	else return got-1;
}

/*-------------------------------------------------------------------------*\
* Reads a line terminated by a LF character, which is not returned by
* the function. All operations are non-blocking and the function respects 
* the timeout values in sock.
* Input
*   sock: socket structure being used in operation
*   wanted: number of bytes in buffer
*   start: time the operation started, in ms
* Output
*   data: pointer to an internal buffer containing the data read
*   err: operation error code. NET_DONE, NET_TIMEOUT or NET_CLOSED
* Returns
*   Number of bytes read
\*-------------------------------------------------------------------------*/
static long receive_unixline(lua_State *L, p_sock sock, char **data, 
	int start, int *err, int *end)
{
	char c = ' ';
  	*end = start;
	luaL_resetbuffer(L);
	while (c != '\n') {
		if (read_or_timeout(sock, time_since(start))) {
#ifdef _DEBUG
*end = get_time();
#endif
			if (recv(sock->sock, &c, 1, 0) <= 0) {
				*err = NET_CLOSED;
				*data = luaL_buffer(L);
				return luaL_getsize(L);
			}
			luaL_addchar(L, c);
		} else {
			*err = NET_TIMEOUT;
			*data = luaL_buffer(L);
			return luaL_getsize(L);
		}
	}
	*err = NET_DONE;
	*data = luaL_buffer(L);
	return luaL_getsize(L) - 1;
}

/*-------------------------------------------------------------------------*\
* Gets a tag from a closure parameter
* Input
*	L: lua environment
*   par: parameter number
\*-------------------------------------------------------------------------*/
static int get_tag(lua_State *L, int par)
{
	return (int) lua_getnumber(L, lua_getparam(L, par));
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
	}
}

/*-------------------------------------------------------------------------*\
* Passes a client socket to Lua. 
* Must be called from a closure receiving the socket tags as its
* parameters.
* Input
*	L: lua environment
*   sock: pointer to socket structure to be used
\*-------------------------------------------------------------------------*/
static void push_client(lua_State *L, p_sock sock)
{
	lua_pushusertag(L, (void *) sock, get_tag(L, CLIENT_TAG));
}

/*-------------------------------------------------------------------------*\
* Passes a server socket to Lua. 
* Must be called from a closure receiving the socket tags as its
* parameters.
* Input
*	L: lua environment
*   sock: pointer to socket structure to be used
\*-------------------------------------------------------------------------*/
static void push_server(lua_State *L, p_sock sock)
{
	lua_pushusertag(L, (void *) sock, get_tag(L, SERVER_TAG));
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
static int wsock_open(void)
{
	WORD wVersionRequested;WSADATA wsaData;int err; 
	wVersionRequested = MAKEWORD( 2, 0 ); 
	err	= WSAStartup( wVersionRequested, &wsaData );
	if ( err != 0 ) {
		return 0;
	} 
	if ( LOBYTE( wsaData.wVersion ) != 2 ||
		HIBYTE( wsaData.wVersion ) != 0 ) {
		WSACleanup( );
		return 0; 
	}
	return 1;
}
	
/*-------------------------------------------------------------------------*\
* Gets time in ms, relative to system startup.
* Returns
*   time in ms.
\*-------------------------------------------------------------------------*/
static int get_time(void) 
{
	return GetTickCount();
}

/*-------------------------------------------------------------------------*\
* Put socket into blocking mode.
\*-------------------------------------------------------------------------*/
static void set_blocking(p_sock sock)
{
	u_long argp = 0;
	if (!sock->blocking) {
		ioctlsocket(sock->sock, FIONBIO, &argp);
		sock->blocking = 1;
	}
}

/*-------------------------------------------------------------------------*\
* Put socket into non-blocking mode.
\*-------------------------------------------------------------------------*/
static void set_nonblocking(p_sock sock)
{
	u_long argp = 1;
	if (sock->blocking) {
		ioctlsocket(sock->sock, FIONBIO, &argp);
		sock->blocking = 0;
	}
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
static char *sock_strerror(void)
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
* Gets time in ms, relative to system startup.
* Returns
*   time in ms.
\*-------------------------------------------------------------------------*/
static int get_time(void)
{
	struct tms t;
	return (times(&t)*1000)/CLK_TCK;
}

/*-------------------------------------------------------------------------*\
* Put socket into blocking mode.
\*-------------------------------------------------------------------------*/
static void set_blocking(p_sock sock)
{
	if (!sock->blocking) {
		int flags = fcntl(sock->sock, F_GETFL, 0);
		flags &= (~(O_NONBLOCK));
		fcntl(sock->sock, F_SETFL, flags);
		sock->blocking = 1;
	}
}

/*-------------------------------------------------------------------------*\
* Put socket into non-blocking mode.
\*-------------------------------------------------------------------------*/
static void set_nonblocking(p_sock sock)
{
	if (sock->blocking) {
		int flags = fcntl(sock->sock, F_GETFL, 0);
		flags |= O_NONBLOCK;
		fcntl(sock->sock, F_SETFL, flags);
		sock->blocking = 0;
	}
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
static char *sock_strerror(void)
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

/*=========================================================================*\
* Module exported functions
\*=========================================================================*/
/*-------------------------------------------------------------------------*\
* Initializes the library interface with Lua and the socket library.
* Defines the symbols exported to Lua.
\*-------------------------------------------------------------------------*/
void lua_socklibopen(lua_State *L)
{
	int client_tag, server_tag;
	static struct luaL_reg funcs[] = {
		{"connect", net_connect},
		{"bind", net_bind},
		{"listen", net_listen},
		{"accept", net_accept},
		{"close", net_close},
		{"send", net_send},
		{"receive", net_receive},
		{"timeout", net_timeout}
	};
	int i;

#ifdef WIN32
	wsock_open();
#endif
	/* declare new Lua tags for used userdata values */
	client_tag = lua_newtag(L);
	server_tag = lua_newtag(L);
	/* Lua exported functions */
	for (i = 0; i < sizeof(funcs)/sizeof(funcs[0]); i++) {
		lua_pushnumber(L, client_tag);
		lua_pushnumber(L, server_tag);
		lua_pushcclosure(L, funcs[i].func, 2 );
		lua_setglobal(L, funcs[i].name );
	}
	/* fallbacks */
	lua_pushnumber(L, client_tag);
	lua_pushnumber(L, server_tag);
	lua_pushcclosure(L, client_gettable, 2);
	lua_settagmethod(L, client_tag, "gettable");

	lua_pushnumber(L, client_tag);
	lua_pushnumber(L, server_tag);
	lua_pushcclosure(L, server_gettable, 2);
	lua_settagmethod(L, server_tag, "gettable");

	lua_pushnumber(L, client_tag);
	lua_pushnumber(L, server_tag);
	lua_pushcclosure(L, sock_gc, 2);
	lua_settagmethod(L, client_tag, "gc");

	lua_pushnumber(L, client_tag);
	lua_pushnumber(L, server_tag);
	lua_pushcclosure(L, sock_gc, 2);
	lua_settagmethod(L, server_tag, "gc");

	/* avoid stupid compiler warnings */
	(void) set_blocking;

#ifndef WIN32
	/* avoid getting killed by a SIGPIPE signal */
	handle_sigpipe();
#endif

#ifdef _DEBUG
/* test support functions */
lua_pushcfunction(L, net_sleep); lua_setglobal(L, "sleep");
lua_pushcfunction(L, net_time); lua_setglobal(L, "time");
#endif
}

/*=========================================================================*\
* Lua2c and c2lua stack auxiliary functions 
\*=========================================================================*/
/*-------------------------------------------------------------------------*\
* Checks if argument is a client socket, printing an error message in
* case of error
* Input
*   numArg: argument position in lua2c stack
* Returns
*   pointer to client socket, or doesn't return in case of error
\*-------------------------------------------------------------------------*/
static p_sock check_client(lua_State *L, int numArg)
{
	p_sock sock;
	lua_Object o = lua_getparam(L, numArg);
	luaL_arg_check(L, lua_tag(L, o) == get_tag(L, CLIENT_TAG), 
		numArg, "client socket expected");
	sock = (p_sock) lua_getuserdata(L, o);
	if (sock->sock < 0)
		lua_error(L, "operation on closed socket");
	return sock;
}

/*-------------------------------------------------------------------------*\
* Checks if argument is a server socket, printing an error message in
* case of error
* Input
*   numArg: argument position in lua2c stack
* Returns
*   pointer to server socket, or doesn't return in case of error
\*-------------------------------------------------------------------------*/
static p_sock check_server(lua_State *L, int numArg)
{
	p_sock sock;
	lua_Object o = lua_getparam(L, numArg);
	luaL_arg_check(L, lua_tag(L, o) == get_tag(L, SERVER_TAG), 
		numArg, "server socket expected");
	sock = (p_sock) lua_getuserdata(L, o);
	if (sock->sock < 0)
		lua_error(L, "operation on closed socket");
	return sock;
}

/*-------------------------------------------------------------------------*\
* Checks if argument is a socket, printing an error message in
* case of error
* Input
*   numArg: argument position in lua2c stack
* Returns
*   pointer to socket, or doesn't return in case of error
\*-------------------------------------------------------------------------*/
static p_sock check_sock(lua_State *L, int numArg)
{
	lua_Object o = lua_getparam(L, numArg);
	luaL_arg_check(L, (lua_tag(L, o) == get_tag(L, CLIENT_TAG)) || 
		(lua_tag(L, o) == get_tag(L, SERVER_TAG)), numArg, "socket expected");
	return lua_getuserdata(L, o);
}
