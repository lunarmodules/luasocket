-- make sure LuaSocket is loaded
if not LUASOCKET_LIBNAME then error('module requires LuaSocket') end
-- get LuaSocket namespace
local socket = _G[LUASOCKET_LIBNAME] 
if not socket then error('module requires LuaSocket') end
-- create code namespace inside LuaSocket namespace
local mime = socket.mime or {}
socket.mime = mime
-- make all module globals fall into mime namespace
setmetatable(mime, { __index = _G })
setfenv(1, mime)

-- encode, decode and wrap algorithm tables
local et = {}
local dt = {}
local wt = {}

-- creates a function that chooses a filter from a given table 
local function choose(table)
    return function(filter, ...)
        local f = table[filter or "nil"]
        if not f then error("unknown filter (" .. tostring(filter) .. ")", 3)
        else return f(unpack(arg)) end
    end
end

-- define the encoding filters
et['base64'] = function()
    return socket.cicle(b64, "")
end

et['quoted-printable'] = function(mode)
    return socket.cicle(qp, "", (mode == "binary") and "=0D=0A" or "\13\10")
end

-- define the decoding filters
dt['base64'] = function()
    return socket.cicle(unb64, "")
end

dt['quoted-printable'] = function()
    return socket.cicle(unqp, "")
end

-- define the line-wrap filters
wt['text'] = function(length)
    length = length or 76
    return socket.cicle(wrp, length, length) 
end
wt['base64'] = wt['text']

wt['quoted-printable'] = function()
    return socket.cicle(qpwrp, 76, 76) 
end

-- function that choose the encoding, decoding or wrap algorithm
encode = choose(et) 
decode = choose(dt)
-- there is a default wrap filter
local cwt = choose(wt)
function wrap(...)
    if type(arg[1]) ~= "string" then table.insert(arg, 1, "text") end
    return cwt(unpack(arg))
end

-- define the end-of-line translation filter
function canonic(marker)
    return socket.cicle(eol, "", marker)
end

-- chains several filters together
function chain(...)
    local layers = table.getn(arg)
    return function (chunk)
        if not chunk then
            local parts = {}
            for i = 1, layers do
                for j = i, layers do
                    chunk = arg[j](chunk)
                end
                table.insert(parts, chunk)
                chunk = nil
            end
            return table.concat(parts)
        else
            for j = 1, layers do
                chunk = arg[j](chunk)
            end
            return chunk
        end
    end
end

return mime
