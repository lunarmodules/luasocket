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
void io_init(p_io io, p_send send, p_recv recv, void *ctx)
{
    io->send = send;
    io->recv = recv;
    io->ctx = ctx;
}

/*-------------------------------------------------------------------------*\
* Translate error codes to Lua
\*-------------------------------------------------------------------------*/
const char *io_strerror(int code)
{
    switch (code) {
        case IO_DONE: return NULL;
        case IO_TIMEOUT: return "timeout";
        case IO_RETRY: return "retry";
        case IO_CLOSED: return "closed";
        case IO_REFUSED: return "refused";
        default: return "unknown error";
    }
}

/*-------------------------------------------------------------------------*\
* Translate error codes to Lua
\*-------------------------------------------------------------------------*/
void io_pusherror(lua_State *L, int code)
{
    const char *err = io_strerror(code);
    if (err) lua_pushstring(L, err);
    else lua_pushnil(L);
}
