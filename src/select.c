/*-------------------------------------------------------------------------*\
* Marks type as selectable
* Input
*   name: type name
\*-------------------------------------------------------------------------*/
void slct_addclass(lua_State *L, cchar *lsclass)
{
    lua_pushstring(L, "selectable sockets");
    lua_gettable(L, LUA_REGISTRYINDEX);
    lua_pushstring(L, lsclass);
    lua_pushnumber(L, 1);
    lua_settable(L, -3);
    lua_pop(L, 2);
}

/*-------------------------------------------------------------------------*\
* Gets a pointer to a socket structure from a userdata
* Input
*   pos: userdata stack index
* Returns
*   pointer to structure, or NULL if invalid type
\*-------------------------------------------------------------------------*/
static p_sock ls_toselectable(lua_State *L)
{
    lua_getregistry(L);
    lua_pushstring(L, "sock(selectable)");
    lua_gettable(L, -2);
    lua_pushstring(L, lua_type(L, -3));
    lua_gettable(L, -2);
    if (lua_isnil(L, -1)) {
        lua_pop(L, 3);
        return NULL;
    } else {
        lua_pop(L, 3);
        return (p_sock) lua_touserdata(L, -1);
    }
}

/*-------------------------------------------------------------------------*\
* Waits for a set of sockets until a condition is met or timeout.
* Lua Input: {input}, {output} [, timeout]
*   {input}: table of sockets to be tested for input
*   {output}: table of sockets to be tested for output
*   timeout: maximum amount of time to wait for condition, in seconds
* Lua Returns: {input}, {output}, err
*   {input}: table with sockets ready for input
*   {output}: table with sockets ready for output
*   err: "timeout" or nil
\*-------------------------------------------------------------------------*/
int global_select(lua_State *L)
{
    int ms = lua_isnil(L, 3) ? -1 : (int) (luaL_opt_number(L, 3, -1) * 1000);
    fd_set rfds, *prfds = NULL, wfds, *pwfds = NULL;
    struct timeval tv, *ptv = NULL;
    unsigned max = 0;
    int byfds, readable, writable;
    int toread = 1, towrite = 2;
    lua_newtable(L); byfds = lua_gettop(L); /* sockets indexed by descriptor */
    lua_newtable(L); readable = lua_gettop(L);
    lua_newtable(L); writable = lua_gettop(L);
    /* collect sockets to be tested into FD_SET structures and fill byfds */
    if (lua_istable(L, toread)) 
        prfds = tab2rfds(L, toread, &rfds, &max, byfds, readable, &ms);
    else if (!lua_isnil(L, toread)) 
        luaL_argerror(L, toread, "expected table or nil");
    if (lua_istable(L, towrite)) 
        pwfds = tab2wfds(L, towrite, &wfds, &max, byfds);
    else if (!lua_isnil(L, towrite)) 
        luaL_argerror(L, towrite, "expected table or nil");
    /* fill timeval structure */
    if (ms >= 0) {
        tv.tv_sec = ms / 1000;
        tv.tv_usec = (ms % 1000) * 1000;
        ptv = &tv; 
    } else ptv = NULL; /* ptv == NULL when we don't have timeout */
    /* see if we can read, write or if we timedout */
    if (select(max+1, prfds, pwfds, NULL, ptv) <= 0 && ms >= 0) { 
        ls_pusherror(L, LS_TIMEOUT);
        return 3;
    }
    /* collect readable and writable sockets into result tables */
    fds2tab(L, prfds, max+1, byfds, readable);
    fds2tab(L, pwfds, max+1, byfds, writable);
    lua_pushnil(L);
    return 3;
}

/*=========================================================================*\
* Select auxiliar functions
\*=========================================================================*/
/*-------------------------------------------------------------------------*\
* Converts a FD_SET structure into a socket table set
* Input
*   fds: pointer to FD_SET structure
*   max: 1 plus the largest descriptor value in FD_SET
*   byfds: table indexed by descriptor number, with corresponding socket tables
*   can: table to receive corresponding socket table set
\*-------------------------------------------------------------------------*/
static void fds2tab(lua_State *L, fd_set *fds, int max, int byfds, int can)
{
    int s;
    if (!fds) return;
    for (s = 0; s < max; s++) {
        if (FD_ISSET(s, fds)) {
            lua_pushnumber(L, lua_getn(L, can) + 1);
            lua_pushnumber(L, s);
            lua_gettable(L, byfds);
            lua_settable(L, can);
        }
    }
}

/*-------------------------------------------------------------------------*\
* Converts a socket table set ito a FD_SET structure
* Input
*   towrite: socket table set
* Output
*   wfds: pointer to FD_SET structure to be filled
*   max: largest descriptor value found in wfds
*   byfds: table indexed by descriptor number, with corresponding socket tables
\*-------------------------------------------------------------------------*/
static fd_set *tab2wfds(lua_State *L, int towrite, fd_set *wfds, 
        int *max, int byfds)
{
    int empty = 1;
    FD_ZERO(wfds); 
    lua_pushnil(L);
    while (lua_next(L, towrite)) {
        p_sock sock = ls_toselectable(L);
        if (sock) { /* skip strange fields */
            NET_FD s = sock->fd;
            if (s != NET_INVALIDFD) { /* skip closed sockets */
                lua_pushnumber(L, s);
                lua_pushvalue(L, -2);
                lua_settable(L, byfds);
                if (s > *max) *max = s;
                FD_SET(s, wfds);
                empty = 0;
            }
        }
        /* get rid of value and expose index */
        lua_pop(L, 1);
    }
    if (empty) return NULL;
    else return wfds;
}

/*-------------------------------------------------------------------------*\
* Converts a socket table set ito a FD_SET structure
* Input
*   toread: socket table set
* Output
*   rfds: pointer to FD_SET structure to be filled
*   max: largest descriptor value found in rfds
*   byfds: table indexed by descriptor number, with corresponding socket tables
*   readable: table to receive socket table if socket is obviously readable
*   ms: will be zeroed if a readable socket is detected
\*-------------------------------------------------------------------------*/
static fd_set *tab2rfds(lua_State *L, int toread, fd_set *rfds, 
        int *max, int byfds, int readable, int *ms)
{
    int empty = 1;
    FD_ZERO(rfds); 
    lua_pushnil(L);
    while (lua_next(L, toread)) {
        p_sock sock = ls_toselectable(L);
        if (sock) { /* skip strange fields */
            NET_FD s = sock->fd;
            if (s != NET_INVALID) { /* skip closed sockets */
                /* a socket can have unread  data in our internal buffer. we
                pass them  straight to  the readable set,  and test  only to
                find out  which of the  other sockets  can be written  to or
                read from immediately. */
                if (sock->vt->readable(sock)) {
                    *ms = 0;
                    lua_pushnumber(L, lua_getn(L, readable) + 1);
                    lua_pushvalue(L, -2);
                    lua_settable(L, readable);
                } else {
                    lua_pushnumber(L, s);
                    lua_pushvalue(L, -2);
                    lua_settable(L, byfds);
                    if (s > *max) *max = s;
                    FD_SET(s, rfds);
                    empty = 0;
                }
            }
        }
        /* get rid of value and exposed index */
        lua_pop(L, 1);
    }
    if (empty) return NULL;
    else return rfds;
}
