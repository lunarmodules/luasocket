/*=========================================================================*\
* UDP class: inherits from Socked and Internet domain classes and provides
* all the functionality for UDP objects.
*
* RCS ID: $Id$
\*=========================================================================*/
#ifndef UDP_H_ 
#define UDP_H_

#include "lsinet.h"

#define UDP_CLASS "luasocket(UDP socket)"

#define UDP_DATAGRAMSIZE 576

#define UDP_FIELDS \
    INET_FIELDS; \
    int udp_connected

typedef struct t_udp_tag {
    UDP_FIELDS; 
} t_udp;
typedef t_udp *p_udp;

void udp_inherit(lua_State *L, cchar *lsclass);
void udp_construct(lua_State *L, p_udp udp);
void udp_open(lua_State *L);
p_udp udp_push(lua_State *L);

#endif
