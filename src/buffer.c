/*=========================================================================*\
* Input/Output interface for Lua programs
* LuaSocket toolkit
*
* RCS ID: $Id$
\*=========================================================================*/
#include <lua.h>
#include <lauxlib.h>

#include "buffer.h"

/*=========================================================================*\
* Internal function prototypes
\*=========================================================================*/
static int recvraw(p_buf buf, size_t wanted, luaL_Buffer *b);
static int recvline(p_buf buf, luaL_Buffer *b);
static int recvall(p_buf buf, luaL_Buffer *b);
static int buf_get(p_buf buf, const char **data, size_t *count);
static void buf_skip(p_buf buf, size_t count);
static int sendraw(p_buf buf, const char *data, size_t count, size_t *sent);

/* min and max macros */
#ifndef MIN
#define MIN(x, y) ((x) < (y) ? x : y)
#endif
#ifndef MAX
#define MAX(x, y) ((x) > (y) ? x : y)
#endif

/*=========================================================================*\
* Exported functions
\*=========================================================================*/
/*-------------------------------------------------------------------------*\
* Initializes module
\*-------------------------------------------------------------------------*/
int buf_open(lua_State *L) {
    (void) L;
    return 0;
}

/*-------------------------------------------------------------------------*\
* Initializes C structure 
\*-------------------------------------------------------------------------*/
void buf_init(p_buf buf, p_io io, p_tm tm) {
	buf->first = buf->last = 0;
    buf->io = io;
    buf->tm = tm;
    buf->received = buf->sent = 0;
    buf->birthday = tm_gettime();
}

/*-------------------------------------------------------------------------*\
* object:getstats() interface
\*-------------------------------------------------------------------------*/
int buf_meth_getstats(lua_State *L, p_buf buf) {
    lua_pushnumber(L, buf->received);
    lua_pushnumber(L, buf->sent);
    lua_pushnumber(L, tm_gettime() - buf->birthday);
    return 3;
}

/*-------------------------------------------------------------------------*\
* object:setstats() interface
\*-------------------------------------------------------------------------*/
int buf_meth_setstats(lua_State *L, p_buf buf) {
    buf->received = (long) luaL_optnumber(L, 2, buf->received); 
    buf->sent = (long) luaL_optnumber(L, 3, buf->sent); 
    if (lua_isnumber(L, 4)) buf->birthday = tm_gettime() - lua_tonumber(L, 4);
    lua_pushnumber(L, 1);
    return 1;
}

/*-------------------------------------------------------------------------*\
* object:send() interface
\*-------------------------------------------------------------------------*/
int buf_meth_send(lua_State *L, p_buf buf) {
    int top = lua_gettop(L);
    p_tm tm = tm_markstart(buf->tm);
    int err = IO_DONE;
    size_t size = 0, sent = 0;
    const char *data = luaL_checklstring(L, 2, &size);
    long start = (long) luaL_optnumber(L, 3, 1);
    long end = (long) luaL_optnumber(L, 4, -1);
    if (start < 0) start = (long) (size+start+1);
    if (end < 0) end = (long) (size+end+1);
    if (start < 1) start = (long) 1;
    if (end > (long) size) end = (long) size;
    if (start <= end) err = sendraw(buf, data+start-1, end-start+1, &sent);
    /* check if there was an error */
    if (err != IO_DONE) {
        lua_pushnil(L);
        lua_pushstring(L, buf->io->error(buf->io->ctx, err)); 
        lua_pushnumber(L, sent+start-1);
    } else {
        lua_pushnumber(L, sent+start-1);
        lua_pushnil(L);
        lua_pushnil(L);
    }
#ifdef LUASOCKET_DEBUG
    /* push time elapsed during operation as the last return value */
    lua_pushnumber(L, tm_gettime() - tm_getstart(tm));
#endif
    return lua_gettop(L) - top;
}

/*-------------------------------------------------------------------------*\
* object:receive() interface
\*-------------------------------------------------------------------------*/
int buf_meth_receive(lua_State *L, p_buf buf) {
    int err = IO_DONE, top = lua_gettop(L);
    p_tm tm = tm_markstart(buf->tm);
    luaL_Buffer b;
    size_t size;
    const char *part = luaL_optlstring(L, 3, "", &size);
    /* initialize buffer with optional extra prefix 
     * (useful for concatenating previous partial results) */
    luaL_buffinit(L, &b);
    luaL_addlstring(&b, part, size);
    /* receive new patterns */
    if (!lua_isnumber(L, 2)) {
        const char *p= luaL_optstring(L, 2, "*l");
        if (p[0] == '*' && p[1] == 'l') err = recvline(buf, &b);
        else if (p[0] == '*' && p[1] == 'a') err = recvall(buf, &b); 
        else luaL_argcheck(L, 0, 2, "invalid receive pattern");
        /* get a fixed number of bytes */
    } else err = recvraw(buf, (size_t) lua_tonumber(L, 2)-size, &b);
    /* check if there was an error */
    if (err != IO_DONE) {
        /* we can't push anyting in the stack before pushing the
         * contents of the buffer. this is the reason for the complication */
        luaL_pushresult(&b);
        lua_pushstring(L, buf->io->error(buf->io->ctx, err)); 
        lua_pushvalue(L, -2); 
        lua_pushnil(L);
        lua_replace(L, -4);
    } else {
        luaL_pushresult(&b);
        lua_pushnil(L);
        lua_pushnil(L);
    }
#ifdef LUASOCKET_DEBUG
    /* push time elapsed during operation as the last return value */
    lua_pushnumber(L, tm_gettime() - tm_getstart(tm));
#endif
    return lua_gettop(L) - top;
}

/*-------------------------------------------------------------------------*\
* Determines if there is any data in the read buffer
\*-------------------------------------------------------------------------*/
int buf_isempty(p_buf buf) {
    return buf->first >= buf->last;
}

/*=========================================================================*\
* Internal functions
\*=========================================================================*/
/*-------------------------------------------------------------------------*\
* Sends a block of data (unbuffered)
\*-------------------------------------------------------------------------*/
#define STEPSIZE 8192
static int sendraw(p_buf buf, const char *data, size_t count, size_t *sent) {
    p_io io = buf->io;
    p_tm tm = buf->tm;
    size_t total = 0;
    int err = IO_DONE;
    while (total < count && err == IO_DONE) {
        size_t done;
        size_t step = (count-total <= STEPSIZE)? count-total: STEPSIZE;
        err = io->send(io->ctx, data+total, step, &done, tm);
        total += done;
    }
    *sent = total;
    buf->sent += total;
    return err;
}

/*-------------------------------------------------------------------------*\
* Reads a fixed number of bytes (buffered)
\*-------------------------------------------------------------------------*/
static int recvraw(p_buf buf, size_t wanted, luaL_Buffer *b) {
    int err = IO_DONE;
    size_t total = 0;
    while (total < wanted && err == IO_DONE) {
        size_t count; const char *data;
        err = buf_get(buf, &data, &count);
        count = MIN(count, wanted - total);
        luaL_addlstring(b, data, count);
        buf_skip(buf, count);
        total += count;
    }
    return err;
}

/*-------------------------------------------------------------------------*\
* Reads everything until the connection is closed (buffered)
\*-------------------------------------------------------------------------*/
static int recvall(p_buf buf, luaL_Buffer *b) {
    int err = IO_DONE;
    while (err == IO_DONE) {
        const char *data; size_t count;
        err = buf_get(buf, &data, &count);
        luaL_addlstring(b, data, count);
        buf_skip(buf, count);
    }
    if (err == IO_CLOSED) return IO_DONE;
    else return err;
}

/*-------------------------------------------------------------------------*\
* Reads a line terminated by a CR LF pair or just by a LF. The CR and LF 
* are not returned by the function and are discarded from the buffer
\*-------------------------------------------------------------------------*/
static int recvline(p_buf buf, luaL_Buffer *b) {
    int err = IO_DONE;
    while (err == IO_DONE) {
        size_t count, pos; const char *data;
        err = buf_get(buf, &data, &count);
        pos = 0;
        while (pos < count && data[pos] != '\n') {
            /* we ignore all \r's */
            if (data[pos] != '\r') luaL_putchar(b, data[pos]);
            pos++;
        }
        if (pos < count) { /* found '\n' */
            buf_skip(buf, pos+1); /* skip '\n' too */
            break; /* we are done */
        } else /* reached the end of the buffer */
            buf_skip(buf, pos);
    }
    return err;
}

/*-------------------------------------------------------------------------*\
* Skips a given number of bytes from read buffer. No data is read from the
* transport layer
\*-------------------------------------------------------------------------*/
static void buf_skip(p_buf buf, size_t count) {
    buf->received += count;
    buf->first += count;
    if (buf_isempty(buf)) 
        buf->first = buf->last = 0;
}

/*-------------------------------------------------------------------------*\
* Return any data available in buffer, or get more data from transport layer
* if buffer is empty
\*-------------------------------------------------------------------------*/
static int buf_get(p_buf buf, const char **data, size_t *count) {
    int err = IO_DONE;
    p_io io = buf->io;
    p_tm tm = buf->tm;
    if (buf_isempty(buf)) {
        size_t got;
        err = io->recv(io->ctx, buf->data, BUF_SIZE, &got, tm);
        buf->first = 0;
        buf->last = got;
    }
    *count = buf->last - buf->first;
    *data = buf->data + buf->first;
    return err;
}
