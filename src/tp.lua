-----------------------------------------------------------------------------
-- Unified SMTP/FTP subsystem
-- LuaSocket toolkit.
-- Author: Diego Nehab
-- Conforming to: RFC 2616, LTN7
-- RCS ID: $Id$
-----------------------------------------------------------------------------
-- make sure LuaSocket is loaded
if not LUASOCKET_LIBNAME then error('module requires LuaSocket') end
-- get LuaSocket namespace
local socket = _G[LUASOCKET_LIBNAME] 
if not socket then error('module requires LuaSocket') end
-- create namespace inside LuaSocket namespace
socket.tp  = socket.tp or {}
-- make all module globals fall into namespace
setmetatable(socket.tp, { __index = _G })
setfenv(1, socket.tp)

TIMEOUT = 60

-- gets server reply
local function get_reply(sock)
    local code, current, separator, _
    local line, err = sock:receive()
    local reply = line
    if err then return nil, err end
    _, _, code, separator = string.find(line, "^(%d%d%d)(.?)")
    if not code then return nil, "invalid server reply" end
    if separator == "-" then -- reply is multiline
        repeat
            line, err = sock:receive()
            if err then return nil, err end
            _,_, current, separator = string.find(line, "^(%d%d%d)(.)")
            if not current or not separator then 
                return nil, "invalid server reply" 
            end
            reply = reply .. "\n" .. line
        -- reply ends with same code
        until code == current and separator == " " 
    end
    return code, reply
end

-- metatable for sock object
local metatable = { __index = {} }

function metatable.__index:check(ok)
    local code, reply = get_reply(self.sock)
    if not code then return nil, reply end
    if type(ok) ~= "function" then
        if type(ok) == "table" then 
            for i, v in ipairs(ok) do
                if string.find(code, v) then return code, reply end
            end
            return nil, reply
        else
            if string.find(code, ok) then return code, reply 
            else return nil, reply end
        end
    else return ok(code, reply) end
end

function metatable.__index:command(cmd, arg)
    if arg then return self.sock:send(cmd .. " " .. arg.. "\r\n")
    else return self.sock:send(cmd .. "\r\n") end
end

function metatable.__index:sink(snk, pat)
    local chunk, err = sock:receive(pat)
    return snk(chunk, err)
end

function metatable.__index:send(data)
    return self.sock:send(data)
end

function metatable.__index:receive(pat)
    return self.sock:receive(pat)
end

function metatable.__index:source(src, instr)
    while true do
        local chunk, err = src()
        if not chunk then return not err, err end
        local ret, err = self.sock:send(chunk)
        if not ret then return nil, err end
    end
end

-- closes the underlying sock
function metatable.__index:close()
    self.sock:close()
end

-- connect with server and return sock object
function connect(host, port)
    local sock, err = socket.connect(host, port)
    if not sock then return nil, err end
    sock:settimeout(TIMEOUT)
    return setmetatable({sock = sock}, metatable)
end
