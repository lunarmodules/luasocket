#ifndef BUF_H
#define BUF_H 
/*=========================================================================*\
* Input/Output interface for Lua programs
* LuaSocket toolkit
*
* Line patterns require buffering. Reading one character at a time involves
* too many system calls and is very slow. This module implements the
* LuaSocket interface for input/output on connected objects, as seen by 
* Lua programs. 
*
* Input is buffered. Output is *not* buffered because there was no simple
* way of making sure the buffered output data would ever be sent.
*
* The module is built on top of the I/O abstraction defined in io.h and the
* timeout management is done with the timeout.h interface.
*
* RCS ID: $Id$
\*=========================================================================*/
#include <lua.h>

#include "io.h"
#include "timeout.h"

/* buffer size in bytes */
#define BUF_SIZE 8192

/* buffer control structure */
typedef struct t_buf_ {
    double birthday;        /* throttle support info: creation time, */
    size_t sent, received;  /* bytes sent, and bytes received */
    p_io io;                /* IO driver used for this buffer */
    p_tm tm;                /* timeout management for this buffer */
	size_t first, last;     /* index of first and last bytes of stored data */
	char data[BUF_SIZE];    /* storage space for buffer data */
} t_buf;
typedef t_buf *p_buf;

int buf_open(lua_State *L);
void buf_init(p_buf buf, p_io io, p_tm tm);
int buf_meth_send(lua_State *L, p_buf buf);
int buf_meth_receive(lua_State *L, p_buf buf);
int buf_meth_getstats(lua_State *L, p_buf buf);
int buf_isempty(p_buf buf);

#endif /* BUF_H */
