#ifndef TM_H
#define TM_H
/*=========================================================================*\
* Timeout management functions
* LuaSocket toolkit
*
* RCS ID: $Id$
\*=========================================================================*/
#include <lua.h>

/* timeout control structure */
typedef struct t_tm_ {
    double total;          /* total number of miliseconds for operation */
    double block;          /* maximum time for blocking calls */
    double start;          /* time of start of operation */
} t_tm;
typedef t_tm *p_tm;

int tm_open(lua_State *L);
void tm_init(p_tm tm, double block, double total);
double tm_get(p_tm tm);
double tm_getretry(p_tm tm);
p_tm tm_markstart(p_tm tm);
double tm_getstart(p_tm tm);
double tm_gettime(void);
int tm_meth_settimeout(lua_State *L, p_tm tm);

#endif /* TM_H */
