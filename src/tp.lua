-----------------------------------------------------------------------------
-- Unified SMTP/FTP subsystem
-- LuaSocket toolkit.
-- Author: Diego Nehab
-- RCS ID: $Id$
-----------------------------------------------------------------------------

-----------------------------------------------------------------------------
-- Load required modules
-----------------------------------------------------------------------------
local socket = require("socket")
local ltn12 = require("ltn12")

-----------------------------------------------------------------------------
-- Program constants
-----------------------------------------------------------------------------
TIMEOUT = 60

-----------------------------------------------------------------------------
-- Implementation
-----------------------------------------------------------------------------
-- gets server reply (works for SMTP and FTP)
local function get_reply(c)
    local code, current, sep
    local line, err = c:receive()
    local reply = line
    if err then return nil, err end
    code, sep = socket.skip(2, string.find(line, "^(%d%d%d)(.?)"))
    if not code then return nil, "invalid server reply" end
    if sep == "-" then -- reply is multiline
        repeat
            line, err = c:receive()
            if err then return nil, err end
            current, sep = socket.skip(2, string.find(line, "^(%d%d%d)(.?)"))
            reply = reply .. "\n" .. line
        -- reply ends with same code
        until code == current and sep == " " 
    end
    return code, reply
end

-- metatable for sock object
local metat = { __index = {} }

function metat.__index:check(ok)
    local code, reply = get_reply(self.c)
    if not code then return nil, reply end
    if type(ok) ~= "function" then
        if type(ok) == "table" then 
            for i, v in ipairs(ok) do
                if string.find(code, v) then return tonumber(code), reply end
            end
            return nil, reply
        else
            if string.find(code, ok) then return tonumber(code), reply 
            else return nil, reply end
        end
    else return ok(tonumber(code), reply) end
end

function metat.__index:command(cmd, arg)
    if arg then return self.c:send(cmd .. " " .. arg.. "\r\n")
    else return self.c:send(cmd .. "\r\n") end
end

function metat.__index:sink(snk, pat)
    local chunk, err = c:receive(pat)
    return snk(chunk, err)
end

function metat.__index:send(data)
    return self.c:send(data)
end

function metat.__index:receive(pat)
    return self.c:receive(pat)
end

function metat.__index:getfd()
    return self.c:getfd()
end

function metat.__index:dirty()
    return self.c:dirty()
end

function metat.__index:getcontrol()
    return self.c
end

function metat.__index:source(source, step)
    local sink = socket.sink("keep-open", self.c)
    return ltn12.pump.all(source, sink, step or ltn12.pump.step)
end

-- closes the underlying c
function metat.__index:close()
    self.c:close()
	return 1
end

-- connect with server and return c object
function connect(host, port, timeout)
    local c, e = socket.tcp()
    if not c then return nil, e end
    c:settimeout(timeout or TIMEOUT)
    local r, e = c:connect(host, port)
    if not r then 
        c:close() 
        return nil, e
    end
    return setmetatable({c = c}, metat)
end
