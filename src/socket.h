#ifndef SOCK_H_
#define SOCK_H_ 

#include <lua.h>
#include "lsfd.h"

#define SOCK_CLASS "luasocket(sock)"

#define SOCK_FIELDS FD_FIELDS

typedef t_fd t_sock;
typedef t_sock *p_sock;

void sock_open(lua_State *L);
void sock_construct(lua_State *L, p_sock sock);
void sock_inherit(lua_State *L, cchar *lsclass);

#endif /* SOCK_H_ */
