-- load our favourite library
local socket = require"socket"

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

-- timeout before an inactive thread is kicked
local TIMEOUT = 10
-- set of connections waiting to receive data
local receiving = newset()
-- set of sockets waiting to send data
local sending = newset() 
-- context for connections and servers
local context = {}

function wait(who, what)
    if what == "input" then receiving:insert(who)
    else sending:insert(who) end
    context[who].last = socket.gettime()
    coroutine.yield()
end

-- initializes the forward server
function init()
    if table.getn(arg) < 1 then
        print("Usage")
        print("    lua forward.lua <iport:ohost:oport> ...")
        os.exit(1)
    end
    -- for each tunnel, start a new server socket
    for i, v in ipairs(arg) do
        -- capture forwarding parameters
        local iport, ohost, oport = 
            socket.skip(2, string.find(v, "([^:]+):([^:]+):([^:]+)"))
        assert(iport, "invalid arguments")
        -- create our server socket
        local server = assert(socket.bind("*", iport))
        server:settimeout(0) -- we don't want to be killed by bad luck
        -- make sure server is tested for readability
        receiving:insert(server)
        -- add server context
        context[server] = { 
            thread = coroutine.create(accept),
            ohost = ohost,
            oport = oport
        }
    end
end

-- starts a connection in a non-blocking way
function connect(who, host, port)
    who:settimeout(0)
print("trying to connect peer", who, host, port)
    local ret, err = who:connect(host, port)
    if not ret and err == "timeout" then
print("got timeout, will wait", who)
        wait(who, "output") 
        ret, err = who:connected()
print("connection results arrived", who, ret, err)
    end
    if not ret then 
print("connection failed", who)
        kick(who)
        kick(context[who].peer)
    else
        return forward(who)
    end
end

-- gets rid of a client
function kick(who)
    if who and context[who] then
        sending:remove(who)
        receiving:remove(who)
        context[who] = nil
        who:close()
    end
end

-- loops accepting connections and creating new threads to deal with them
function accept(server)
    while true do
        -- accept a new connection and start a new coroutine to deal with it
        local client = server:accept()
print("accepted ", client)
        if client then
            -- create contexts for client and peer. 
            local peer, err = socket.tcp() 
            if peer then
                context[client] = {
                    last = socket.gettime(),
                    -- client goes straight to forwarding loop
                    thread = coroutine.create(forward),
                    peer = peer,
                }
                context[peer] = {
                    last = socket.gettime(),
                    peer = client,
                    -- peer first tries to connect to forwarding address
                    thread = coroutine.create(connect),
                    last = socket.gettime()
                }
                -- resume peer and client so they can do their thing
                local ohost = context[server].ohost
                local oport = context[server].oport
                coroutine.resume(context[peer].thread, peer, ohost, oport)
                coroutine.resume(context[client].thread, client)
            else 
                print(err)
                client:close()
            end
        end
        -- tell scheduler we are done for now
        wait(server, "input") 
    end
end

-- forwards all data arriving to the appropriate peer
function forward(who)
print("starting to foward", who)
    who:settimeout(0)
    while true do
        -- wait until we have something to read
        wait(who, "input")
        -- try to read as much as possible
        local data, rec_err, partial = who:receive("*a")
        -- if we had an error other than timeout, abort
        if rec_err and rec_err ~= "timeout" then return kick(who) end
        -- if we got a timeout, we probably have partial results to send
        data = data or partial
        -- forward what we got right away
        local peer = context[who].peer
        while true do
            -- tell scheduler we need to wait until we can send something
            wait(who, "output") 
            local ret, snd_err
            local start = 0
            ret, snd_err, start = peer:send(data, start+1)
            if ret then break 
            elseif snd_err ~= "timeout" then return kick(who) end
        end
        -- if we are done receiving, we are done
        if not rec_err then 
            kick(who) 
            kick(peer)
        end
    end
end

-- loop waiting until something happens, restarting the thread to deal with
-- what happened, and routing it to wait until something else happens
function go()
    while true  do
print("will select for reading")
for i,v in ipairs(receiving) do
    print(i, v)
end
print("will select for sending")
for i,v in ipairs(sending) do
    print(i, v)
end
        -- check which sockets are interesting and act on them
        readable, writable = socket.select(receiving, sending, 3)
print("was readable")
for i,v in ipairs(readable) do
    print(i, v)
end
print("was writable")
for i,v in ipairs(writable) do
    print(i, v)
end
        -- for all readable connections, resume its thread 
        for _, who in ipairs(readable) do
            receiving:remove(who)
            coroutine.resume(context[who].thread, who)
        end
        -- for all writable connections, do the same
        for _, who in ipairs(writable) do
            sending:remove(who)
            coroutine.resume(context[who].thread, who)
        end
        -- put all inactive threads in death row
        local now = socket.gettime()
        local deathrow
        for who, data in pairs(context) do
            if data.peer then
                if  now - data.last > TIMEOUT then
                    -- only create table if at least one is doomed
                    deathrow = deathrow or {} 
                    deathrow[who] = true
                end
            end
        end
        -- finally kick everyone in deathrow
        if deathrow then
            for who in pairs(deathrow) do kick(who) end
        end
    end
end

init()
go()
