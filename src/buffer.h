/*=========================================================================*\
* Buffered input/output routines
* RCS ID: $Id$
\*=========================================================================*/
#ifndef BUF_H_
#define BUF_H_ 

#include <lua.h>
#include "lsbase.h"

/* buffer size in bytes */
#define BUF_SIZE 8192

/*-------------------------------------------------------------------------*\
* Buffer control structure
\*-------------------------------------------------------------------------*/
typedef struct t_buf_tag {
	size_t buf_first, buf_last;
	uchar buf_data[BUF_SIZE];
    p_base buf_base;
} t_buf;
typedef t_buf *p_buf;

/*-------------------------------------------------------------------------*\
* Exported functions
\*-------------------------------------------------------------------------*/
void buf_open(lua_State *L);
void buf_init(lua_State *L, p_buf buf, p_base base);
int buf_send(lua_State *L, p_buf buf);
int buf_receive(lua_State *L, p_buf buf);
int buf_isempty(lua_State *L, p_buf buf);

#endif /* BUF_H_ */
