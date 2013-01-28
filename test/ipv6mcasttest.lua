#!/usr/bin/env lua
-- -*-lua-*-
--
-- $Id: ipv6mcasttest.lua $
--
-- Author: Markus Stenberg <mstenber@cisco.com>
--
-- Copyright (c) 2012 cisco Systems, Inc.
--
-- Created:       Wed Dec  5 09:55:46 2012 mstenber
-- Last modified: Mon Jan 28 16:20:14 2013 mstenber
-- Edit time:     54 min
--

-- exercise the new IPv6 related functionality:

-- join/leave IPv6 multicast group, send/receive IPv6 message using
-- sendmsg/recvmsg API

require 'socket'

local mcast = 'ff02::fb'

local port = 4242
local ifname = 'eth2'
--local ifname = 'lo' -- should not work - no multicast on lo in Linux?
local testdata = 'foobar'

function setup_socket(port)
   local s = socket.udp6()
   s:setoption('ipv6-v6only', true)
   if port
   then
      s:setoption('reuseaddr', true)
      --local r, err = s:setsockname('::1', port)
      local r, err = s:setsockname('*', port)
      assert(r, 'setsockname failed ' .. tostring(err))
      --print("getsockname", s:getsockname())
   end
   assert(tostring(s):find("udp{unconnected}"))
   return s
end

function setup_connected(host, port)
   local c = setup_socket()
   assert(host and port)
   local r, err = c:setpeername(host, port)
   assert(r, 'setpeername failed ' .. tostring(err))
   --print('got from setpeername', r, err)
   --print("getsockname", c:getsockname())
   assert(tostring(c):find("udp{connected}"), 'not connected', tostring(c))
   --print("getpeername", c:getpeername())
   return c
end

function my_setoption(s, k, v)
   local old = s:getoption(k)
   print('before set', k, old)
   local r, err = s:setoption(k, v)
   assert(r, 'setoption failed ' .. tostring(err))
   local new = s:getoption(k)
   print('after set', k, new)
   assert(v == new)
end

-- specific interface
--local ifindex = socket.iface.nametoindex(ifname)

-- all interfaces
local ifindex = nil

local s = setup_socket(port)

local mct = {multiaddr=mcast, interface=ifindex}
local r, err = s:setoption('ipv6-drop-membership', mct)
-- don't check result - it may or may not fail
local r, err = s:setoption('ipv6-add-membership', mct)
assert(r, 'ipv6-add-membership failed', err)

--local c = setup_connected(mcast .. '%lo', port)
--c:send('foo')
local c = setup_socket()

-- this seems to be the default anyway?
my_setoption(c, 'ipv6-unicast-hops', 255)
my_setoption(c, 'ipv6-multicast-loop', true)
my_setoption(c, 'ipv6-multicast-hops', 255)
my_setoption(s, 'ipv6-multicast-hops', 255)

local r, err = c:sendto(testdata, mcast .. '%' .. ifname, port)
assert(r, 'sendto failed')

-- make sure sending both to mcast address, and link-local
-- address on the chosen interface works
local r, err = c:sendto(testdata, mcast .. '%' .. ifname, port)
assert(r, 'sendto failed (mcast)')

local data, host, port = s:receivefrom()
assert(data == testdata, 'weird data ' .. tostring(data))
print('recvfrom', host, port)

-- make sure we can send stuff back to link-local addr as well'
local r, err = s:sendto(testdata, host, port)
assert(r, 'sendto failed (ll)')

-- and it is received too
local data, host, port = c:receivefrom()
assert(data)
print('recvfrom', host, port)

-- now, finally, we can get rid of mcast group
local r, err = s:setoption('ipv6-drop-membership', mct)
assert(r, 'ipv6-drop-membership failed', err)
--local c = setup_connected(port)


