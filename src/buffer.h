/*=========================================================================*\
* Buffered input/output routines
*
* RCS ID: $Id$
\*=========================================================================*/
#ifndef BUF_H
#define BUF_H 

#include <lua.h>
#include "io.h"
#include "tm.h"

/* buffer size in bytes */
#define BUF_SIZE 8192

/*-------------------------------------------------------------------------*\
* Buffer control structure
\*-------------------------------------------------------------------------*/
typedef struct t_buf_ {
    p_io io;                /* IO driver used for this buffer */
    p_tm tm;                /* timeout management for this buffer */
	size_t first, last;     /* index of first and last bytes of stored data */
	char data[BUF_SIZE];    /* storage space for buffer data */
} t_buf;
typedef t_buf *p_buf;

/*-------------------------------------------------------------------------*\
* Exported functions
\*-------------------------------------------------------------------------*/
void buf_open(lua_State *L);
void buf_init(p_buf buf, p_io io, p_tm tm);
int buf_meth_send(lua_State *L, p_buf buf);
int buf_meth_receive(lua_State *L, p_buf buf);
int buf_isempty(p_buf buf);

#endif /* BUF_H */
