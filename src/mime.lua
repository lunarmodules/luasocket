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

base64 = {}
qprint = {}

function base64.encode()
    local unfinished = ""
    return function(chunk)
        local done
        done, unfinished = b64(unfinished, chunk)
        return done
    end
end

function base64.decode()
    local unfinished = ""
    return function(chunk)
        local done
        done, unfinished = unb64(unfinished, chunk)
        return done
    end
end

function qprint.encode(mode)
    mode = (mode == "binary") and "=0D=0A" or "\13\10" 
    local unfinished = ""
    return function(chunk)
        local done
        done, unfinished = qp(unfinished, chunk, mode)
        return done
    end
end

function qprint.decode()
    local unfinished = ""
    return function(chunk)
        local done
        done, unfinished = unqp(unfinished, chunk)
        return done
    end
end

function split(length, marker)
    length = length or 76
    local left = length
    return function(chunk)
        local done
        done, left = fmt(chunk, length, left, marker)
        return done
    end
end

function qprint.split(length)
    length = length or 76
    local left = length
    return function(chunk)
        local done
        done, left = qpfmt(chunk, length, left)
        return done
    end
end

function canonic(marker)
    local unfinished = ""
    return function(chunk)
        local done
        done, unfinished = eol(unfinished, chunk, marker)
        return done
    end
end

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
