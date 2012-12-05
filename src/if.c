/*
 * $Id: if.c $
 *
 * Author: Markus Stenberg <fingon@iki.fi>
 *
 *  Copyright (c) 2012 Markus Stenberg
 *       All rights reserved
 *
 * Created:       Tue Dec  4 14:50:34 2012 mstenber
 * Last modified: Wed Dec  5 18:48:55 2012 mstenber
 * Edit time:     23 min
 *
 */

#include <sys/types.h>
#include <sys/socket.h>
#include <net/if.h>

#include "if.h"

#include "lauxlib.h"

static int if_global_indextoname(lua_State *L);
static int if_global_nametoindex(lua_State *L);
static int if_global_nameindex(lua_State *L);

static luaL_Reg func[] = {
    { "indextoname", if_global_indextoname},
    { "nametoindex", if_global_nametoindex},
    { "nameindex", if_global_nameindex},
    { NULL, NULL}
};

int if_open(lua_State *L)
{
    lua_pushstring(L, "iface");
    lua_newtable(L);
    luaL_openlib(L, NULL, func, 0);
    lua_settable(L, -3);
    return 0;
}

int if_global_indextoname(lua_State *L)
{
  unsigned int ifnumber;
  const char *name;
  char buf[IF_NAMESIZE+1];

  if (!lua_isnumber(L, 1))
    {
      lua_pushnil(L);
      lua_pushstring(L, "indextoname expects only number argument");
      return 2;
    }
  ifnumber = lua_tonumber(L, 1);
  if (!(name = if_indextoname(ifnumber, buf)))
    {
      lua_pushnil(L);
      lua_pushstring(L, "nonexistent interface");
      return 2;
    }
  lua_pushstring(L, name);
  return 1;
}

int if_global_nametoindex(lua_State *L)
{
  unsigned int ifnumber;
  if (!lua_isstring(L, 1))
    {
      lua_pushnil(L);
      lua_pushstring(L, "nametoindex expects only string argument");
      return 2;
    }
  if (!(ifnumber = if_nametoindex(lua_tostring(L, 1))))
    {
      lua_pushnil(L);
      lua_pushstring(L, "nonexistent interface");
      return 2;
    }
  lua_pushnumber(L, ifnumber);
  return 1;
}

int if_global_nameindex(lua_State *L)
{
  struct if_nameindex *ni, *oni;
  int i = 1;
  oni = ni = if_nameindex();
  lua_newtable(L);
  while (ni && ni->if_index && *(ni->if_name))
    {
      /* at result[i], we store.. */
      lua_pushnumber(L, i);

      /* new table with two items - index, name*/
      lua_newtable(L);
      lua_pushstring(L, "index");
      lua_pushnumber(L, ni->if_index);
      lua_settable(L, -3);

      lua_pushstring(L, "name");
      lua_pushstring(L, ni->if_name);
      lua_settable(L, -3);

      /* Then, actually store it */
      lua_settable(L, -3);

      i++;
      ni++;
    }
  if_freenameindex(oni);
  return 1;
}
