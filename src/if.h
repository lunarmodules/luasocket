/*
 * $Id: if.h $
 *
 * Author: Markus Stenberg <fingon@iki.fi>
 *
 *  Copyright (c) 2012 cisco Systems, Inc.
 *
 * Created:       Tue Dec  4 14:37:24 2012 mstenber
 * Last modified: Tue Dec  4 14:51:43 2012 mstenber
 * Edit time:     7 min
 *
 */

/* This module provides Lua wrapping for the advanced socket API
 * defined in RFC3542, or mainly, the access to the system's interface
 * list. It is necessary for use of recvmsg/sendmsg.
 *
 * TODO - Do something clever with Windows?
 */
#ifndef IF_H
#define IF_H

#include "lua.h"

int if_open(lua_State *L);

#endif /* IF_H */
