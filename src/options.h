#ifndef OPTIONS_H
#define OPTIONS_H

#include <lua.h>
#include "socket.h"

/* option registry */
typedef struct t_opt {
  const char *name;
  int (*func)(lua_State *L, p_sock ps);
} t_opt;
typedef t_opt *p_opt;

/* supported options */
int opt_dontroute(lua_State *L, p_sock ps);
int opt_broadcast(lua_State *L, p_sock ps);
int opt_reuseaddr(lua_State *L, p_sock ps);
int opt_tcp_nodelay(lua_State *L, p_sock ps);
int opt_keepalive(lua_State *L, p_sock ps);
int opt_linger(lua_State *L, p_sock ps);
int opt_reuseaddr(lua_State *L, p_sock ps);
int opt_ip_multicast_ttl(lua_State *L, p_sock ps);
int opt_ip_multicast_loop(lua_State *L, p_sock ps);
int opt_ip_add_membership(lua_State *L, p_sock ps);
int opt_ip_drop_membersip(lua_State *L, p_sock ps);

/* invokes the appropriate option handler */
int opt_meth_setoption(lua_State *L, p_opt opt, p_sock ps);

#endif
