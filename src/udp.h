#ifndef UDP_H
#define UDP_H

#include <lua.h>

#include "timeout.h"
#include "socket.h"

#define UDP_DATAGRAMSIZE 576

typedef struct t_udp_ {
    t_sock sock;
    t_tm tm;
} t_udp;
typedef t_udp *p_udp;

void udp_open(lua_State *L);

#endif
