-- create code namespace inside LuaSocket namespace
ltn12 = ltn12 or {}
-- make all module globals fall into mime namespace
setmetatable(ltn12, { __index = _G })
setfenv(1, ltn12)

-- sub namespaces
filter = {}
source = {}
sink = {}

-- 2048 seems to be better in windows...
BLOCKSIZE = 2048

-- returns a high level filter that cycles a cycles a low-level filter
function filter.cycle(low, ctx, extra)
    return function(chunk)
        local ret
        ret, ctx = low(ctx, chunk, extra)
        return ret
    end
end

-- chains two filters together
local function chain2(f1, f2)
    return function(chunk)
        local ret = f2(f1(chunk))
        if chunk then return ret
        else return ret .. f2() end
    end
end

-- chains a bunch of filters together
function filter.chain(...)
    local f = arg[1]
    for i = 2, table.getn(arg) do
        f = chain2(f, arg[i])
    end
    return f
end

-- create an empty source
function source.empty(err)
    return function()
        return nil, err
    end
end

-- creates a file source
function source.file(handle, io_err)
    if handle then
        return function()
            local chunk = handle:read(BLOCKSIZE)
            if not chunk then handle:close() end
            return chunk
        end
    else source.empty(io_err or "unable to open file") end
end

-- turns a fancy source into a simple source
function source.simplify(src)
    return function()
        local chunk, err_or_new = src()
        src = err_or_new or src
        if not chunk then return nil, err_or_new
        else return chunk end
    end
end

-- creates string source
function source.string(s)
    if s then
        local i = 1
        return function()
            local chunk = string.sub(s, i, i+BLOCKSIZE-1)
            i = i + BLOCKSIZE
            if chunk ~= "" then return chunk
            else return nil end
        end
    else source.empty() end
end

-- creates rewindable source
function source.rewind(src)
    local t = {}
    src = source.simplify(src)
    return function(chunk)
        if not chunk then
            chunk = table.remove(t)
            if not chunk then return src()
            else return chunk end
        else
            table.insert(t, chunk)
        end
    end
end

-- chains a source with a filter
function source.chain(src, f)
    src = source.simplify(src)
    local chain = function()
        local chunk, err = src()
        if not chunk then return f(nil), source.empty(err)
        else return f(chunk) end
    end
    return source.simplify(chain)
end

-- creates a sink that stores into a table
function sink.table(t)
    t = t or {}
    local f = function(chunk, err)
        if chunk then table.insert(t, chunk) end
        return 1
    end
    return f, t
end

-- turns a fancy sink into a simple sink
function sink.simplify(snk)
    return function(chunk, err)
        local ret, err_or_new = snk(chunk, err)
        if not ret then return nil, err_or_new end
        snk = err_or_new or snk
        return 1
    end
end

-- creates a file sink
function sink.file(handle, io_err)
    if handle then
        return function(chunk, err)
            if not chunk then 
                handle:close()
                return nil, err
            end
            return handle:write(chunk)
        end
    else sink.null() end
end

-- creates a sink that discards data
local function null()
    return 1
end

function sink.null()
    return null
end

-- chains a sink with a filter 
function sink.chain(f, snk)
    snk = sink.simplify(snk)
    return function(chunk, err)
        local r, e = snk(f(chunk))
        if not r then return nil, e end
        if not chunk then return snk(nil, err) end
        return 1
    end
end

-- pumps all data from a source to a sink
function pump(src, snk)
    snk = sink.simplify(snk)
    for chunk, src_err in source.simplify(src) do
        local ret, snk_err = snk(chunk, src_err)
        if not chunk or not ret then 
            return not src_err and not snk_err, src_err or snk_err 
        end
    end
end
