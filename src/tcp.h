#ifndef TCP_H
#define TCP_H

#include <lua.h>

#include "buffer.h"
#include "timeout.h"
#include "socket.h"

typedef struct t_tcp_ {
    t_sock sock;
    t_io io;
    t_buf buf;
    t_tm tm;
} t_tcp;
typedef t_tcp *p_tcp;

void tcp_open(lua_State *L);

#endif
