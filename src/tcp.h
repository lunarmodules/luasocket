#ifndef TCP_H
#define TCP_H

#include <lua.h>

#include "buf.h"
#include "tm.h"
#include "sock.h"

typedef struct t_tcp_ {
    t_sock sock;
    t_io io;
    t_buf buf;
    t_tm tm;
} t_tcp;
typedef t_tcp *p_tcp;

void tcp_open(lua_State *L);

#endif
