#ifndef SELECT_H
#define SELECT_H
/*=========================================================================*\
* Select implementation
* LuaSocket toolkit
*
* To make the code as simple as possible, the select function is
* implemented int Lua, with a few helper functions written in C.
*
* Each object that can be passed to the select function has to be in the
* group select{able} and export two methods: fd() and dirty(). Fd returns
* the descriptor to be passed to the select function. Dirty() should return
* true if there is data ready for reading (required for buffered input).
*
* RCS ID: $Id$
\*=========================================================================*/

int select_open(lua_State *L);

#endif /* SELECT_H */
