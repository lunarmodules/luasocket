-----------------------------------------------------------------------------
-- Canonic header field capitalization
-- LuaSocket toolkit.
-- Author: Diego Nehab
-----------------------------------------------------------------------------
local socket = require("socket")
socket.headers = {}
local _M = socket.headers

_M.canonic = setmetatable({},{
  __index=function (t,k)
    t[k] = string.gsub(k, "%f[%w]%l", string.upper)
    return t[k]
  end;
})

return _M
