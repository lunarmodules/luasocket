/*=========================================================================*\
* Buffered input/output routines
* Lua methods:
*   send: unbuffered send using C base_send
*   receive: buffered read using C base_receive
\*=========================================================================*/
#include <lua.h>
#include <lauxlib.h>

#include "lsbuf.h"

/*=========================================================================*\
* Internal function prototypes.
\*=========================================================================*/
static int sendraw(lua_State *L, p_buf buf, cchar *data, size_t len, 
        size_t *done);
static int recvraw(lua_State *L, p_buf buf, size_t wanted);
static int recvdosline(lua_State *L, p_buf buf);
static int recvunixline(lua_State *L, p_buf buf);
static int recvall(lua_State *L, p_buf buf);

static int buf_contents(lua_State *L, p_buf buf, cchar **data, size_t *len);
static void buf_skip(lua_State *L, p_buf buf, size_t len);

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
* Input
*   buf: buffer structure to initialize
*   base: socket object to associate with buffer structure
\*-------------------------------------------------------------------------*/
void buf_init(lua_State *L, p_buf buf, p_base base)
{
    (void) L;
	buf->buf_first = buf->buf_last = 0;
    buf->buf_base = base;
}

/*-------------------------------------------------------------------------*\
* Send data through buffered object
* Input
*   buf: buffer structure to be used
* Lua Input: self, a_1 [, a_2, a_3 ... a_n]
*   self: socket object
*   a_i: strings to be sent. 
* Lua Returns
*   On success: nil, followed by the total number of bytes sent
*   On error: error message
\*-------------------------------------------------------------------------*/
int buf_send(lua_State *L, p_buf buf)
{
    int top = lua_gettop(L);
    size_t total = 0;
    int err = PRIV_DONE;
    int arg;
    p_base base = buf->buf_base;
    tm_markstart(&base->base_tm);
    for (arg = 2; arg <= top; arg++) { /* first arg is socket object */
        size_t done, len;
        cchar *data = luaL_optlstring(L, arg, NULL, &len);
        if (!data || err != PRIV_DONE) break;
        err = sendraw(L, buf, data, len, &done);
        total += done;
    }
    priv_pusherror(L, err);
    lua_pushnumber(L, total);
#ifdef LUASOCKET_DEBUG
    /* push time elapsed during operation as the last return value */
    lua_pushnumber(L, tm_getelapsed(&base->base_tm)/1000.0);
#endif
    return lua_gettop(L) - top;
}

/*-------------------------------------------------------------------------*\
* Receive data from a buffered object
* Input
*   buf: buffer structure to be used
* Lua Input: self [pat_1, pat_2 ... pat_n]
*   self: socket object
*   pat_i: may be one of the following 
*     "*l": reads a text line, defined as a string of caracters terminates
*       by a LF character, preceded or not by a CR character. This is
*       the default pattern
*     "*lu": reads a text line, terminanted by a CR character only. (Unix mode)
*     "*a": reads until connection closed
*     number: reads 'number' characters from the socket object
* Lua Returns
*   On success: one string for each pattern
*   On error: all strings for which there was no error, followed by one
*     nil value for the remaining strings, followed by an error code
\*-------------------------------------------------------------------------*/
int buf_receive(lua_State *L, p_buf buf)
{
    int top = lua_gettop(L);
    int arg, err = PRIV_DONE;
    p_base base = buf->buf_base;
    tm_markstart(&base->base_tm);
    /* push default pattern if need be */
    if (top < 2) {
        lua_pushstring(L, "*l");
        top++;
    }
    /* make sure we have enough stack space */
    luaL_checkstack(L, top+LUA_MINSTACK, "too many arguments");
    /* receive all patterns */
    for (arg = 2; arg <= top && err == PRIV_DONE; arg++) {
        if (!lua_isnumber(L, arg)) {
            static cchar *patternnames[] = {"*l", "*lu", "*a", "*w", NULL};
            cchar *pattern = luaL_optstring(L, arg, NULL);
            /* get next pattern */
            switch (luaL_findstring(pattern, patternnames)) {
                case 0: /* DOS line pattern */
                    err = recvdosline(L, buf); break;
                case 1: /* Unix line pattern */
                    err = recvunixline(L, buf); break;
                case 2: /* Until closed pattern */
                    err = recvall(L, buf); break;
                case 3: /* Word pattern */
                    luaL_argcheck(L, 0, arg, "word patterns are deprecated");
                    break;
                default: /* else it is an error */
                    luaL_argcheck(L, 0, arg, "invalid receive pattern");
                    break;
            }
        /* raw pattern */
        } else err = recvraw(L, buf, (size_t) lua_tonumber(L, arg));
    }
    /* push nil for each pattern after an error */
    for ( ; arg <= top; arg++) lua_pushnil(L);
    /* last return is an error code */
    priv_pusherror(L, err);
#ifdef LUASOCKET_DEBUG
    /* push time elapsed during operation as the last return value */
    lua_pushnumber(L, tm_getelapsed(&base->base_tm)/1000.0);
#endif
    return lua_gettop(L) - top;
}

/*-------------------------------------------------------------------------*\
* Determines if there is any data in the read buffer
* Input
*   buf: buffer structure to be used
* Returns
*   1 if empty, 0 if there is data
\*-------------------------------------------------------------------------*/
int buf_isempty(lua_State *L, p_buf buf)
{
    (void) L;
    return buf->buf_first >= buf->buf_last;
}

/*=========================================================================*\
* Internal functions
\*=========================================================================*/
/*-------------------------------------------------------------------------*\
* Sends a raw block of data through a buffered object.
* Input
*   buf: buffer structure to be used
*   data: data to be sent
*   len: number of bytes to send
* Output
*   sent: number of bytes sent
* Returns
*   operation error code.
\*-------------------------------------------------------------------------*/
static int sendraw(lua_State *L, p_buf buf, cchar *data, size_t len, 
        size_t *sent)
{
    p_base base = buf->buf_base;
    size_t total = 0;
    int err = PRIV_DONE;
    while (total < len && err == PRIV_DONE) {
        size_t done;
        err = base->base_send(L, base, data + total, len - total, &done);
        total += done;
    }
    *sent = total;
    return err;
}

/*-------------------------------------------------------------------------*\
* Reads a raw block of data from a buffered object.
* Input
*   buf: buffer structure
*   wanted: number of bytes to be read
* Returns
*   operation error code.
\*-------------------------------------------------------------------------*/
static int recvraw(lua_State *L, p_buf buf, size_t wanted)
{
    int err =  PRIV_DONE;
    size_t total = 0;
    luaL_Buffer b;
    luaL_buffinit(L, &b);
    while (total < wanted && err == PRIV_DONE) {
        size_t len; cchar *data;
        err = buf_contents(L, buf, &data, &len);
        len = MIN(len, wanted - total);
        luaL_addlstring(&b, data, len);
        buf_skip(L, buf, len);
        total += len;
    }
    luaL_pushresult(&b);
    return err;
}

/*-------------------------------------------------------------------------*\
* Reads everything until the connection is closed
* Input
*   buf: buffer structure
* Result
*   operation error code.
\*-------------------------------------------------------------------------*/
static int recvall(lua_State *L, p_buf buf)
{
    int err = PRIV_DONE;
    luaL_Buffer b;
    luaL_buffinit(L, &b);
    while (err == PRIV_DONE) {
        cchar *data; size_t len;
        err = buf_contents(L, buf, &data, &len);
        luaL_addlstring(&b, data, len);
        buf_skip(L, buf, len);
    }
    luaL_pushresult(&b);
    return err;
}

/*-------------------------------------------------------------------------*\
* Reads a line terminated by a CR LF pair or just by a LF. The CR and LF 
* are not returned by the function and are discarded from the buffer. 
* Input
*   buf: buffer structure
* Result
*   operation error code. PRIV_DONE, PRIV_TIMEOUT or PRIV_CLOSED
\*-------------------------------------------------------------------------*/
static int recvdosline(lua_State *L, p_buf buf)
{
    int err = 0;
    luaL_Buffer b;
    luaL_buffinit(L, &b);
    while (err == PRIV_DONE) {
        size_t len, pos; cchar *data;
        err = buf_contents(L, buf, &data, &len);
        pos = 0;
        while (pos < len && data[pos] != '\n') {
            /* we ignore all \r's */
            if (data[pos] != '\r') luaL_putchar(&b, data[pos]);
            pos++;
        }
        if (pos < len) { /* found '\n' */
            buf_skip(L, buf, pos+1); /* skip '\n' too */
            break; /* we are done */
        } else /* reached the end of the buffer */
            buf_skip(L, buf, pos);
    }
    luaL_pushresult(&b);
    return err;
}

/*-------------------------------------------------------------------------*\
* Reads a line terminated by a LF character, which is not returned by
* the function, and is skipped in the buffer. 
* Input
*   buf: buffer structure
* Returns
*   operation error code. PRIV_DONE, PRIV_TIMEOUT or PRIV_CLOSED
\*-------------------------------------------------------------------------*/
static int recvunixline(lua_State *L, p_buf buf)
{
    int err = PRIV_DONE;
    luaL_Buffer b;
    luaL_buffinit(L, &b);
    while (err == 0) {
        size_t pos, len; cchar *data;
        err = buf_contents(L, buf, &data, &len);
        pos = 0;
        while (pos < len && data[pos] != '\n') {
            luaL_putchar(&b, data[pos]);
            pos++;
        }
        if (pos < len) { /* found '\n' */
            buf_skip(L, buf, pos+1); /* skip '\n' too */
            break; /* we are done */
        } else /* reached the end of the buffer */
            buf_skip(L, buf, pos);
    }
    luaL_pushresult(&b);
    return err;
}

/*-------------------------------------------------------------------------*\
* Skips a given number of bytes in read buffer
* Input
*   buf: buffer structure
*   len: number of bytes to skip
\*-------------------------------------------------------------------------*/
static void buf_skip(lua_State *L, p_buf buf, size_t len)
{
    buf->buf_first += len;
    if (buf_isempty(L, buf)) buf->buf_first = buf->buf_last = 0;
}

/*-------------------------------------------------------------------------*\
* Return any data available in buffer, or get more data from transport layer
* if buffer is empty.
* Input
*   buf: buffer structure
* Output
*   data: pointer to buffer start
*   len: buffer buffer length
* Returns
*   PRIV_DONE, PRIV_CLOSED, PRIV_TIMEOUT ...
\*-------------------------------------------------------------------------*/
static int buf_contents(lua_State *L, p_buf buf, cchar **data, size_t *len)
{
    int err = PRIV_DONE;
    p_base base = buf->buf_base;
    if (buf_isempty(L, buf)) {
        size_t done;
        err = base->base_receive(L, base, buf->buf_data, BUF_SIZE, &done);
        buf->buf_first = 0;
        buf->buf_last = done;
    }
    *len = buf->buf_last - buf->buf_first;
    *data = buf->buf_data + buf->buf_first;
    return err;
}
