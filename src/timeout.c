/*=========================================================================*\
* Timeout management functions
\*=========================================================================*/
#include <lua.h>
#include <lauxlib.h>

#include "lspriv.h"
#include "lstm.h"

#include <stdio.h>

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
#ifdef LUASOCKET_DEBUG
static int tm_lua_time(lua_State *L);
static int tm_lua_sleep(lua_State *L);
#endif

/*=========================================================================*\
* Exported functions.
\*=========================================================================*/
/*-------------------------------------------------------------------------*\
* Sets timeout limits
* Input
*   tm: timeout control structure
*   mode: block or return timeout
*   value: timeout value in miliseconds
\*-------------------------------------------------------------------------*/
void tm_set(p_tm tm, int tm_block, int tm_return)
{
    tm->tm_block = tm_block;
    tm->tm_return = tm_return;
}

/*-------------------------------------------------------------------------*\
* Returns timeout limits
* Input
*   tm: timeout control structure
*   mode: block or return timeout
*   value: timeout value in miliseconds
\*-------------------------------------------------------------------------*/
void tm_get(p_tm tm, int *tm_block, int *tm_return)
{
    if (tm_block) *tm_block = tm->tm_block;
    if (tm_return) *tm_return = tm->tm_return;
}

/*-------------------------------------------------------------------------*\
* Determines how much time we have left for the current io operation
* an IO write operation.
* Input
*   tm: timeout control structure
* Returns
*   the number of ms left or -1 if there is no time limit
\*-------------------------------------------------------------------------*/
int tm_getremaining(p_tm tm)
{
    /* no timeout */
    if (tm->tm_block < 0 && tm->tm_return < 0)
        return -1;
    /* there is no block timeout, we use the return timeout */
    else if (tm->tm_block < 0)
        return MAX(tm->tm_return - tm_gettime() + tm->tm_start, 0);
    /* there is no return timeout, we use the block timeout */
    else if (tm->tm_return < 0) 
        return tm->tm_block;
    /* both timeouts are specified */
    else return MIN(tm->tm_block, 
            MAX(tm->tm_return - tm_gettime() + tm->tm_start, 0));
}

/*-------------------------------------------------------------------------*\
* Marks the operation start time in sock structure
* Input
*   tm: timeout control structure
\*-------------------------------------------------------------------------*/
void tm_markstart(p_tm tm)
{
    tm->tm_start = tm_gettime();
    tm->tm_end = tm->tm_start;
}

/*-------------------------------------------------------------------------*\
* Returns the length of the operation in ms
* Input
*   tm: timeout control structure
\*-------------------------------------------------------------------------*/
int tm_getelapsed(p_tm tm)
{
    return tm->tm_end - tm->tm_start;
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
    (void) L;
#ifdef LUASOCKET_DEBUG
    lua_pushcfunction(L, tm_lua_time);
    priv_newglobal(L, "_time");
    lua_pushcfunction(L, tm_lua_sleep);
    priv_newglobal(L, "_sleep");
#endif
}

/*=========================================================================*\
* Test support functions
\*=========================================================================*/
/*-------------------------------------------------------------------------*\
* Returns the time the system has been up, in secconds.
\*-------------------------------------------------------------------------*/
#ifdef LUASOCKET_DEBUG
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
#endif
