/*=========================================================================*\
* Encoding support functions
* LuaSocket toolkit
*
* RCS ID: $Id$
\*=========================================================================*/
#include <string.h>

#include <lua.h>
#include <lauxlib.h>

#include "luasocket.h"
#include "mime.h"

/*=========================================================================*\
* Don't want to trust escape character constants
\*=========================================================================*/
#define CR 0x0D
#define LF 0x0A
#define HT 0x09
#define SP 0x20

typedef unsigned char UC;
static const char CRLF[2] = {CR, LF};
static const char EQCRLF[3] = {'=', CR, LF};

/*=========================================================================*\
* Internal function prototypes.
\*=========================================================================*/
static int mime_global_fmt(lua_State *L);
static int mime_global_b64(lua_State *L);
static int mime_global_unb64(lua_State *L);
static int mime_global_qp(lua_State *L);
static int mime_global_unqp(lua_State *L);
static int mime_global_qpfmt(lua_State *L);
static int mime_global_eol(lua_State *L);

static void b64fill(UC *b64unbase);
static size_t b64encode(UC c, UC *input, size_t size, luaL_Buffer *buffer);
static size_t b64pad(const UC *input, size_t size, luaL_Buffer *buffer);
static size_t b64decode(UC c, UC *input, size_t size, luaL_Buffer *buffer);

static void qpfill(UC *qpclass, UC *qpunbase);
static void qpquote(UC c, luaL_Buffer *buffer);
static size_t qpdecode(UC c, UC *input, size_t size, luaL_Buffer *buffer);
static size_t qpencode(UC c, UC *input, size_t size, 
        const char *marker, luaL_Buffer *buffer);

/* code support functions */
static luaL_reg func[] = {
    { "eol", mime_global_eol },
    { "qp", mime_global_qp },
    { "unqp", mime_global_unqp },
    { "qpfmt", mime_global_qpfmt },
    { "b64", mime_global_b64 },
    { "unb64", mime_global_unb64 },
    { "fmt", mime_global_fmt },
    { NULL, NULL }
};

/*-------------------------------------------------------------------------*\
* Quoted-printable globals
\*-------------------------------------------------------------------------*/
static UC qpclass[256];
static UC qpbase[] = "0123456789ABCDEF";
static UC qpunbase[256];
enum {QP_PLAIN, QP_QUOTED, QP_CR, QP_IF_LAST};

/*-------------------------------------------------------------------------*\
* Base64 globals
\*-------------------------------------------------------------------------*/
static const UC b64base[] =
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
static UC b64unbase[256];

/*=========================================================================*\
* Exported functions
\*=========================================================================*/
/*-------------------------------------------------------------------------*\
* Initializes module
\*-------------------------------------------------------------------------*/
void mime_open(lua_State *L)
{
    lua_pushstring(L, LUASOCKET_LIBNAME);
    lua_gettable(L, LUA_GLOBALSINDEX);
    if (lua_isnil(L, -1)) {
        lua_pop(L, 1);
        lua_newtable(L);
        lua_pushstring(L, LUASOCKET_LIBNAME);
        lua_pushvalue(L, -2);
        lua_settable(L, LUA_GLOBALSINDEX);
    }
    lua_pushstring(L, "mime");
    lua_newtable(L);
    luaL_openlib(L, NULL, func, 0);
    lua_settable(L, -3);
    lua_pop(L, 1);
    /* initialize lookup tables */
    qpfill(qpclass, qpunbase);
    b64fill(b64unbase);
}

/*=========================================================================*\
* Global Lua functions
\*=========================================================================*/
/*-------------------------------------------------------------------------*\
* Incrementaly breaks a string into lines
* A, n = fmt(B, length, left)
* A is a copy of B, broken into lines of at most 'length' bytes. 
* Left is how many bytes are left in the first line of B. 'n' is the number 
* of bytes left in the last line of A. 
\*-------------------------------------------------------------------------*/
static int mime_global_fmt(lua_State *L)
{
    size_t size = 0;
    const UC *input = (UC *) (lua_isnil(L, 1)? NULL: 
            luaL_checklstring(L, 1, &size));
    const UC *last = input + size;
    int length = (int) luaL_checknumber(L, 2);
    int left = (int) luaL_optnumber(L, 3, length);
    const char *marker = luaL_optstring(L, 4, CRLF);
    luaL_Buffer buffer;
    luaL_buffinit(L, &buffer);
    while (input < last) {
        luaL_putchar(&buffer, *input++);
        if (--left <= 0) {
            luaL_addstring(&buffer, marker);
            left = length;
        }
    }
    if (!input && left < length) {
        luaL_addstring(&buffer, marker);
        left = length;
    }
    luaL_pushresult(&buffer);
    lua_pushnumber(L, left);
    return 2;
}

/*-------------------------------------------------------------------------*\
* Fill base64 decode map. 
\*-------------------------------------------------------------------------*/
static void b64fill(UC *b64unbase) 
{
    int i;
    for (i = 0; i < 255; i++) b64unbase[i] = 255;
    for (i = 0; i < 64; i++) b64unbase[b64base[i]] = i;
    b64unbase['='] = 0;
}

/*-------------------------------------------------------------------------*\
* Acumulates bytes in input buffer until 3 bytes are available. 
* Translate the 3 bytes into Base64 form and append to buffer.
* Returns new number of bytes in buffer.
\*-------------------------------------------------------------------------*/
static size_t b64encode(UC c, UC *input, size_t size, 
        luaL_Buffer *buffer)
{
    input[size++] = c;
    if (size == 3) {
        UC code[4];
        unsigned long value = 0;
        value += input[0]; value <<= 8;
        value += input[1]; value <<= 8;
        value += input[2]; 
        code[3] = b64base[value & 0x3f]; value >>= 6;
        code[2] = b64base[value & 0x3f]; value >>= 6;
        code[1] = b64base[value & 0x3f]; value >>= 6;
        code[0] = b64base[value];
        luaL_addlstring(buffer, (char *) code, 4);
        size = 0;
    }
    return size;
}

/*-------------------------------------------------------------------------*\
* Encodes the Base64 last 1 or 2 bytes and adds padding '=' 
* Result, if any, is appended to buffer.
* Returns 0.
\*-------------------------------------------------------------------------*/
static size_t b64pad(const UC *input, size_t size, 
        luaL_Buffer *buffer)
{
    unsigned long value = 0;
    UC code[4] = "====";
    switch (size) {
        case 1:
            value = input[0] << 4;
            code[1] = b64base[value & 0x3f]; value >>= 6;
            code[0] = b64base[value];
            luaL_addlstring(buffer, (char *) code, 4);
            break;
        case 2:
            value = input[0]; value <<= 8; 
            value |= input[1]; value <<= 2;
            code[2] = b64base[value & 0x3f]; value >>= 6;
            code[1] = b64base[value & 0x3f]; value >>= 6;
            code[0] = b64base[value];
            luaL_addlstring(buffer, (char *) code, 4);
            break;
        case 0: /* fall through */
        default:
            break;
    }
    return 0;
}

/*-------------------------------------------------------------------------*\
* Acumulates bytes in input buffer until 4 bytes are available. 
* Translate the 4 bytes from Base64 form and append to buffer.
* Returns new number of bytes in buffer.
\*-------------------------------------------------------------------------*/
static size_t b64decode(UC c, UC *input, size_t size, 
        luaL_Buffer *buffer)
{

    /* ignore invalid characters */
    if (b64unbase[c] > 64) return size;
    input[size++] = c;
    /* decode atom */
    if (size == 4) {
        UC decoded[3];
        int valid, value = 0;
        value =  b64unbase[input[0]]; value <<= 6;
        value |= b64unbase[input[1]]; value <<= 6;
        value |= b64unbase[input[2]]; value <<= 6;
        value |= b64unbase[input[3]];
        decoded[2] = (UC) (value & 0xff); value >>= 8;
        decoded[1] = (UC) (value & 0xff); value >>= 8;
        decoded[0] = (UC) value;
        /* take care of paddding */
        valid = (input[2] == '=') ? 1 : (input[3] == '=') ? 2 : 3; 
        luaL_addlstring(buffer, (char *) decoded, valid);
        return 0;
    /* need more data */
    } else return size;
}

/*-------------------------------------------------------------------------*\
* Incrementally applies the Base64 transfer content encoding to a string
* A, B = b64(C, D)
* A is the encoded version of the largest prefix of C .. D that is
* divisible by 3. B has the remaining bytes of C .. D, *without* encoding.
* The easiest thing would be to concatenate the two strings and 
* encode the result, but we can't afford that or Lua would dupplicate
* every chunk we received.
\*-------------------------------------------------------------------------*/
static int mime_global_b64(lua_State *L)
{
    UC atom[3];
    size_t isize = 0, asize = 0;
    const UC *input = (UC *) luaL_checklstring(L, 1, &isize);
    const UC *last = input + isize;
    luaL_Buffer buffer;
    luaL_buffinit(L, &buffer);
    while (input < last) 
        asize = b64encode(*input++, atom, asize, &buffer);
    input = (UC *) luaL_optlstring(L, 2, NULL, &isize);
    if (input) {
        last = input + isize;
        while (input < last) 
            asize = b64encode(*input++, atom, asize, &buffer);
    } else 
        asize = b64pad(atom, asize, &buffer);
    luaL_pushresult(&buffer);
    lua_pushlstring(L, (char *) atom, asize);
    return 2;
}

/*-------------------------------------------------------------------------*\
* Incrementally removes the Base64 transfer content encoding from a string
* A, B = b64(C, D)
* A is the encoded version of the largest prefix of C .. D that is
* divisible by 4. B has the remaining bytes of C .. D, *without* encoding.
\*-------------------------------------------------------------------------*/
static int mime_global_unb64(lua_State *L)
{
    UC atom[4];
    size_t isize = 0, asize = 0;
    const UC *input = (UC *) luaL_checklstring(L, 1, &isize);
    const UC *last = input + isize;
    luaL_Buffer buffer;
    luaL_buffinit(L, &buffer);
    while (input < last) 
        asize = b64decode(*input++, atom, asize, &buffer);
    input = (UC *) luaL_optlstring(L, 2, NULL, &isize);
    if (input) {
        last = input + isize;
        while (input < last) 
            asize = b64decode(*input++, atom, asize, &buffer);
    } 
    luaL_pushresult(&buffer);
    lua_pushlstring(L, (char *) atom, asize);
    return 2;
}

/*-------------------------------------------------------------------------*\
* Quoted-printable encoding scheme
* all (except CRLF in text) can be =XX
* CLRL in not text must be =XX=XX
* 33 through 60 inclusive can be plain
* 62 through 120 inclusive can be plain
* 9 and 32 can be plain, unless in the end of a line, where must be =XX
* encoded lines must be no longer than 76 not counting CRLF
* soft line-break are =CRLF
* !"#$@[\]^`{|}~ should be =XX for EBCDIC compatibility
* To encode one byte, we need to see the next two. 
* Worst case is when we see a space, and wonder if a CRLF is comming
\*-------------------------------------------------------------------------*/
/*-------------------------------------------------------------------------*\
* Split quoted-printable characters into classes
* Precompute reverse map for encoding
\*-------------------------------------------------------------------------*/
static void qpfill(UC *qpclass, UC *qpunbase)
{
    int i;
    for (i = 0; i < 256; i++) qpclass[i] = QP_QUOTED;
    for (i = 33; i <= 60; i++) qpclass[i] = QP_PLAIN;
    for (i = 62; i <= 120; i++) qpclass[i] = QP_PLAIN;
    qpclass[HT] = QP_IF_LAST; qpclass[SP] = QP_IF_LAST;
    qpclass['!'] = QP_QUOTED; qpclass['"'] = QP_QUOTED; 
    qpclass['#'] = QP_QUOTED; qpclass['$'] = QP_QUOTED; 
    qpclass['@'] = QP_QUOTED; qpclass['['] = QP_QUOTED;
    qpclass['\\'] = QP_QUOTED; qpclass[']'] = QP_QUOTED; 
    qpclass['^'] = QP_QUOTED; qpclass['`'] = QP_QUOTED; 
    qpclass['{'] = QP_QUOTED; qpclass['|'] = QP_QUOTED;
    qpclass['}'] = QP_QUOTED; qpclass['~'] = QP_QUOTED; 
    qpclass['}'] = QP_QUOTED; qpclass[CR] = QP_CR;
    for (i = 0; i < 256; i++) qpunbase[i] = 255;
    qpunbase['0'] = 0; qpunbase['1'] = 1; qpunbase['2'] = 2;
    qpunbase['3'] = 3; qpunbase['4'] = 4; qpunbase['5'] = 5;
    qpunbase['6'] = 6; qpunbase['7'] = 7; qpunbase['8'] = 8;
    qpunbase['9'] = 9; qpunbase['A'] = 10; qpunbase['a'] = 10;
    qpunbase['B'] = 11; qpunbase['b'] = 11; qpunbase['C'] = 12;
    qpunbase['c'] = 12; qpunbase['D'] = 13; qpunbase['d'] = 13;
    qpunbase['E'] = 14; qpunbase['e'] = 14; qpunbase['F'] = 15;
    qpunbase['f'] = 15;
}

/*-------------------------------------------------------------------------*\
* Output one character in form =XX
\*-------------------------------------------------------------------------*/
static void qpquote(UC c, luaL_Buffer *buffer)
{
    luaL_putchar(buffer, '=');
    luaL_putchar(buffer, qpbase[c >> 4]);
    luaL_putchar(buffer, qpbase[c & 0x0F]);
}

/*-------------------------------------------------------------------------*\
* Accumulate characters until we are sure about how to deal with them.
* Once we are sure, output the to the buffer, in the correct form. 
\*-------------------------------------------------------------------------*/
static size_t qpencode(UC c, UC *input, size_t size, 
        const char *marker, luaL_Buffer *buffer)
{
    input[size++] = c;
    /* deal with all characters we can have */
    while (size > 0) {
        switch (qpclass[input[0]]) {
            /* might be the CR of a CRLF sequence */
            case QP_CR:
                if (size < 2) return size;
                if (input[1] == LF) {
                    luaL_addstring(buffer, marker);
                    return 0;
                } else qpquote(input[0], buffer);
                break;
            /* might be a space and that has to be quoted if last in line */
            case QP_IF_LAST:
                if (size < 3) return size;
                /* if it is the last, quote it and we are done */
                if (input[1] == CR && input[2] == LF) {
                    qpquote(input[0], buffer);
                    luaL_addstring(buffer, marker);
                    return 0;
                } else luaL_putchar(buffer, input[0]);
                break;
                /* might have to be quoted always */
            case QP_QUOTED:
                qpquote(input[0], buffer);
                break;
                /* might never have to be quoted */
            default:
                luaL_putchar(buffer, input[0]);
                break;
        }
        input[0] = input[1]; input[1] = input[2];
        size--;
    }
    return 0;
}

/*-------------------------------------------------------------------------*\
* Deal with the final characters 
\*-------------------------------------------------------------------------*/
static void qppad(UC *input, size_t size, luaL_Buffer *buffer)
{
    size_t i;
    for (i = 0; i < size; i++) {
        if (qpclass[input[i]] == QP_PLAIN) luaL_putchar(buffer, input[i]);
        else qpquote(input[i], buffer);
    }
    luaL_addstring(buffer, EQCRLF);
}

/*-------------------------------------------------------------------------*\
* Incrementally converts a string to quoted-printable
* A, B = qp(C, D, marker)
* Crlf is the text to be used to replace CRLF sequences found in A.
* A is the encoded version of the largest prefix of C .. D that 
* can be encoded without doubts. 
* B has the remaining bytes of C .. D, *without* encoding.
\*-------------------------------------------------------------------------*/
static int mime_global_qp(lua_State *L)
{

    size_t asize = 0, isize = 0;
    UC atom[3];
    const UC *input = (UC *) (lua_isnil(L, 1) ? NULL: 
            luaL_checklstring(L, 1, &isize));
    const UC *last = input + isize;
    const char *marker = luaL_optstring(L, 3, CRLF);
    luaL_Buffer buffer;
    luaL_buffinit(L, &buffer);
    while (input < last)
        asize = qpencode(*input++, atom, asize, marker, &buffer);
    input = (UC *) luaL_optlstring(L, 2, NULL, &isize);
    if (input) {
        last = input + isize;
        while (input < last)
            asize = qpencode(*input++, atom, asize, marker, &buffer);
    } else qppad(atom, asize, &buffer);
    luaL_pushresult(&buffer);
    lua_pushlstring(L, (char *) atom, asize);
    return 2;
}

/*-------------------------------------------------------------------------*\
* Accumulate characters until we are sure about how to deal with them.
* Once we are sure, output the to the buffer, in the correct form. 
\*-------------------------------------------------------------------------*/
static size_t qpdecode(UC c, UC *input, size_t size, 
        luaL_Buffer *buffer)
{
    input[size++] = c;
    /* deal with all characters we can deal */
    while (size > 0) {
        int c, d;
        switch (input[0]) {
            /* if we have an escape character */
            case '=': 
                if (size < 3) return size; 
                /* eliminate soft line break */
                if (input[1] == CR && input[2] == LF) return 0;
                /* decode quoted representation */
                c = qpunbase[input[1]]; d = qpunbase[input[2]];
                /* if it is an invalid, do not decode */
                if (c > 15 || d > 15) luaL_addlstring(buffer, (char *)input, 3);
                else luaL_putchar(buffer, (c << 4) + d);
                return 0;
            case CR:
                if (size < 2) return size; 
                if (input[1] == LF) luaL_addlstring(buffer, (char *)input, 2);
                return 0;
            default:
                if (input[0] == HT || (input[0] > 31 && input[0] < 127))
                    luaL_putchar(buffer, input[0]);
                return 0;
        }
        input[0] = input[1]; input[1] = input[2];
        size--;
    }
    return 0;
}

/*-------------------------------------------------------------------------*\
* Incrementally decodes a string in quoted-printable
* A, B = qp(C, D)
* A is the decoded version of the largest prefix of C .. D that 
* can be decoded without doubts. 
* B has the remaining bytes of C .. D, *without* decoding.
\*-------------------------------------------------------------------------*/
static int mime_global_unqp(lua_State *L)
{

    size_t asize = 0, isize = 0;
    UC atom[3];
    const UC *input = (UC *) (lua_isnil(L, 1) ? NULL: 
            luaL_checklstring(L, 1, &isize));
    const UC *last = input + isize;
    luaL_Buffer buffer;
    luaL_buffinit(L, &buffer);
    while (input < last)
        asize = qpdecode(*input++, atom, asize, &buffer);
    input = (UC *) luaL_optlstring(L, 2, NULL, &isize);
    if (input) {
        last = input + isize;
        while (input < last)
            asize = qpdecode(*input++, atom, asize, &buffer);
    } 
    luaL_pushresult(&buffer);
    lua_pushlstring(L, (char *) atom, asize);
    return 2;
}

/*-------------------------------------------------------------------------*\
* Incrementally breaks a quoted-printed string into lines
* A, n = qpfmt(B, length, left)
* A is a copy of B, broken into lines of at most 'length' bytes. 
* Left is how many bytes are left in the first line of B. 'n' is the number 
* of bytes left in the last line of A. 
* There are two complications: lines can't be broken in the middle
* of an encoded =XX, and there might be line breaks already
\*-------------------------------------------------------------------------*/
static int mime_global_qpfmt(lua_State *L)
{
    size_t size = 0;
    const UC *input = (UC *) (lua_isnil(L, 1)? NULL: 
            luaL_checklstring(L, 1, &size));
    const UC *last = input + size;
    int length = (int) luaL_checknumber(L, 2);
    int left = (int) luaL_optnumber(L, 3, length);
    luaL_Buffer buffer;
    luaL_buffinit(L, &buffer);
    while (input < last) {
        left--;
        switch (*input) {
            case '=':
                /* if there's no room in this line for the quoted char, 
                 * output a soft line break now */
                if (left <= 3) {
                    luaL_addstring(&buffer, EQCRLF);
                    left = length;
                }
                break;
            /* \r\n starts a new line */
            case CR: 
                break;
            case LF:
                left = length;
                break;
            default:
                /* if in last column, output a soft line break */
                if (left <= 1) {
                    luaL_addstring(&buffer, EQCRLF);
                    left = length;
                }
        }
        luaL_putchar(&buffer, *input);
        input++;
    }
    if (!input && left < length) {
        luaL_addstring(&buffer, EQCRLF);
        left = length;
    }
    luaL_pushresult(&buffer);
    lua_pushnumber(L, left);
    return 2;
}

/*-------------------------------------------------------------------------*\
* Here is what we do: \n, \r and \f are considered candidates for line
* break. We issue *one* new line marker if any of them is seen alone, or
* followed by a different one. That is, \n\n, \r\r and \f\f will issue two
* end of line markers each, but \r\n, \n\r, \r\f etc will only issue *one*
* marker.  This covers Mac OS, Mac OS X, VMS, Unix and DOS, as well as
* probably other more obscure conventions.
\*-------------------------------------------------------------------------*/
#define eolcandidate(c) (c == CR || c == LF)
static size_t eolconvert(UC c, UC *input, size_t size, 
        const char *marker, luaL_Buffer *buffer)
{
    input[size++] = c;
    /* deal with all characters we can deal */
    if (eolcandidate(input[0])) {
        if (size < 2) return size; 
        luaL_addstring(buffer, marker);
        if (eolcandidate(input[1])) {
            if (input[0] == input[1]) luaL_addstring(buffer, marker);
        } else luaL_putchar(buffer, input[1]);
        return 0;
    } else {
        luaL_putchar(buffer, input[0]);
        return 0;
    }
}

/*-------------------------------------------------------------------------*\
* Converts a string to uniform EOL convention. 
* A, B = eol(C, D, marker)
* A is the converted version of the largest prefix of C .. D that 
* can be converted without doubts. 
* B has the remaining bytes of C .. D, *without* convertion.
\*-------------------------------------------------------------------------*/
static int mime_global_eol(lua_State *L)
{
    size_t asize = 0, isize = 0;
    UC atom[2];
    const UC *input = (UC *) (lua_isnil(L, 1)? NULL: 
            luaL_checklstring(L, 1, &isize));
    const UC *last = input + isize;
    const char *marker = luaL_optstring(L, 3, CRLF);
    luaL_Buffer buffer;
    luaL_buffinit(L, &buffer);
    while (input < last)
        asize = eolconvert(*input++, atom, asize, marker, &buffer);
    input = (UC *) luaL_optlstring(L, 2, NULL, &isize);
    if (input) {
        last = input + isize;
        while (input < last)
            asize = eolconvert(*input++, atom, asize, marker, &buffer);
    /* if there is something in atom, it's one character, and it
     * is a candidate. so we output a new line */
    } else if (asize > 0) luaL_addstring(&buffer, marker);
    luaL_pushresult(&buffer);
    lua_pushlstring(L, (char *) atom, asize);
    return 2;
}
