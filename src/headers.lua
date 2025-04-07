-----------------------------------------------------------------------------
-- Canonic header field capitalization
-- LuaSocket toolkit.
-- Author: Diego Nehab
-----------------------------------------------------------------------------
local socket = require("socket")
socket.headers = {}
local _M = socket.headers

local parts = {
  ch="CH",
  dns="DNS",
  ect="ECT",
  etag="ETag",
  gpc="GPC",
  id="ID",
  md5="MD5",
  mime="MIME",
  mta="MTA",
  nel="NEL",
  rtt="RTT",
  smtp="SMTP",
  sourcemap="SourceMap",
  te="TE",
  ua="UA",
  websocket="WebSocket",
  wow64="WoW64",
  www="WWW",
  xss="XSS",
}

_M.canonic = setmetatable({},{
  __index=function (t,k)
    t[k] = string.gsub(k, "%f[%w]%l", function (part)
      return parts[part] or string.upper(part)
    end)
    return t[k]
  end;
})

_M.parts = parts

return _M
