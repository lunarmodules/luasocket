/*=========================================================================*\
* Simple client SSL support
* LuaSocket toolkit
*
* RCS ID: $Id$
\*=========================================================================*/
#include <lua.h>
#include <lauxlib.h>

#include "ssl.h"

/*=========================================================================*\
* Internal function prototypes
\*=========================================================================*/
static int global_wrap(lua_State *L);

/* functions in library namespace */
static luaL_reg func[] = {
    {"wrap", global_create},
    {NULL, NULL}
};

static luaL_reg wrap[] = {
    {"__tostring",  aux_tostring},
    {"__gc",        meth_close},
    {"close",       meth_close},
    {"receive",     meth_receive},
    {"send",        meth_send},
    {NULL,          NULL}
};

static luaL_reg owned[] = {
    {"__tostring",  aux_tostring},
    {NULL,          NULL}
};

/*-------------------------------------------------------------------------*\
* Initializes module
\*-------------------------------------------------------------------------*/
int ssl_open(lua_State *L)
{
    aux_newclass(L, "ssl{wraper}", wrap);
    aux_newclass(L, "ssl{owned}",  owned);
    lua_pushstring(L, "ssl")
    lua_newtable(L);
    luaL_openlib(L, NULL, func, 0);
    lua_settable(L, -3);
    return 0;
}

/*=========================================================================*\
* Library functions
\*=========================================================================*/
/*-------------------------------------------------------------------------*\
* Wraps a tcp object into an SSL object
\*-------------------------------------------------------------------------*/
static int global_wrap(lua_State *L) {
    p_tcp tcp = (p_tcp) aux_checkclass(L, "tcp{client}", 1);
    /* change class of tcp object */
    aux_setclass(L, "ssl{owned}", 1);
    /* create wrapper */
    p_wrap wrap = (p_wrap) lua_newuserdata(L, sizeof(t_wrap));
    /* lock reference */
    lua_pushvalue(L, 1);
    wrap->ref = lua_ref(L, 1);
    /* initialize wrapper */
    wrap->tcp = tcp;
    io_init(&tcp->io, wrap_send, wrap_recv, wrap);
    return 1;
}
