-- create module namespace 
ltn12 = ltn12 or {}
-- make all globals fall into ltn12 namespace
setmetatable(ltn12, { __index = _G })
setfenv(1, ltn12)

-- sub namespaces
filter = {}
source = {}
sink = {}

-- 2048 seems to be better in windows...
BLOCKSIZE = 2048

local function second(a, b)
    return b
end

local function shift(a, b, c)
    return b, c
end

-- returns a high level filter that cycles a cycles a low-level filter
function filter.cycle(low, ctx, extra)
    if type(low) ~= 'function' then error('invalid low-level filter', 2) end 
    return function(chunk)
        local ret
        ret, ctx = low(ctx, chunk, extra)
        return ret
    end
end

-- chains two filters together
local function chain2(f1, f2)
    if type(f1) ~= 'function' then error('invalid filter', 2) end 
    if type(f2) ~= 'function' then error('invalid filter', 2) end 
    local co = coroutine.create(function(chunk)
        while true do
            local filtered1 = f1(chunk)
            local filtered2 = f2(filtered1)
            local done2 = filtered1 and ""
            while true do
                if filtered2 == "" or filtered2 == nil then break end
                coroutine.yield(filtered2)
                filtered2 = f2(done2)
            end
            if filtered1 == "" then chunk = coroutine.yield(filtered1)
            elseif filtered1 == nil then return nil
            else chunk = chunk and "" end
        end
    end)
    return function(chunk)
        return shift(coroutine.resume(co, chunk))
    end
end

-- chains a bunch of filters together
function filter.chain(...)
    local f = arg[1]
    for i = 2, table.getn(arg) do
        if type(arg[i]) ~= 'function' then error('invalid filter', 2) end 
        f = chain2(f, arg[i])
    end
    return f
end

-- create an empty source
local function empty()
    return nil
end

function source.empty()
    return empty
end

-- returns a source that just outputs an error
function source.error(err)
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
    else return source.error(io_err or "unable to open file") end
end

-- turns a fancy source into a simple source
function source.simplify(src)
    if type(src) ~= 'function' then error('invalid source', 2) end 
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
    else return source.empty() end
end

-- creates rewindable source
function source.rewind(src)
    if type(src) ~= 'function' then error('invalid source', 2) end 
    local t = {}
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
    if type(src) ~= 'function' then error('invalid source', 2) end
    if type(f) ~= 'function' then error('invalid filter', 2) end
    local co = coroutine.create(function()
        while true do 
            local chunk, err = src()
            if err then return nil, err end
            local filtered = f(chunk)
            local done = chunk and ""
            while true do
                coroutine.yield(filtered)
                if filtered == done then break end
                filtered = f(done)
            end
        end
    end)
    return function()
        return shift(coroutine.resume(co))
    end
end

-- creates a source that produces contents of several files one after the
-- other, as if they were concatenated
function source.cat(...)
    local co = coroutine.create(function()
        local i = 1
        while i <= table.getn(arg) do 
            local chunk = arg[i]:read(2048)
            if chunk then coroutine.yield(chunk)
            else i = i + 1 end
        end
    end)
    return source.simplify(function()
        return shift(coroutine.resume(co))
    end)
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
    if type(snk) ~= 'function' then error('invalid sink', 2) end
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
                return 1
            else return handle:write(chunk) end
        end
    else return sink.error(io_err or "unable to open file") end
end

-- creates a sink that discards data
local function null()
    return 1
end

function sink.null()
    return null
end

-- creates a sink that just returns an error
function sink.error(err)
    return function()
        return nil, err
    end
end

-- chains a sink with a filter 
function sink.chain(f, snk)
    if type(snk) ~= 'function' then error('invalid sink', 2) end
    if type(f) ~= 'function' then error('invalid filter', 2) end
    return function(chunk, err)
        local filtered = f(chunk)
        local done = chunk and ""
        while true do
            local ret, snkerr = snk(filtered, err)
            if not ret then return nil, snkerr end
            if filtered == done then return 1 end
            filtered = f(done)
        end
    end
end

-- pumps all data from a source to a sink
function pump(src, snk)
    if type(src) ~= 'function' then error('invalid source', 2) end
    if type(snk) ~= 'function' then error('invalid sink', 2) end
    while true do
        local chunk, src_err = src()
        local ret, snk_err = snk(chunk, src_err)
        if not chunk or not ret then
            return not src_err and not snk_err, src_err or snk_err
        end
    end
end
