-----------------------------------------------------------------------------
-- LuaSocket helper module
-- Author: Diego Nehab
-- RCS ID: $Id$
-----------------------------------------------------------------------------

-----------------------------------------------------------------------------
-- Load LuaSocket from dynamic library
-- Comment these lines if you are loading static
-----------------------------------------------------------------------------
open, err1, err2 = loadlib("luasocket", "luaopen_socket")
if not open then error(err1) end
open()
if not LUASOCKET_LIBNAME then error("LuaSocket init failed") end

-----------------------------------------------------------------------------
-- Namespace independence
-----------------------------------------------------------------------------
local socket = _G[LUASOCKET_LIBNAME]
if not socket then error('LuaSocket init failed') end

-----------------------------------------------------------------------------
-- Auxiliar functions
-----------------------------------------------------------------------------
function socket.connect(address, port, laddress, lport)
    local sock, err = socket.tcp()
    if not sock then return nil, err end
    if laddress then 
        local res, err = sock:bind(laddress, lport, -1)
        if not res then return nil, err end
    end
    local res, err = sock:connect(address, port)
    if not res then return nil, err end
    return sock
end

function socket.bind(host, port, backlog)
    local sock, err = socket.tcp()
    if not sock then return nil, err end
    sock:setoption("reuseaddr", true)
    local res, err = sock:bind(host, port)
    if not res then return nil, err end
    backlog = backlog or 1
    res, err = sock:listen(backlog)
    if not res then return nil, err end
    return sock
end

function socket.choose(table)
    return function(name, opt1, opt2)
        if type(name) ~= "string" then
            name, opt1, opt2 = "default", name, opt1
        end
        local f = table[name or "nil"]
        if not f then error("unknown key (" .. tostring(name) .. ")", 3)
        else return f(opt1, opt2) end
    end
end

-----------------------------------------------------------------------------
-- Socket sources and sinks, conforming to LTN12
-----------------------------------------------------------------------------
-- create namespaces inside LuaSocket namespace
socket.sourcet = {}
socket.sinkt = {}

socket.BLOCKSIZE = 2048

socket.sinkt["http-chunked"] = function(sock)
    return setmetatable({
        getfd = function() return sock:getfd() end,
        dirty = function() return sock:dirty() end
    }, { 
        __call = function(self, chunk, err)
            if not chunk then return sock:send("0\r\n\r\n") end
            local size = string.format("%X\r\n", string.len(chunk))
            return sock:send(size, chunk, "\r\n")
        end
    })
end

socket.sinkt["close-when-done"] = function(sock)
    return setmetatable({
        getfd = function() return sock:getfd() end,
        dirty = function() return sock:dirty() end
    }, { 
        __call = function(self, chunk, err)
            if not chunk then 
                sock:close()
                return 1
            else return sock:send(chunk) end
        end
    })
end

socket.sinkt["keep-open"] = function(sock)
    return setmetatable({
        getfd = function() return sock:getfd() end,
        dirty = function() return sock:dirty() end
    }, { 
        __call = function(self, chunk, err)
            return sock:send(chunk)
        end
    })
end

socket.sinkt["default"] = socket.sinkt["keep-open"]

socket.sink = socket.choose(socket.sinkt)

socket.sourcet["by-length"] = function(sock, length)
    return setmetatable({
        getfd = function() return sock:getfd() end,
        dirty = function() return sock:dirty() end
    }, { 
        __call = function()
            if length <= 0 then return nil end
            local size = math.min(socket.BLOCKSIZE, length)
            local chunk, err = sock:receive(size)
            if err then return nil, err end
            length = length - string.len(chunk)
            return chunk
        end
    })
end

socket.sourcet["until-closed"] = function(sock)
    return setmetatable({
        getfd = function() return sock:getfd() end,
        dirty = function() return sock:dirty() end
    }, { 
        __call = ltn12.source.simplify(function()
            local chunk, err, partial = sock:receive(socket.BLOCKSIZE)
            if not err then return chunk
            elseif err == "closed" then 
                sock:close()
                return partial, ltn12.source.empty()
            else return nil, err end 
        end)
    })
end

socket.sourcet["http-chunked"] = function(sock)
    return setmetatable({
        getfd = function() return sock:getfd() end,
        dirty = function() return sock:dirty() end
    }, { 
        __call = function()
            -- get chunk size, skip extention
            local line, err = sock:receive()
            if err then return nil, err end 
            local size = tonumber(string.gsub(line, ";.*", ""), 16)
            if not size then return nil, "invalid chunk size" end
            -- was it the last chunk?
            if size <= 0 then 
                -- skip trailer headers, if any
                local line, err = sock:receive()
                while not err and line ~= "" do
                    line, err = sock:receive()
                end
                return nil, err
            else
                -- get chunk and skip terminating CRLF
                local chunk, err = sock:receive(size)
                if err or socket.skip(2, sock:receive()) then return nil, err 
                else return chunk end
            end
        end
    })
end

socket.sourcet["default"] = socket.sourcet["until-closed"]

socket.source = socket.choose(socket.sourcet)
