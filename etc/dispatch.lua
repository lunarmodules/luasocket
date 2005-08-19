-----------------------------------------------------------------------------
-- A hacked dispatcher module
-- LuaSocket sample files
-- Author: Diego Nehab
-- RCS ID: $$
-----------------------------------------------------------------------------
local base = _G
local socket = require("socket")
local coroutine = require("coroutine")
module("dispatch")

-- if too much time goes by without any activity in one of our sockets, we
-- just kill it
TIMEOUT = 10

-----------------------------------------------------------------------------
-- Mega hack. Don't try to do this at home.
-----------------------------------------------------------------------------
-- Lua 5.1 has coroutine.running(). We need it here, so we use this terrible
-- hack to emulate it in Lua itself
-- This is very inefficient, but is very good for debugging.
local running
local resume = coroutine.resume
function coroutine.resume(co, ...)
    running = co
    return resume(co, unpack(arg))
end

function coroutine.running()
    return running
end

-----------------------------------------------------------------------------
-- Mega hack. Don't try to do this at home.
-----------------------------------------------------------------------------
-- we can't yield across calls to protect, so we rewrite it with coxpcall
-- make sure you don't require any module that uses socket.protect before
-- loading our hack
function socket.protect(f)
    return f
end

function socket.protect(f)
  return function(...)
    local co = coroutine.create(f)
    while true do
      local results = {resume(co, unpack(arg))}
      local status = table.remove(results, 1)
      if not status then
        if type(results[1]) == 'table' then
          return nil, results[1][1]
        else error(results[1]) end 
      end
      if coroutine.status(co) == "suspended" then
        arg = {coroutine.yield(unpack(results))}
      else
        return unpack(results)
      end
    end
  end
end

-----------------------------------------------------------------------------
-- socket.tcp() replacement for non-blocking I/O
-----------------------------------------------------------------------------
local function newtrap(dispatcher)
    -- try to create underlying socket
    local tcp, error = socket.tcp()
    if not tcp then return nil, error end
    -- put it in non-blocking mode right away
    tcp:settimeout(0)
    -- metatable for trap produces new methods on demand for those that we
    -- don't override explicitly.
    local metat = { __index = function(table, key) 
        table[key] = function(...)
            return tcp[key](tcp, unpack(arg))
        end
    end}
    -- does user want to do his own non-blocking I/O?
    local zero = false
    -- create a trap object that will behave just like a real socket object
    local trap = {  } 
    -- we ignore settimeout to preserve our 0 timeout, but record whether
    -- the user wants to do his own non-blocking I/O
    function trap:settimeout(mode, value)
        if value == 0 then
            zero = true
        else
            zero = false
        end
        return 1
    end
    -- send in non-blocking mode and yield on timeout
    function trap:send(data, first, last) 
        first = (first or 1) - 1
        local result, error
        while true do
            -- tell dispatcher we want to keep sending before we yield 
            dispatcher.sending:insert(tcp)                   
            -- mark time we started waiting
            dispatcher.context[tcp].last = socket.gettime()
            -- return control to dispatcher
            -- if upon return the dispatcher tells us we timed out,
            -- return an error to whoever called us
            if coroutine.yield() == "timeout" then 
                return nil, "timeout" 
            end
            -- try sending
            result, error, first = tcp:send(data, first+1, last)
            -- if we are done, or there was an unexpected error, 
            -- break away from loop
            if error ~= "timeout" then return result, error, first end
        end
    end
    -- receive in non-blocking mode and yield on timeout
    -- or simply return partial read, if user requested timeout = 0
    function trap:receive(pattern, partial)
        local error = "timeout"
        local value
        while true do 
            -- tell dispatcher we want to keep receiving before we yield
            dispatcher.receiving:insert(tcp)
            -- mark time we started waiting
            dispatcher.context[tcp].last = socket.gettime()
            -- return control to dispatcher
            -- if upon return the dispatcher tells us we timed out,
            -- return an error to whoever called us
            if coroutine.yield() == "timeout" then 
                return nil, "timeout" 
            end
            -- try receiving
            value, error, partial = tcp:receive(pattern, partial)
            -- if we are done, or there was an unexpected error, 
            -- break away from loop
            if (error ~= "timeout") or zero then 
                return value, error, partial 
            end
        end
    end
    -- connect in non-blocking mode and yield on timeout
    function trap:connect(host, port)
        local result, error = tcp:connect(host, port)
        -- mark time we started waiting
        dispatcher.context[tcp].last = socket.gettime()
        if error == "timeout" then
            -- tell dispatcher we will be able to write uppon connection
            dispatcher.sending:insert(tcp)
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
    end
    -- accept in non-blocking mode and yield on timeout
    function trap:accept()
        local result, error = tcp:accept()
        while error == "timeout" do
            -- mark time we started waiting
            dispatcher.context[tcp].last = socket.gettime()
            -- tell dispatcher we will be able to read uppon connection
            dispatcher.receiving:insert(tcp)
            -- return control to dispatcher
            -- if upon return the dispatcher tells us we have a
            -- timeout, just abort
            if coroutine.yield() == "timeout" then 
                return nil, "timeout" 
            end
        end 
        return result, error
    end
    -- remove thread from context
    function trap:close()
        dispatcher.context[tcp] = nil
        return tcp:close()
    end
    -- add newly created socket to context
    dispatcher.context[tcp] = {
        thread = coroutine.running()
    }
    return setmetatable(trap, metat)
end

-----------------------------------------------------------------------------
-- Our set data structure
-----------------------------------------------------------------------------
local function newset()
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

-----------------------------------------------------------------------------
-- Our dispatcher API. 
-----------------------------------------------------------------------------
local metat = { __index = {} }

function metat.__index:start(func) 
    local co = coroutine.create(func)
    assert(coroutine.resume(co))
end

function newhandler()
    local dispatcher = { 
        context = {},
        sending = newset(),
        receiving = newset()
    }
    function dispatcher.tcp()
        return newtrap(dispatcher)
    end
    return setmetatable(dispatcher, metat)
end

-- step through all active threads
function metat.__index:step()
    -- check which sockets are interesting and act on them
    local readable, writable = socket.select(self.receiving, 
        self.sending, 1)
    -- for all readable connections, resume their threads
    for _, who in ipairs(readable) do
        if self.context[who] then
            self.receiving:remove(who)
            assert(coroutine.resume(self.context[who].thread))
        end
    end
    -- for all writable connections, do the same
    for _, who in ipairs(writable) do
        if self.context[who] then
            self.sending:remove(who)
            assert(coroutine.resume(self.context[who].thread))
        end
    end
    -- politely ask replacement I/O functions in idle threads to 
    -- return reporting a timeout
    local now = socket.gettime()
    for who, data in pairs(self.context) do
        if  data.last and now - data.last > TIMEOUT then
            self.sending:remove(who)
            self.receiving:remove(who)
            assert(coroutine.resume(self.context[who].thread, "timeout"))
        end
    end
end
