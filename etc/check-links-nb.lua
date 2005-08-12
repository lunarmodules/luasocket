-----------------------------------------------------------------------------
-- Little program that checks links in HTML files, using coroutines and
-- non-blocking I/O. Thus, faster than simpler version of same program
-- LuaSocket sample files
-- Author: Diego Nehab
-- RCS ID: $$
-----------------------------------------------------------------------------
local socket = require("socket")

TIMEOUT = 10

-- we need to yield across calls to protect, so we can't use pcall
-- we borrow and simplify code from coxpcall to reimplement socket.protect
-- before loading http
function socket.protect(f)
    return function(...)
        local co = coroutine.create(f)
        while true do
            local results = {coroutine.resume(co, unpack(arg))}
            local status = results[1]
            table.remove(results, 1)
            if not status then
                return nil, results[1][1]
            end
            if coroutine.status(co) == "suspended" then
                arg = {coroutine.yield(unpack(results))}
            else
                return unpack(results)
            end
        end
    end
end

local http = require("socket.http")
local url = require("socket.url")

-- creates a new set data structure
function newset()
    local reverse = {}
    local set = {}
    return setmetatable(set, {__index = {
        insert = function(set, value)
            if not reverse[value] then
                table.insert(set, value)
                reverse[value] = table.getn(set)
            end
        end,
        remove = function(set, value)
            local index = reverse[value]
            if index then
                reverse[value] = nil
                local top = table.remove(set)
                if top ~= value then 
                    reverse[top] = index
                    set[index] = top
                end 
            end
        end
    }}) 
end

local context = {}
local sending = newset()
local receiving = newset()
local nthreads = 0

-- socket.tcp() replacement for non-blocking I/O
-- implements enough functionality to be used with http.request
-- in Lua 5.1, we have coroutine.running to simplify things... 
function newcreate(thread)
    return function()
        -- try to create underlying socket
        local tcp, error = socket.tcp()
        if not tcp then return nil, error end
        -- put it in non-blocking mode right away
        tcp:settimeout(0)
        local trap = { 
            -- we ignore settimeout to preserve our 0 timeout
            settimeout = function(self, mode, value)
                return 1
            end,
            -- send in non-blocking mode and yield on timeout
            send = function(self, data, first, last) 
                first = (first or 1) - 1
                local result, error
                while true do
                    -- tell dispatcher we want to keep sending before we
                    -- yield control
                    sending:insert(tcp)                   
                    -- return control to dispatcher
                    -- if upon return the dispatcher tells us we timed out,
                    -- return an error to whoever called us
                    if coroutine.yield() == "timeout" then 
                        return nil, "timeout" 
                    end
                    -- mark time we started waiting
                    context[tcp].last = socket.gettime()
                    -- try sending
                    result, error, first = tcp:send(data, first+1, last)
                    -- if we are done, or there was an unexpected error, 
                    -- break away from loop
                    if error ~= "timeout" then return result, error, first end
                end
            end,
            -- receive in non-blocking mode and yield on timeout
            receive = function(self, pattern)
                local error, partial = "timeout", ""
                local value
                while true do 
                    -- tell dispatcher we want to keep receiving before we
                    -- yield control
                    receiving:insert(tcp)
                    -- return control to dispatcher
                    -- if upon return the dispatcher tells us we timed out,
                    -- return an error to whoever called us
                    if coroutine.yield() == "timeout" then 
                        return nil, "timeout" 
                    end
                    -- mark time we started waiting
                    context[tcp].last = socket.gettime()
                    -- try receiving
                    value, error, partial = tcp:receive(pattern, partial)
                    -- if we are done, or there was an unexpected error, 
                    -- break away from loop
                    if error ~= "timeout" then return value, error, partial end
                end
            end,
            -- connect in non-blocking mode and yield on timeout
            connect = function(self, host, port)
                local result, error = tcp:connect(host, port)
                -- mark time we started waiting
                context[tcp].last = socket.gettime()
                if error == "timeout" then
                    -- tell dispatcher we will be able to write uppon connection
                    sending:insert(tcp)
                    -- return control to dispatcher
                    -- if upon return the dispatcher tells us we have a
                    -- timeout, just abort
                    if coroutine.yield() == "timeout" then 
                        return nil, "timeout" 
                    end
                    -- when we come back, check if connection was successful
                    result, error = tcp:connect(host, port)
                    if result or error == "already connected" then return 1
                    else return nil, "non-blocking connect failed" end
                else return result, error end
            end,
            close = function(self)
                context[tcp] = nil
                return tcp:close()
            end
        }
        -- add newly created socket to context
        context[tcp] = {
            thread = thread,
            trap = trap
        }
        return trap
    end
end

-- get the status of a URL, non-blocking
function getstatus(link)
    local parsed = url.parse(link, {scheme = "file"})
    if parsed.scheme == "http" then
        local thread = coroutine.create(function(thread, link)
            local r, c, h, s = http.request{
                method = "HEAD",
                url = link, 
                create = newcreate(thread)
            }
            if c == 200 then io.write('\t', link, '\n')
            else io.write('\t', link, ': ', c, '\n') end
            nthreads = nthreads - 1
        end)
        nthreads = nthreads + 1
        assert(coroutine.resume(thread, thread, link))
    end
end

-- dispatch all threads until we are done
function dispatch()
    while nthreads > 0 do
        -- check which sockets are interesting and act on them
        local readable, writable = socket.select(receiving, sending, 1)
        -- for all readable connections, resume their threads
        for _, who in ipairs(readable) do
            if context[who] then
                receiving:remove(who)
                assert(coroutine.resume(context[who].thread))
            end
        end
        -- for all writable connections, do the same
        for _, who in ipairs(writable) do
            if context[who] then
                sending:remove(who)
                assert(coroutine.resume(context[who].thread))
            end
        end
        -- politely ask replacement I/O functions in idle threads to 
        -- return reporting a timeout
        local now = socket.gettime()
        for who, data in pairs(context) do
            if  data.last and now - data.last > TIMEOUT then
                sending:remove(who)
                receiving:remove(who)
                assert(coroutine.resume(context[who].thread, "timeout"))
            end
        end
    end
end

function readfile(path)
    path = url.unescape(path)
    local file, error = io.open(path, "r")
    if file then
        local body = file:read("*a")
        file:close()
        return body
    else return nil, error end
end

function load(u)
    local parsed = url.parse(u, { scheme = "file" })
    local body, headers, code, error
    local base = u
    if parsed.scheme == "http" then
        body, code, headers = http.request(u)
        if code == 200 then
            -- if there was a redirect, update base to reflect it
            base = headers.location or base
        end
        if not body then
            error = code
        end
    elseif parsed.scheme == "file" then
        body, error = readfile(parsed.path)
    else error = string.format("unhandled scheme '%s'", parsed.scheme) end
    return base, body, error
end

function getlinks(body, base)
    -- get rid of comments
    body = string.gsub(body, "%<%!%-%-.-%-%-%>", "")
    local links = {}
    -- extract links
    body = string.gsub(body, '[Hh][Rr][Ee][Ff]%s*=%s*"([^"]*)"', function(href)
        table.insert(links, url.absolute(base, href))
    end)
    body = string.gsub(body, "[Hh][Rr][Ee][Ff]%s*=%s*'([^']*)'", function(href)
        table.insert(links, url.absolute(base, href))
    end)
    string.gsub(body, "[Hh][Rr][Ee][Ff]%s*=%s*(.-)>", function(href)
        table.insert(links, url.absolute(base, href))
    end)
    return links
end

function checklinks(address)
    local base, body, error = load(address)
    if not body then print(error) return end
    print("Checking ", base)
    local links = getlinks(body, base)
    for _, link in ipairs(links) do
        getstatus(link)
    end
end

arg = arg or {}
if table.getn(arg) < 1 then
    print("Usage:\n  luasocket check-links.lua {<url>}")
    exit()
end
for _, address in ipairs(arg) do
    checklinks(url.absolute("file:", address))
end
dispatch()
