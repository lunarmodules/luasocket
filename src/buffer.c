/*=========================================================================*\
* Input/Output interface for Lua programs
* LuaSocket toolkit
*
* RCS ID: $Id$
\*=========================================================================*/
#include <lua.h>
#include <lauxlib.h>

#include "auxiliar.h"
#include "buffer.h"

/*=========================================================================*\
* Internal function prototypes
\*=========================================================================*/
static int recvraw(lua_State *L, p_buf buf, size_t wanted);
static int recvline(lua_State *L, p_buf buf);
static int recvall(lua_State *L, p_buf buf);
static int buf_get(p_buf buf, const char **data, size_t *count);
static void buf_skip(p_buf buf, size_t count);
static int sendraw(p_buf buf, const char *data, size_t count, size_t *sent);

/*=========================================================================*\
* Exported functions
\*=========================================================================*/
/*-------------------------------------------------------------------------*\
* Initializes module
\*-------------------------------------------------------------------------*/
void buf_open(lua_State *L)
{
    (void) L;
}

/*-------------------------------------------------------------------------*\
* Initializes C structure 
\*-------------------------------------------------------------------------*/
void buf_init(p_buf buf, p_io io, p_tm tm)
{
	buf->first = buf->last = 0;
    buf->io = io;
    buf->tm = tm;
}

/*-------------------------------------------------------------------------*\
* object:send() interface
\*-------------------------------------------------------------------------*/
int buf_meth_send(lua_State *L, p_buf buf)
{
    int top = lua_gettop(L);
    size_t total = 0;
    int arg, err = IO_DONE;
    p_tm tm = buf->tm;
    tm_markstart(tm);
    for (arg = 2; arg <= top; arg++) { /* first arg is socket object */
        size_t sent, count;
        const char *data = luaL_optlstring(L, arg, NULL, &count);
        if (!data || err != IO_DONE) break;
        err = sendraw(buf, data, count, &sent);
        total += sent;
    }
    lua_pushnumber(L, total);
    io_pusherror(L, err);
#ifdef LUASOCKET_DEBUG
    /* push time elapsed during operation as the last return value */
    lua_pushnumber(L, (tm_gettime() - tm_getstart(tm))/1000.0);
#endif
    return lua_gettop(L) - top;
}

/*-------------------------------------------------------------------------*\
* object:receive() interface
\*-------------------------------------------------------------------------*/
int buf_meth_receive(lua_State *L, p_buf buf)
{
    int top = lua_gettop(L);
    int arg, err = IO_DONE;
    p_tm tm = buf->tm;
    tm_markstart(tm);
    /* push default pattern if need be */
    if (top < 2) {
        lua_pushstring(L, "*l");
        top++;
    }
    /* make sure we have enough stack space for all returns */
    luaL_checkstack(L, top+LUA_MINSTACK, "too many arguments");
    /* receive all patterns */
    for (arg = 2; arg <= top && err == IO_DONE; arg++) {
        if (!lua_isnumber(L, arg)) {
            static const char *patternnames[] = {"*l", "*a", NULL};
            const char *pattern = lua_isnil(L, arg) ? 
                "*l" : luaL_checkstring(L, arg);
            /* get next pattern */
            switch (luaL_findstring(pattern, patternnames)) {
                case 0: /* line pattern */
                    err = recvline(L, buf); break;
                case 1: /* until closed pattern */
                    err = recvall(L, buf); 
                    if (err == IO_CLOSED) err = IO_DONE;
                    break;
                default: /* else it is an error */
                    luaL_argcheck(L, 0, arg, "invalid receive pattern");
                    break;
            }
        /* get a fixed number of bytes */
        } else err = recvraw(L, buf, (size_t) lua_tonumber(L, arg));
    }
    /* push nil for each pattern after an error */
    for ( ; arg <= top; arg++) lua_pushnil(L);
    /* last return is an error code */
    io_pusherror(L, err);
#ifdef LUASOCKET_DEBUG
    /* push time elapsed during operation as the last return value */
    lua_pushnumber(L, (tm_gettime() - tm_getstart(tm))/1000.0);
#endif
    return lua_gettop(L) - top;
}

/*-------------------------------------------------------------------------*\
* Determines if there is any data in the read buffer
\*-------------------------------------------------------------------------*/
int buf_isempty(p_buf buf)
{
    return buf->first >= buf->last;
}

/*=========================================================================*\
* Internal functions
\*=========================================================================*/
/*-------------------------------------------------------------------------*\
* Sends a block of data (unbuffered)
\*-------------------------------------------------------------------------*/
static 
int sendraw(p_buf buf, const char *data, size_t count, size_t *sent)
{
    p_io io = buf->io;
    p_tm tm = buf->tm;
    size_t total = 0;
    int err = IO_DONE;
    while (total < count && err == IO_DONE) {
        size_t done;
        err = io->send(io->ctx, data+total, count-total, &done, tm_get(tm));
        total += done;
    }
    *sent = total;
    return err;
}

/*-------------------------------------------------------------------------*\
* Reads a fixed number of bytes (buffered)
\*-------------------------------------------------------------------------*/
static 
int recvraw(lua_State *L, p_buf buf, size_t wanted)
{
    int err =  IO_DONE;
    size_t total = 0;
    luaL_Buffer b;
    luaL_buffinit(L, &b);
    while (total < wanted && (err == IO_DONE || err == IO_RETRY)) {
        size_t count; const char *data;
        err = buf_get(buf, &data, &count);
        count = MIN(count, wanted - total);
        luaL_addlstring(&b, data, count);
        buf_skip(buf, count);
        total += count;
    }
    luaL_pushresult(&b);
    return err;
}

/*-------------------------------------------------------------------------*\
* Reads everything until the connection is closed (buffered)
\*-------------------------------------------------------------------------*/
static 
int recvall(lua_State *L, p_buf buf)
{
    int err = IO_DONE;
    luaL_Buffer b;
    luaL_buffinit(L, &b);
    while (err == IO_DONE || err == IO_RETRY) {
        const char *data; size_t count;
        err = buf_get(buf, &data, &count);
        luaL_addlstring(&b, data, count);
        buf_skip(buf, count);
    }
    luaL_pushresult(&b);
    return err;
}

/*-------------------------------------------------------------------------*\
* Reads a line terminated by a CR LF pair or just by a LF. The CR and LF 
* are not returned by the function and are discarded from the buffer
\*-------------------------------------------------------------------------*/
static 
int recvline(lua_State *L, p_buf buf)
{
    int err = IO_DONE;
    luaL_Buffer b;
    luaL_buffinit(L, &b);
    while (err == IO_DONE || err == IO_RETRY) {
        size_t count, pos; const char *data;
        err = buf_get(buf, &data, &count);
        pos = 0;
        while (pos < count && data[pos] != '\n') {
            /* we ignore all \r's */
            if (data[pos] != '\r') luaL_putchar(&b, data[pos]);
            pos++;
        }
        if (pos < count) { /* found '\n' */
            buf_skip(buf, pos+1); /* skip '\n' too */
            break; /* we are done */
        } else /* reached the end of the buffer */
            buf_skip(buf, pos);
    }
    luaL_pushresult(&b);
    return err;
}

/*-------------------------------------------------------------------------*\
* Skips a given number of bytes from read buffer. No data is read from the
* transport layer
\*-------------------------------------------------------------------------*/
static 
void buf_skip(p_buf buf, size_t count)
{
    buf->first += count;
    if (buf_isempty(buf)) 
        buf->first = buf->last = 0;
}

/*-------------------------------------------------------------------------*\
* Return any data available in buffer, or get more data from transport layer
* if buffer is empty
\*-------------------------------------------------------------------------*/
static 
int buf_get(p_buf buf, const char **data, size_t *count)
{
    int err = IO_DONE;
    p_io io = buf->io;
    p_tm tm = buf->tm;
    if (buf_isempty(buf)) {
        size_t got;
        err = io->recv(io->ctx, buf->data, BUF_SIZE, &got, tm_get(tm));
        buf->first = 0;
        buf->last = got;
    }
    *count = buf->last - buf->first;
    *data = buf->data + buf->first;
    return err;
}

