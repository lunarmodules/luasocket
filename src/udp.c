/*=========================================================================*\
* UDP socket object implementation (inherits from sock and inet)
\*=========================================================================*/
#include <string.h>

#include <lua.h>
#include <lauxlib.h>

#include "lsinet.h"
#include "lsudp.h"
#include "lscompat.h"
#include "lsselect.h"

/*=========================================================================*\
* Internal function prototypes.
\*=========================================================================*/
static int udp_lua_send(lua_State *L);
static int udp_lua_sendto(lua_State *L);
static int udp_lua_receive(lua_State *L);
static int udp_lua_receivefrom(lua_State *L);
static int udp_lua_setpeername(lua_State *L);
static int udp_lua_setsockname(lua_State *L);

static int udp_global_udpsocket(lua_State *L);

static struct luaL_reg funcs[] = {
    {"send", udp_lua_send},
    {"sendto", udp_lua_sendto},
    {"receive", udp_lua_receive},
    {"receivefrom", udp_lua_receivefrom},
    {"setpeername", udp_lua_setpeername},
    {"setsockname", udp_lua_setsockname},
};

/*=========================================================================*\
* Exported functions
\*=========================================================================*/
/*-------------------------------------------------------------------------*\
* Initializes module
\*-------------------------------------------------------------------------*/
void udp_open(lua_State *L)
{
    unsigned int i;
    priv_newclass(L, UDP_CLASS);
    udp_inherit(L, UDP_CLASS);
    /* declare global functions */
    lua_pushcfunction(L, udp_global_udpsocket);
    lua_setglobal(L, "udpsocket");
    for (i = 0; i < sizeof(funcs)/sizeof(funcs[0]); i++) 
        priv_newglobalmethod(L, funcs[i].name);
    /* make class selectable */
    select_addclass(L, UDP_CLASS);
}

/*-------------------------------------------------------------------------*\
* Hook object methods to methods table.
\*-------------------------------------------------------------------------*/
void udp_inherit(lua_State *L, cchar *lsclass)
{
    unsigned int i;
    inet_inherit(L, lsclass);
    for (i = 0; i < sizeof(funcs)/sizeof(funcs[0]); i++) {
        lua_pushcfunction(L, funcs[i].func);
        priv_setmethod(L, lsclass, funcs[i].name);
    }
}

/*-------------------------------------------------------------------------*\
* Initializes socket structure 
\*-------------------------------------------------------------------------*/
void udp_construct(lua_State *L, p_udp udp)
{
    inet_construct(L, (p_inet) udp);
    udp->udp_connected = 0;
}

/*-------------------------------------------------------------------------*\
* Creates a socket structure and initializes it. A socket object is
* left in the Lua stack.
* Returns
*   pointer to allocated structure
\*-------------------------------------------------------------------------*/
p_udp udp_push(lua_State *L)
{
    p_udp udp = (p_udp) lua_newuserdata(L, sizeof(t_udp));
    priv_setclass(L, UDP_CLASS);
    udp_construct(L, udp);
    return udp;
}

/*=========================================================================*\
* Socket table constructors
\*=========================================================================*/
/*-------------------------------------------------------------------------*\
* Creates a udp socket object and returns it to the Lua script. 
* Lua Input: [options]
*   options: socket options table
* Lua Returns
*   On success: udp socket
*   On error: nil, followed by an error message
\*-------------------------------------------------------------------------*/
static int udp_global_udpsocket(lua_State *L)
{
    int oldtop = lua_gettop(L);
    p_udp udp = udp_push(L);
    cchar *err = inet_trysocket((p_inet) udp, SOCK_DGRAM);
    if (err) {
        lua_pushnil(L);
        lua_pushstring(L, err);
        return 2;
    }
    if (oldtop < 1) return 1;
    err = compat_trysetoptions(L, udp->fd);
    if (err) {
        lua_pushnil(L);
        lua_pushstring(L, err);
        return 2;
    }
    return 1;
}

/*=========================================================================*\
* Socket table methods
\*=========================================================================*/
/*-------------------------------------------------------------------------*\
* Receives data from a UDP socket
* Lua Input: sock [, wanted]
*   sock: client socket created by the connect function
*   wanted: the number of bytes expected (default: LUASOCKET_UDPBUFFERSIZE)
* Lua Returns
*   On success: datagram received
*   On error: nil, followed by an error message
\*-------------------------------------------------------------------------*/
static int udp_lua_receive(lua_State *L)
{
    p_udp udp = (p_udp) lua_touserdata(L, 1);
    unsigned char buffer[UDP_DATAGRAMSIZE];
    size_t got, wanted = (size_t) luaL_opt_number(L, 2, sizeof(buffer));
    int err;
    p_tm tm = &udp->base_tm;
    wanted = MIN(wanted, sizeof(buffer));
    tm_markstart(tm);
    err = compat_recv(udp->fd, buffer, wanted, &got, tm_getremaining(tm));
    if (err == PRIV_CLOSED) err = PRIV_REFUSED;
    if (err != PRIV_DONE) lua_pushnil(L);
    else lua_pushlstring(L, buffer, got);
    priv_pusherror(L, err);
    return 2;
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
static int udp_lua_receivefrom(lua_State *L)
{
    p_udp udp = (p_udp) lua_touserdata(L, 1);
    p_tm tm = &udp->base_tm;
    struct sockaddr_in peer;
    size_t peer_len = sizeof(peer);
    unsigned char buffer[UDP_DATAGRAMSIZE];
    size_t wanted = (size_t) luaL_opt_number(L, 2, sizeof(buffer));
    size_t got;
    int err;
    if (udp->udp_connected) lua_error(L, "receivefrom on connected socket");
    tm_markstart(tm);
    wanted = MIN(wanted, sizeof(buffer));
    err = compat_recvfrom(udp->fd, buffer, wanted, &got, tm_getremaining(tm),
            (SA *) &peer, &peer_len);
    if (err == PRIV_CLOSED) err = PRIV_REFUSED;
    if (err == PRIV_DONE) {
        lua_pushlstring(L, buffer, got);
        lua_pushstring(L, inet_ntoa(peer.sin_addr));
        lua_pushnumber(L, ntohs(peer.sin_port));
        return 3;
    } else {
        lua_pushnil(L);
        priv_pusherror(L, err);
        return 2;
    }
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
static int udp_lua_send(lua_State *L)
{
    p_udp udp = (p_udp) lua_touserdata(L, 1);
    p_tm tm = &udp->base_tm;
    size_t wanted, sent = 0;
    int err;
    cchar *data = luaL_check_lstr(L, 2, &wanted);
    if (!udp->udp_connected) lua_error(L, "send on unconnected socket");
    tm_markstart(tm);
    err = compat_send(udp->fd, data, wanted, &sent, tm_getremaining(tm));
    priv_pusherror(L, err == PRIV_CLOSED ? PRIV_REFUSED : err);
    lua_pushnumber(L, sent);
    return 2;
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
static int udp_lua_sendto(lua_State *L)
{
    p_udp udp = (p_udp) lua_touserdata(L, 1);
    size_t wanted, sent = 0;
    cchar *data = luaL_check_lstr(L, 2, &wanted);
    cchar *ip = luaL_check_string(L, 3);
    ushort port = (ushort) luaL_check_number(L, 4);
    p_tm tm = &udp->base_tm;
    struct sockaddr_in peer;
    int err;
    if (udp->udp_connected) lua_error(L, "sendto on connected socket");
    memset(&peer, 0, sizeof(peer));
    if (!inet_aton(ip, &peer.sin_addr)) lua_error(L, "invalid ip address");
    peer.sin_family = AF_INET;
    peer.sin_port = htons(port);
    tm_markstart(tm);
    err = compat_sendto(udp->fd, data, wanted, &sent, tm_getremaining(tm),
            (SA *) &peer, sizeof(peer));
    priv_pusherror(L, err == PRIV_CLOSED ? PRIV_REFUSED : err);
    lua_pushnumber(L, sent);
    return 2;
}

/*-------------------------------------------------------------------------*\
* Associates a local address to an UDP socket
* Lua Input: address, port
*   address: host name or ip address to bind to 
*   port: port to bind to
* Lua Returns
*   On success: nil
*   On error: error message
\*-------------------------------------------------------------------------*/
static int udp_lua_setsockname(lua_State * L)
{
    p_udp udp = (p_udp) lua_touserdata(L, 1);
    cchar *address = luaL_check_string(L, 2);
    ushort port = (ushort) luaL_check_number(L, 3);
    cchar *err = inet_trybind((p_inet) udp, address, port);
    if (err) lua_pushstring(L, err);
    else lua_pushnil(L);
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
static int udp_lua_setpeername(lua_State *L)
{
    p_udp udp = (p_udp) lua_touserdata(L, 1);
    cchar *address = luaL_check_string(L, 2);
    ushort port = (ushort) luaL_check_number(L, 3);
    cchar *err = inet_tryconnect((p_inet) udp, address, port);
    if (!err) {
        udp->udp_connected = 1;
        lua_pushnil(L);
    } else lua_pushstring(L, err);
    return 1;
}

