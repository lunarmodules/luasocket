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

-- tries to get a pattern from the server and closes socket on error
local function try_receiving(sock, pattern)
    local data, message = sock:receive(pattern)
    if not data then sock:close() end
    return data, message
end

-- tries to send data to server and closes socket on error
local function try_sending(sock, data)
    local sent, message = sock:send(data)
    if not sent then sock:close() end
    return sent, message
end

-- gets server reply
local function get_reply(sock)
    local code, current, separator, _
    local line, message = try_receiving(sock)
    local reply = line
    if message then return nil, message end
    _, _, code, separator = string.find(line, "^(%d%d%d)(.?)")
    if not code then return nil, "invalid server reply" end
    if separator == "-" then -- reply is multiline
        repeat
            line, message = try_receiving(sock)
            if message then return nil, message end
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

-- execute the "check" instr
function metatable.__index:check(ok)
    local code, reply = get_reply(self.sock)
    if not code then return nil, reply end
    if type(ok) ~= "function" then
        if type(ok) ~= "table" then ok = {ok} end
        for i, v in ipairs(ok) do
            if string.find(code, v) then return code, reply end
        end
        return nil, reply
    else return ok(code, reply) end
end

function metatable.__index:cmdchk(cmd, arg, ok)
    local code, err = self:command(cmd, arg)
    if not code then return nil, err end
    return self:check(ok)
end

-- execute the "command" instr
function metatable.__index:command(cmd, arg)
    if arg then return try_sending(self.sock, cmd .. " " .. arg.. "\r\n")
    return try_sending(self.sock, cmd .. "\r\n") end
end

function metatable.__index:sink(snk, pat)
    local chunk, err = sock:receive(pat)
    return snk(chunk, err)
end

function metatable.__index:source(src, instr)
    while true do
        local chunk, err = src()
        if not chunk then return not err, err end
        local ret, err = try_sending(self.sock, chunk)
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
    if not sock then return nil, message end
    sock:settimeout(TIMEOUT)
    return setmetatable({sock = sock}, metatable)
end
