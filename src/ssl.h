#ifndef SSL_H
#define SSL_H
/*=========================================================================*\
* Simple client SSL support
* LuaSocket toolkit
*
* This is just a simple example to show how to extend LuaSocket
*
* RCS ID: $Id$
\*=========================================================================*/
#include <lua.h>
#include <openssl/ssl.h>

#include "buffer.h"
#include "timeout.h"
#include "socket.h"
#include "tcp.h"

typedef struct t_wrap_ {
    p_tcp tcp;
    SSL* ssl;
    int ref;
} t_wrap;

typedef t_wrap *p_wrap;

int ssl_open(lua_State *L);

#endif /* SSL_H */
