/*=========================================================================*\
* TCP/IP bind for the Lua language
* Diego Nehab
* 26/11/1999
*
* Module: LUASOCKET.C
*
* This module is part of an effort to make the most important features
* of the TCP/IP protocol available to Lua scripts.
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
#include <assert.h>
#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <lauxlib.h>
#include <lua.h>
#include <lualib.h>

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
* The timeout and buffer parameters are not used by server sockets.
\*-------------------------------------------------------------------------*/
typedef struct t_sock {
	/* operating system socket object */
	SOCKET sock;
	/* start time of the current operation */	
	int tm_start;
	/* return and blocking timeout values (-1 if no limit) */
	int tm_return, tm_block;
	/* buffered I/O storage */
	unsigned char bf_buffer[LUASOCKET_BUFFERSIZE];
	/* first and last red bytes not yet passed to application */
	int bf_first, bf_last;
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
	int client, server, table;
} t_tags;
typedef t_tags *p_tags;

/*-------------------------------------------------------------------------*\
* Macros and internal declarations
\*-------------------------------------------------------------------------*/
/* min and max macros */
#ifndef min
#define min(x, y) ((x) < (y) ? x : y)
#endif
#ifndef max
#define max(x, y) ((x) > (y) ? x : y)
#endif

/*=========================================================================*\
* Internal function prototypes
\*=========================================================================*/
/* luasocket API functions */
static int global_connect(lua_State *L);
static int global_bind(lua_State *L);
static int table_listen(lua_State *L);
static int table_accept(lua_State *L);
static int table_send(lua_State *L);
static int table_receive(lua_State *L);
static int table_timeout(lua_State *L);
static int table_close(lua_State *L);
#ifndef LUASOCKET_NOGLOBALS
static int global_listen(lua_State *L);
static int global_accept(lua_State *L);
static int global_send(lua_State *L);
static int global_receive(lua_State *L);
static int global_timeout(lua_State *L);
static int global_close(lua_State *L);
static p_sock get_selfclientsock(lua_State *L, p_tags tags);
static p_sock get_selfserversock(lua_State *L, p_tags tags);
#endif

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
static int receive_dosline(lua_State *L, p_sock sock);
static int receive_unixline(lua_State *L, p_sock sock);
static int receive_all(lua_State *L, p_sock sock);

/* parameter manipulation functions */
static p_tags pop_tags(lua_State *L);
static p_sock pop_sock(lua_State *L);
static p_sock get_selfsock(lua_State *L, p_tags tags);
static int gc_sock(lua_State *L);
static p_sock push_servertable(lua_State *L, p_tags tags);
static p_sock push_clienttable(lua_State *L, p_tags tags);
static void push_error(lua_State *L, int err);

/* error code translations functions */
static char *host_strerror(void);
static char *bind_strerror(void);
static char *sock_strerror(void);
static char *connect_strerror(void);

/* auxiliary functions */
static void set_blocking(p_sock sock);
static void set_nonblocking(p_sock sock);
static int create_tcpsocket(p_sock sock);
static int fill_sockaddr(struct sockaddr_in *server, const char *hostname,
    unsigned short port);

#ifdef WIN32
static int winsock_open(void);
#endif

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
* Lua Input
*   host: host name or ip address to connect to 
*   port: port number on host
* Lua Returns
*   On success: client socket
*   On error: nil, followed by an error message
\*-------------------------------------------------------------------------*/
static int global_connect(lua_State *L)
{
	p_tags tags = pop_tags(L);
	const char *hostname = luaL_check_string(L, 1);
	unsigned short port = (unsigned short) luaL_check_number(L, 2);
	struct sockaddr_in server;
	p_sock sock = push_clienttable(L, tags);
	if (!sock) {
		lua_pushnil(L);
		lua_pushstring(L, "out of memory");
		return 2;
	}
	if (!create_tcpsocket(sock)) {
		lua_pushnil(L);
		lua_pushstring(L, sock_strerror());
		return 2;
	}
	/* fills the sockaddr structure with the information needed to
	** connect our socket with the remote host */
	if (!fill_sockaddr(&server, hostname, port)) {
		lua_pushnil(L);
		lua_pushstring(L, host_strerror());
		return 2;
	}
	if (connect(sock->sock, (struct sockaddr *)&server, sizeof(server)) < 0) {
		/* no connection? we close the socket to free the descriptor */
		closesocket(sock->sock);
		lua_pushnil(L);
		lua_pushstring(L, connect_strerror());
		return 2;
	}
	/* all operations on client sockets are non-blocking */
	set_nonblocking(sock);
	lua_pushnil(L);
	return 2;
}

/*-------------------------------------------------------------------------*\
* Converts from ip number to host name
* Lua Input
*   ip: ip number
* Lua Returns
*   On success: domain name
*   On error: nil, followed by an error message
\*-------------------------------------------------------------------------*/
static int global_toip(lua_State *L)
{
	struct hostent *host;
	struct in_addr addr;
	pop_tags(L);
   	host = gethostbyname(luaL_check_string(L, 1));
	if (!host) {
		lua_pushnil(L);
		lua_pushstring(L, host_strerror());
		return 2;
	}
	memcpy(&addr, host->h_addr, (unsigned) host->h_length);
	lua_pushstring(L, inet_ntoa(addr));
	return 1;
}

/*-------------------------------------------------------------------------*\
* Specifies the number of connections that can be queued on a server
* socket.
* Lua Input
*   sock: server socket created by the bind function
* Lua Returns
*   On success: nil
*   On error: an error message
\*-------------------------------------------------------------------------*/
static int table_listen(lua_State *L)
{
	p_sock sock = pop_sock(L);
	unsigned int backlog = (unsigned int) luaL_check_number(L, 2);	
	if (listen(sock->sock, backlog) < 0) {
		lua_pushstring(L, "listen error");
		return 1;
	} else {
		lua_pushnil(L);
		return 1;
	}
}

/*-------------------------------------------------------------------------*\
* Returns a client socket attempting to connect to a server socket.
* The function blocks until a client shows up.
* Lua Input
*   sock: server socket created by the bind function
* Lua Returns
*   On success: client socket attempting connection
*   On error: nil followed by an error message
\*-------------------------------------------------------------------------*/
static int table_accept(lua_State *L)
{
	struct sockaddr_in client_addr;
	size_t client_len = sizeof(client_addr);
	p_sock server = pop_sock(L);
	p_tags tags = pop_tags(L);
	p_sock client = push_clienttable(L, tags);
	SOCKET accepted = accept(server->sock, (struct sockaddr *) &client_addr,
		&client_len);
	client->sock = accepted;
	set_nonblocking(client);
	lua_pushnil(L);
	return 2;
}

/*-------------------------------------------------------------------------*\
* Associates an address to a server socket.
* Input
*   host: host name or ip address to bind to 
*   port: port to bind to
*   backlog: optional parameter specifying the number of connections
*     to keep waiting before refuse a connection. the default value is 1.
* Returns
*   On success: server socket bound to address, the ip address and port bound
*   On error: nil, followed by an error message
\*-------------------------------------------------------------------------*/
static int global_bind(lua_State *L)
{
	p_tags tags = pop_tags(L);
	const char *hostname = luaL_check_string(L, 1);
	unsigned short port = (unsigned short) luaL_check_number(L, 2);
	unsigned int backlog = (unsigned int) luaL_opt_number(L, 3, 1.0);	
	struct sockaddr_in server;
	size_t server_size = sizeof(server);
	p_sock sock = push_servertable(L, tags);
	if (!sock) {
		lua_pushnil(L);
		lua_pushstring(L, sock_strerror());
		return 2;
	}
	/* fills the sockaddr structure with the information needed to
	** connect our socket with local address */
	else if (!fill_sockaddr(&server, hostname, port)) {
		free(sock);
		lua_pushnil(L);
		lua_pushstring(L, host_strerror());
		return 2;
	}
	else if (bind(sock->sock,(struct sockaddr *)&server, server_size) < 0) {
		lua_pushnil(L);
		lua_pushstring(L, bind_strerror());
		return 2;
	}
	/* define the connection waiting queue length */
	else if (listen(sock->sock, backlog) < 0) {
		lua_pushnil(L);
		lua_pushstring(L, "listen error");
		return 2;
	} 
	/* pass the created socket to Lua, as a server socket */
	else {
		/* get used address and port */
		getsockname(sock->sock, (struct sockaddr *)&server, &server_size);
		/* pass ip number */
		lua_pushstring(L, inet_ntoa(server.sin_addr));
		/* pass port number */
		lua_pushnumber(L, ntohs(server.sin_port));
		lua_pushnil(L);
		return 4;
	}
}

/*-------------------------------------------------------------------------*\
* Sets timeout values for IO operations on a client socket
* Lua Input
*   sock: client socket created by the connect function
*   time: time out value in seconds
*   mode: optional timeout mode. "block" specifies the upper bound on
*     the time any IO operation on sock can cause the program to block.
*     "return" specifies the upper bound on the time elapsed before the
*     function returns control to the script. "block" is the default.
\*-------------------------------------------------------------------------*/
static int table_timeout(lua_State *L)
{
	p_sock sock = pop_sock(L);
	int ms = (int) (luaL_check_number(L, 2)*1000.0);
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
* Send data through a socket
* Lua Input: sock, a_1 [, a_2, a_3 ... a_n]
*   sock: client socket created by the connect function
*   a_i: strings to be sent. The strings will be sent on the order they
*     appear as parameters
* Lua Returns
*   On success: nil, followed by the total number of bytes sent
*   On error: NET_TIMEOUT if the connection timedout, or NET_CLOSED if
*     the connection has been closed, followed by the total number of 
*     bytes sent
\*-------------------------------------------------------------------------*/
static int table_send(lua_State *L)
{
	int arg;
	p_sock sock = pop_sock(L);
	int top = lua_gettop(L);
	int total = 0;
	int err = NET_DONE;
	tm_markstart(sock);
	for (arg = 2; arg <= top; arg++) { /* skip self table */
		int sent, wanted;
	 	const char *data = luaL_opt_lstr(L, arg, NULL, &wanted);
	 	if (!data || err != NET_DONE) break;
		err = send_raw(sock, data, wanted, &sent);
		total += sent;
	}
	push_error(L, err);
	lua_pushnumber(L, (double) total);
#ifdef _DEBUG
	/* push time elapsed during operation as the last return value */
	lua_pushnumber(L, (sock->tm_end - sock->tm_start)/1000.0);
#endif
	return lua_gettop(L) - top;
}

/*-------------------------------------------------------------------------*\
* Receive data from a socket
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
static int table_receive(lua_State *L)
{
	static const char *const modenames[] = {"*l", "*lu", "*a", NULL};
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
	/* receive all patterns */
	for (arg = 2; arg <= top; arg++) {
		/* if one pattern failed, we just skip all other patterns */
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
				case 0:
					err = receive_dosline(L, sock);
					break;
				/* Unix line mode */
				case 1:
					err = receive_unixline(L, sock);
					break;
				/* until closed mode */
				case 2:
					err = receive_all(L, sock);
					break;
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
* Closes a socket.
* Lua Input 
*   sock: socket to be closed
\*-------------------------------------------------------------------------*/
static int table_close(lua_State *L)
{
	/* close socket and set value to -1 so that pop_socket can later 
	** detect the use of a closed socket */
	p_sock sock = pop_sock(L);
	closesocket(sock->sock);
	sock->sock = -1;
	return 0;
}

/*-------------------------------------------------------------------------*\
* Garbage collection fallback for the socket objects. This function 
* makes sure that all collected sockets are closed.
\*-------------------------------------------------------------------------*/
static int gc_sock(lua_State *L)
{
	p_tags tags = pop_tags(L);
	p_sock sock = get_selfsock(L, tags);
	/* sock might have been closed */
	if (sock->sock >= 0) closesocket(sock->sock);
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
* Creates a TCP/IP socket.
* Input
*   sock: structure to receive new socket
* Returns
*   1 if successfull, 0 in case or error
\*-------------------------------------------------------------------------*/
static int create_tcpsocket(p_sock sock)
{
	sock->sock = socket(AF_INET, SOCK_STREAM, 0);
	if (sock->sock < 0) return 0;
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
	return 1;
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
	memset(address, 0, sizeof(struct sockaddr_in));
	if (strcmp(hostname, "*")) {
		/* BSD says we could have used gethostbyname even if the hostname is
		** in ip address form, but WinSock2 says we can't. Therefore we
		** choose a method that works on both plataforms */
		if (addr == INADDR_NONE) host = gethostbyname(hostname);
		else host = gethostbyaddr((char * ) &addr, sizeof(unsigned long), 
				AF_INET);
		if (!host) 
			return 0;
		memcpy(&(address->sin_addr), host->h_addr, (unsigned) host->h_length);
	} else {
		address->sin_addr.s_addr = htonl(INADDR_ANY);
	}
	address->sin_family = AF_INET;
	address->sin_port = htons(port);
	return 1;
}

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
		{"send", table_send},
		{"receive", table_receive},
		{"close", table_close},
		{"timeout", table_timeout},
	};
	int i;
	p_sock sock;
	lua_newtable(L); lua_settag(L, tags->table);
	lua_pushstring(L, P_SOCK);
	sock = (p_sock) lua_newuserdata(L, sizeof(t_sock));
	if (!sock) lua_error(L, "out of memory");
	lua_settag(L, tags->client);
	lua_settable(L, -3);
	sock->sock = -1;
	sock->tm_block = -1;
	sock->tm_return = -1;
	sock->bf_first = sock->bf_last = 0;
	for (i = 0; i < sizeof(funcs)/sizeof(funcs[0]); i++) {
		lua_pushstring(L, funcs[i].name);
		lua_pushusertag(L, sock, tags->client);
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
		{"listen", table_listen},
		{"close", table_close},
	};
	int i;
	p_sock sock;
	lua_newtable(L); lua_settag(L, tags->table);
	lua_pushstring(L, P_SOCK);
	sock = (p_sock) lua_newuserdata(L, sizeof(t_sock));
	if (!sock) lua_error(L, "out of memory");
	lua_settag(L, tags->server);
	lua_settable(L, -3);
	if (!create_tcpsocket(sock)) return NULL;
	sock->tm_block = -1;
	sock->tm_return = -1;
	sock->bf_first = sock->bf_last = 0;
	for (i = 0; i < sizeof(funcs)/sizeof(funcs[0]); i++) {
		lua_pushstring(L, funcs[i].name);
		lua_pushusertag(L, sock, tags->client);
		lua_pushcclosure(L, funcs[i].func, 1);
		lua_settable(L, -3);
	}
	/* the accept method is different, it needs the tags closure too */
	lua_pushstring(L, "accept");
	lua_pushuserdata(L, tags);
	lua_pushusertag(L, sock, tags->client);
	lua_pushcclosure(L, table_accept, 2);
	lua_settable(L, -3);
	return sock;
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
		return max(sock->tm_return - tm_gettime() + sock->tm_start, 0);
	/* there is no return timeout, we use the block timeout */
	else if (sock->tm_return < 0)
		return sock->tm_block;
	/* both timeouts are specified */
	else return min(sock->tm_block, 
			max(sock->tm_return - tm_gettime() + sock->tm_start, 0));
}

/*-------------------------------------------------------------------------*\
* Determines if we have a timeout condition or if we can proceed with
* an IO write operation.
* Input
*   sock: socket structure being used in operation
*   mode: TM_RECEIVE or TM_SEND
* Returns
*   1 if we can proceed, 0 if a timeout has occured
\*-------------------------------------------------------------------------*/
static int tm_timedout(p_sock sock, int mode)
{
	fd_set fds;
	int ret, delta;
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
	if (ms > 0) ptm = &tm; /* ptm == NULL when we don't have timeout */
	if (mode == TM_RECEIVE) preadfds = &fds;
	else pwritefds = &fds;
	delta = tm_gettime();
	/* see if we can read or write or if we timedout */
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
#ifdef _WIN32
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
* if there is none.
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
		int got = recv(sock->sock, sock->bf_buffer, LUASOCKET_BUFFERSIZE, 0);
		sock->bf_first = 0;
		if (got >= 0) sock->bf_last = got;
		else sock->bf_last = 0;
	}
	*length = sock->bf_last - sock->bf_first;
	return sock->bf_buffer + sock->bf_first;
}

/*=========================================================================*\
* These are the function that are called for each I/O pattern
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
			** should have blocked us */
			if (WSAGetLastError() == WSAEWOULDBLOCK)
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
		got = min(got, wanted);
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
*   operation error code. NET_DONE, NET_TIMEOUT or NET_CLOSED
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
		if (got > 0) {
			int len = 0, end = 1;
			while (len < got) {
				if (buffer[len] == '\n') { /* found eol */
					if (len > 0 && buffer[len-1] == '\r') {
						end++; len--;
					}
					luaL_addlstring(&b, buffer, len);
					bf_skip(sock, len + end); /* skip '\r\n' in stream */
					luaL_pushresult(&b);
					return NET_DONE;
				}
				len++;
			}
			luaL_addlstring(&b, buffer, got);
			bf_skip(sock, got);
		} else {
			luaL_pushresult(&b);
			return NET_CLOSED;
		}
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
		if (got > 0) {
			int len = 0;
			while (len < got) {
				if (buffer[len] == '\n') { /* found eol */
					luaL_addlstring(&b, buffer, len);
					bf_skip(sock, len + 1); /* skip '\n' in stream */
					luaL_pushresult(&b);
					return NET_DONE;
				}
				len++;
			}
			luaL_addlstring(&b, buffer, got);
			bf_skip(sock, got);
		} else {
			luaL_pushresult(&b);
			return NET_CLOSED;
		}
	}
}

/*=========================================================================*\
* Module exported functions
\*=========================================================================*/
/*-------------------------------------------------------------------------*\
* Initializes the library interface with Lua and the socket library.
* Defines the symbols exported to Lua.
\*-------------------------------------------------------------------------*/
void lua_socketlibopen(lua_State *L)
{
	static struct luaL_reg funcs[] = {
		{"connect", global_connect},
		{"bind", global_bind},
		{"toip", global_toip},
	};
	int i;
	/* declare new Lua tags for used userdata values */
	p_tags tags = (p_tags) lua_newuserdata(L, sizeof(t_tags));
	if (!tags) lua_error(L, "out of memory");
	tags->client = lua_newtag(L);
	tags->server = lua_newtag(L);
	tags->table = lua_newtag(L);
	/* global functions exported */
	for (i = 0; i < sizeof(funcs)/sizeof(funcs[0]); i++) {
		lua_pushuserdata(L, tags);
		lua_pushcclosure(L, funcs[i].func, 1);
		lua_setglobal(L, funcs[i].name);
	}
	/* socket garbage collection */
	lua_pushuserdata(L, tags);
	lua_pushcclosure(L, gc_sock, 1);
	lua_settagmethod(L, tags->table, "gc");

#ifndef LUASOCKET_NOGLOBALS
	/* global version of socket table functions */
{ 	static struct luaL_reg opt_funcs[] = {
		{"send", global_send},
		{"receive", global_receive},
		{"accept", global_accept},
		{"close", global_close},
		{"timeout", global_timeout},
		{"listen", global_listen},
	};
	for (i = 0; i < sizeof(opt_funcs)/sizeof(opt_funcs[0]); i++) {
		lua_pushuserdata(L, tags);
		lua_pushcclosure(L, opt_funcs[i].func, 1);
		lua_setglobal(L, opt_funcs[i].name);
	}
}
#endif
#ifdef WIN32
	/* WinSock needs special initialization */
	winsock_open();
#else
	/* avoid getting killed by a SIGPIPE signal thrown by send */
	handle_sigpipe();
#endif
#ifdef _DEBUG
	/* test support functions */
	lua_pushcfunction(L, global_sleep); lua_setglobal(L, "sleep");
	lua_pushcfunction(L, global_time); lua_setglobal(L, "time");
#endif
	/* avoid stupid compiler warnings */
	(void) set_blocking;
}

/*=========================================================================*\
* Optional global version of socket table methods
\*=========================================================================*/
#ifndef LUASOCKET_NOGLOBALS
int global_accept(lua_State *L)
{
	p_tags tags = pop_tags(L);
	p_sock sock = get_selfserversock(L, tags);
	lua_pushuserdata(L, tags);
	lua_pushusertag(L, sock, tags->server);
	return table_accept(L);
}

int global_listen(lua_State *L)
{
	p_tags tags = pop_tags(L);
	p_sock sock = get_selfserversock(L, tags);
	lua_pushusertag(L, sock, tags->server);
	return table_listen(L);
}

int global_send(lua_State *L)
{
	p_tags tags = pop_tags(L);
	p_sock sock = get_selfclientsock(L, tags);
	lua_pushusertag(L, sock, tags->client);
	return table_send(L);
}

int global_receive(lua_State *L)
{
	p_tags tags = pop_tags(L);
	p_sock sock = get_selfclientsock(L, tags);
	lua_pushusertag(L, sock, tags->client);
	return table_receive(L);
}

int global_timeout(lua_State *L)
{
	p_tags tags = pop_tags(L);
	p_sock sock = get_selfclientsock(L, tags);
	lua_pushusertag(L, sock, tags->client);
	return table_timeout(L);
}

int global_close(lua_State *L)
{
	return gc_sock(L);
}
#endif

/*=========================================================================*\
* Parameter manipulation functions 
\*=========================================================================*/
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
	if (sock->sock < 0) lua_error(L, "operation on closed socket");
	lua_pop(L, 1);
	return sock;
}

static p_sock get_selfsock(lua_State *L, p_tags tags)
{
	p_sock sock;
	if (lua_tag(L, 1) != tags->table) lua_error(L, "invalid socket object");
	lua_pushstring(L, P_SOCK);
	lua_gettable(L, 1);
	sock = lua_touserdata(L, -1);
	if (!sock) lua_error(L, "invalid socket object");
	lua_pop(L, 1);
	return sock;
}

#ifndef LUASOCKET_NOGLOBALS
static p_sock get_selfclientsock(lua_State *L, p_tags tags)
{
	p_sock sock;
	if (lua_tag(L, 1) != tags->table) lua_error(L, "invalid socket object");
	lua_pushstring(L, P_SOCK);
	lua_gettable(L, 1);
	sock = lua_touserdata(L, -1);
	if (!sock || lua_tag(L, -1) != tags->client) 
		lua_error(L, "client socket expected");
	lua_pop(L, 1);
	return sock;
}

static p_sock get_selfserversock(lua_State *L, p_tags tags)
{
	p_sock sock;
	if (lua_tag(L, 1) != tags->table) lua_error(L, "invalid socket object");
	lua_pushstring(L, P_SOCK);
	lua_gettable(L, 1);
	sock = lua_touserdata(L, -1);
	if (!sock || lua_tag(L, -1) != tags->server) 
		lua_error(L, "server socket expected");
	lua_pop(L, 1);
	return sock;
}
#endif

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
