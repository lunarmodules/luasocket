/*=========================================================================*\
* Input/Output abstraction
* LuaSocket toolkit
*
* RCS ID: $Id$
\*=========================================================================*/
#include "io.h"

/*=========================================================================*\
* Exported functions
\*=========================================================================*/
/*-------------------------------------------------------------------------*\
* Initializes C structure
\*-------------------------------------------------------------------------*/
void io_init(p_io io, p_send send, p_recv recv, p_geterr geterr, void *ctx) {
    io->send = send;
    io->recv = recv;
    io->geterr = geterr;
    io->ctx = ctx;
}

/*-------------------------------------------------------------------------*\
* Translate error codes to Lua
\*-------------------------------------------------------------------------*/
const char *io_strerror(int code) {
    switch (code) {
        case IO_DONE: return NULL;
        case IO_CLOSED: return "closed";
        case IO_TIMEOUT: return "timeout";
        case IO_CLIPPED: return "clipped";
        default: return "unknown error";
    }
}

/*-------------------------------------------------------------------------*\
* Push error message from code or from driver
\*-------------------------------------------------------------------------*/
void io_pusherror(lua_State *L, p_io io, int code)
{
    const char *err = NULL; 
    if (code < IO_USER) err = io_strerror(code);
    else err = io->geterr(io->ctx, code);
    if (err) lua_pushstring(L, err);
    else lua_pushnil(L);
}
