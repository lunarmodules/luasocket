-- load our favourite library
local socket = require"socket"
-- timeout before an inactive thread is kicked
local TIMEOUT = 10
-- local address to bind to
local ihost, iport = arg[1] or "localhost", arg[2] or 8080
-- address to forward all data to
local ohost, oport = arg[3] or "localhost", arg[4] or 3128

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

local receiving = newset()
local sending = newset() 
local context = {}

-- starts a non-blocking connect
function nconnect(host, port)
    local peer, err = socket.tcp()
    if not peer then return nil, err end
    peer:settimeout(0)
    local ret, err = peer:connect(host, port)
    if ret then return peer end
    if err ~= "timeout" then 
        peer:close()
        return nil, err 
    end
    return peer
end

-- gets rid of a client
function kick(who)
if who == server then error("FUDEU") end
    if context[who] then
        sending:remove(who)
        receiving:remove(who)
        context[who] = nil
        who:close()
    end
end

-- decides what to do with a thread based on coroutine return
function route(who, status, what)
print(who, status, what)
    if status and what then
        if what == "receiving" then receiving:insert(who) end
        if what == "sending" then sending:insert(who) end
    else kick(who) end
end

-- loops accepting connections and creating new threads to deal with them
function accept(server)
    while true do
print(server, "accepting a new client")
        -- accept a new connection and start a new coroutine to deal with it
        local client = server:accept()
        if client then
            -- start a new connection, non-blockingly, to the forwarding address
            local peer = nconnect(ohost, oport)
            if peer then
                context[client] = {
                    last = socket.gettime(),
                    thread = coroutine.create(forward),
                    peer = peer,
                }
                -- make sure peer will be tested for writing in the next select
                -- round, which means the connection attempt has finished
                sending:insert(peer)
                context[peer] = {
                    peer = client,
                    thread = coroutine.create(check),
                    last = socket.gettime()
                }
                -- put both in non-blocking mode
                client:settimeout(0)
                peer:settimeout(0)
            else 
                -- otherwise just dump the client
                client:close() 
            end
        end
        -- tell scheduler we are done for now
        coroutine.yield("receiving")
    end
end

-- forwards all data arriving to the appropriate peer
function forward(who)
    while true do
print(who, "getting data")
        -- try to read as much as possible
        local data, rec_err, partial = who:receive("*a")
        -- if we had an error other than timeout, abort
        if rec_err and rec_err ~= "timeout" then return error(rec_err) end
        -- if we got a timeout, we probably have partial results to send
        data = data or partial
print(who, " got ", string.len(data))
        -- renew our timestamp so scheduler sees we are active
        context[who].last = socket.gettime()
        -- forward what we got right away
        local peer = context[who].peer
        while true do
            -- tell scheduler we need to wait until we can send something
            coroutine.yield("sending")
            local ret, snd_err
            local start = 0
print(who, "sending data")
            ret, snd_err, start = peer:send(data, start+1)
            if ret then break 
            elseif snd_err ~= "timeout" then return error(snd_err) end
            -- renew our timestamp so scheduler sees we are active
            context[who].last = socket.gettime()
        end
        -- if we are done receiving, we are done with this side of the
        -- connection
        if not rec_err then return nil end
        -- otherwise tell schedule we have to wait for more data to arrive
        coroutine.yield("receiving")
    end
end

-- checks if a connection completed successfully and if it did, starts
-- forwarding all data
function check(who)
    local ret, err = who:connected()
    if ret then 
print(who, "connection completed")
        receiving:insert(context[who].peer)
        context[who].last = socket.gettime()
print(who, "yielding until there is input data")
        coroutine.yield("receiving")
        return forward(who)
    else return error(err) end
end

-- initializes the forward server
function init()
    -- socket sets to test for events 
    -- create our server socket
    server = assert(socket.bind(ihost, iport))
    server:settimeout(0.1) -- we don't want to be killed by bad luck
    -- we initially
    receiving:insert(server)
    context[server] = { thread = coroutine.create(accept) }
end

-- loop waiting until something happens, restarting the thread to deal with
-- what happened, and routing it to wait until something else happens
function go()
    while true  do
print("will select for readability")
for i,v in ipairs(receiving) do
    print(i, v)
end
print("will select for writability")
for i,v in ipairs(sending) do
    print(i, v)
end
        -- check which sockets are interesting and act on them
        readable, writable = socket.select(receiving, sending, 3)
print("returned as readable")
for i,v in ipairs(readable) do
    print(i, v)
end
print("returned as writable")
for i,v in ipairs(writable) do
    print(i, v)
end
        -- for all readable connections, resume its thread and route it 
        for _, who in ipairs(readable) do
            receiving:remove(who)
            if context[who] then
                route(who, coroutine.resume(context[who].thread, who))
            end
        end
        -- for all writable connections, do the same
        for _, who in ipairs(writable) do
            sending:remove(who)
            if context[who] then
                route(who, coroutine.resume(context[who].thread, who))
            end
        end
        -- put all inactive threads in death row
        local now = socket.gettime()
        local deathrow
        for who, data in pairs(context) do
            if data.last then
print("hung for" , now - data.last, who)
                if  now - data.last > TIMEOUT then
                    -- only create table if someone is doomed
                    deathrow = deathrow or {} 
                    deathrow[who] = true
                end
            end
        end
        -- finally kick everyone in deathrow
        if deathrow then
print("in death row")
for i,v in pairs(deathrow) do
    print(i, v)
end
            for who in pairs(deathrow) do kick(who) end
        end
    end
end

go(init())
