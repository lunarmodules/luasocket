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
void io_pusherror(lua_State *L, int code)
{
    switch (code) {
        case IO_DONE:
            lua_pushnil(L);
            break;
        case IO_TIMEOUT:
            lua_pushstring(L, "timeout");
            break;
        case IO_LIMITED:
            lua_pushstring(L, "limited");
            break;
        case IO_CLOSED:
            lua_pushstring(L, "closed");
            break;
        case IO_REFUSED:
            lua_pushstring(L, "refused");
            break;
        default:
            lua_pushstring(L, "unknown error");
            break;
    }
}

