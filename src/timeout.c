/*=========================================================================*\
* Timeout management functions
* LuaSocket toolkit
*
* RCS ID: $Id$
\*=========================================================================*/
#include <stdio.h>

#include <lua.h>
#include <lauxlib.h>

#include "luasocket.h"
#include "auxiliar.h"
#include "timeout.h"

#ifdef WIN32
#include <windows.h>
#else
#include <sys/times.h>
#include <time.h>
#include <unistd.h>
#endif

/*=========================================================================*\
* Internal function prototypes
\*=========================================================================*/
static int tm_lua_time(lua_State *L);
static int tm_lua_sleep(lua_State *L);

static luaL_reg func[] = {
    { "time", tm_lua_time },
    { "sleep", tm_lua_sleep },
    { NULL, NULL }
};

/*=========================================================================*\
* Exported functions.
\*=========================================================================*/
/*-------------------------------------------------------------------------*\
* Initialize structure
\*-------------------------------------------------------------------------*/
void tm_init(p_tm tm, int block, int total)
{
    tm->block = block;
    tm->total = total;
}

/*-------------------------------------------------------------------------*\
* Set and get timeout limits
\*-------------------------------------------------------------------------*/
void tm_setblock(p_tm tm, int block)
{ tm->block = block; }
void tm_settotal(p_tm tm, int total)
{ tm->total = total; }
int tm_getblock(p_tm tm)
{ return tm->block; }
int tm_gettotal(p_tm tm)
{ return tm->total; }
int tm_getstart(p_tm tm)
{ return tm->start; }

/*-------------------------------------------------------------------------*\
* Determines how much time we have left for the current operation
* Input
*   tm: timeout control structure
* Returns
*   the number of ms left or -1 if there is no time limit
\*-------------------------------------------------------------------------*/
int tm_get(p_tm tm)
{
    /* no timeout */
    if (tm->block < 0 && tm->total < 0)
        return -1;
    /* there is no block timeout, we use the return timeout */
    else if (tm->block < 0)
        return MAX(tm->total - tm_gettime() + tm->start, 0);
    /* there is no return timeout, we use the block timeout */
    else if (tm->total < 0) 
        return tm->block;
    /* both timeouts are specified */
    else return MIN(tm->block, 
            MAX(tm->total - tm_gettime() + tm->start, 0));
}

/*-------------------------------------------------------------------------*\
* Marks the operation start time in structure 
* Input
*   tm: timeout control structure
\*-------------------------------------------------------------------------*/
void tm_markstart(p_tm tm)
{
    tm->start = tm_gettime();
}

/*-------------------------------------------------------------------------*\
* Gets time in ms, relative to system startup.
* Returns
*   time in ms.
\*-------------------------------------------------------------------------*/
#ifdef WIN32
int tm_gettime(void) 
{
    return GetTickCount();
}
#else
int tm_gettime(void) 
{
    struct tms t;
    return (times(&t)*1000)/CLK_TCK;
}
#endif

/*-------------------------------------------------------------------------*\
* Initializes module
\*-------------------------------------------------------------------------*/
void tm_open(lua_State *L)
{
    luaL_openlib(L, LUASOCKET_LIBNAME, func, 0);
    lua_pop(L, 1);
}

/*-------------------------------------------------------------------------*\
* Sets timeout values for IO operations
* Lua Input: base, time [, mode]
*   time: time out value in seconds
*   mode: "b" for block timeout, "t" for total timeout. (default: b)
\*-------------------------------------------------------------------------*/
int tm_meth_timeout(lua_State *L, p_tm tm)
{
    int ms = lua_isnil(L, 2) ? -1 : (int) (luaL_checknumber(L, 2)*1000.0);
    const char *mode = luaL_optstring(L, 3, "b");
    switch (*mode) {
        case 'b':
            tm_setblock(tm, ms);
            break;
        case 'r': case 't':
            tm_settotal(tm, ms);
            break;
        default:
            luaL_argcheck(L, 0, 3, "invalid timeout mode");
            break;
    }
    return 0;
}

/*=========================================================================*\
* Test support functions
\*=========================================================================*/
/*-------------------------------------------------------------------------*\
* Returns the time the system has been up, in secconds.
\*-------------------------------------------------------------------------*/
static int tm_lua_time(lua_State *L)
{
    lua_pushnumber(L, tm_gettime()/1000.0);
    return 1;
}

/*-------------------------------------------------------------------------*\
* Sleep for n seconds.
\*-------------------------------------------------------------------------*/
int tm_lua_sleep(lua_State *L)
{
    double n = luaL_checknumber(L, 1);
#ifdef WIN32
    Sleep((int)n*1000);
#else
    sleep((int)n);
#endif
    return 0;
}
