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
        server:settimeout(0.1) -- we don't want to be killed by bad luck
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
function nbkcon(host, port)
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
    if context[who] then
        sending:remove(who)
        receiving:remove(who)
        context[who] = nil
        who:close()
    end
end

-- decides what to do with a thread based on coroutine return
function route(who, status, what)
    if status and what then
        if what == "receiving" then receiving:insert(who) end
        if what == "sending" then sending:insert(who) end
    else kick(who) end
end

-- loops accepting connections and creating new threads to deal with them
function accept(server)
    while true do
        -- accept a new connection and start a new coroutine to deal with it
        local client = server:accept()
        if client then
            -- start a new connection, non-blockingly, to the forwarding address
            local ohost = context[server].ohost
            local oport = context[server].oport
            local peer = nbkcon(ohost, oport)
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
                    thread = coroutine.create(chkcon),
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
        -- try to read as much as possible
        local data, rec_err, partial = who:receive("*a")
        -- if we had an error other than timeout, abort
        if rec_err and rec_err ~= "timeout" then return error(rec_err) end
        -- if we got a timeout, we probably have partial results to send
        data = data or partial
        -- renew our timestamp so scheduler sees we are active
        context[who].last = socket.gettime()
        -- forward what we got right away
        local peer = context[who].peer
        while true do
            -- tell scheduler we need to wait until we can send something
            coroutine.yield("sending")
            local ret, snd_err
            local start = 0
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
function chkcon(who)
    local ret, err = who:connected()
    if ret then 
        receiving:insert(context[who].peer)
        context[who].last = socket.gettime()
        coroutine.yield("receiving")
        return forward(who)
    else return error(err) end
end

-- loop waiting until something happens, restarting the thread to deal with
-- what happened, and routing it to wait until something else happens
function go()
    while true  do
        -- check which sockets are interesting and act on them
        readable, writable = socket.select(receiving, sending, 3)
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
                if  now - data.last > TIMEOUT then
                    -- only create table if someone is doomed
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
