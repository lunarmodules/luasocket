-----------------------------------------------------------------------------
-- Canonic header field capitalization
-- LuaSocket toolkit.
-- Author: Diego Nehab
-----------------------------------------------------------------------------
local socket = require("socket")
socket.headers = {}
local _M = socket.headers

-- capitalizes the first letter of each hyphen-separated word, lowercases
-- the rest (e.g. "x-request-id" -> "X-Request-Id")
local function titlecase(header)
    return (header:gsub("(%a)([%w]*)", function(a, b) return a:upper()..b:lower() end))
end

_M.canonic = {}

setmetatable(_M.canonic, {
    __index = function(t, key)
        if type(key) ~= "string" then
            return nil
        end

        local lower = key:lower()
        local v = rawget(t, lower)
        if v then
            return v
        end

        v = titlecase(lower)
        rawset(t, lower, v)
        return v
    end
})

-- adds a header with a given canonical capitalization, e.g. for headers
-- whose capitalization titlecase(header) would not reproduce correctly
function _M.setcanonic(header)
    if type(header) ~= "string" then
        error("header must be a string", 2)
    end
    _M.canonic[header:lower()] = header
end

-- headers whose canonical capitalization titlecase() does not reproduce
-- (acronyms and other irregular capitalization). Anything not listed here
-- is generated and cached on first lookup by the __index above.
_M.setcanonic("Content-ID")
_M.setcanonic("Content-MD5")
_M.setcanonic("DSN-Gateway")
_M.setcanonic("ETag")
_M.setcanonic("Final-Log-ID")
_M.setcanonic("Message-ID")
_M.setcanonic("MIME-Version")
_M.setcanonic("Original-Envelope-ID")
_M.setcanonic("Received-From-MTA")
_M.setcanonic("Remote-MTA")
_M.setcanonic("Reporting-MTA")
_M.setcanonic("Resent-Message-ID")
_M.setcanonic("SMTP-Remote-Recipient")
_M.setcanonic("TE")
_M.setcanonic("WWW-Authenticate")

return _M
