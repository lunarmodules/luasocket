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

-- creates a function that chooses an algorithm from a given table 
local function choose(table)
    return function(method, ...)
        local f = table[method or "nil"]
        if not f then error("unknown method (" .. tostring(method) .. ")", 3)
        else return f(unpack(arg)) end
    end
end

-- creates a function that cicles a filter with a given initial
-- context and extra arguments
local function cicle(f, ctx, ...)
    return function(chunk)
        local ret
        ret, ctx = f(ctx, chunk, unpack(arg))
        return ret
    end
end

-- function that choose the encoding, decoding or wrap algorithm
encode = choose(et) 
decode = choose(dt)

-- the wrap filter has default parameters
local cwt = choose(wt)
function wrap(...)
    if not arg[1] or type(arg[1]) ~= "string" then 
        table.insert(arg, 1, "base64")
    end
    return cwt(unpack(arg))
end

-- define the encoding algorithms
et['base64'] = function()
    return cicle(b64, "")
end

et['quoted-printable'] = function(mode)
    return cicle(qp, "", (mode == "binary") and "=0D=0A" or "\13\10")
end

-- define the decoding algorithms
dt['base64'] = function()
    return cicle(unb64, "")
end

dt['quoted-printable'] = function()
    return cicle(unqp, "")
end

-- define the wrap algorithms
wt['base64'] = function(length, marker)
    length = length or 76
    return cicle(wrp, length, length, marker) 
end

wt['quoted-printable'] = function(length)
    length = length or 76
    return cicle(qpwrp, length, length) 
end

-- define the end-of-line translation function
function canonic(marker)
    return cicle(eol, "", marker)
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

return code
