#!/usr/bin/env lua
-- -*-lua-*-
--
-- $Id: ifacetest.lua $
--
-- Author: Markus Stenberg <fingon@iki.fi>
--
-- Copyright (c) 2012 cisco Systems, Inc.
--
-- Created:       Wed Dec  5 09:42:12 2012 mstenber
-- Last modified: Wed Dec  5 09:51:17 2012 mstenber
-- Edit time:     3 min
--

local socket = require 'socket'
local iface = socket.iface

local a = iface.nameindex()
assert(#a > 0)
local o = a[1]
assert(o.index)
assert(o.name)
assert(iface.nametoindex(o.name))
assert(not iface.nametoindex('gargle'))
assert(iface.indextoname(o.index))
assert(not iface.indextoname(-123))

