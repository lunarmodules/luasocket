-----------------------------------------------------------------------------
-- Select sample: simple text line server
-- LuaSocket 1.5 sample files.
-- Author: Diego Nehab
-- RCS ID: $Id$
-----------------------------------------------------------------------------
host = host or "*"
port1 = port1 or 8080
port2 = port2 or 8081
if arg then
    host = arg[1] or host
    port1 = arg[2] or port1
    port2 = arg[3] or port2
end

server1, error = socket.bind(host, port1)
assert(server1, error)
server1:timeout(1)
server2, error = socket.bind(host, port2)
assert(server2, error)
server2:timeout(1)

function newset()
    local reverse = {}
    local set = {}
    setmetatable(set, { __index = {
        insert = function(set, value) 
            table.insert(set, value)
            reverse[value] = table.getn(set)
        end,
        remove = function(set, value)
            table.remove(set, reverse[value])
            reverse[value] = nil
        end,
        id = function(set, value)
            return reverse[value]
        end
    }})
    return set
end

sockets = newset()

sockets:insert(server1)
sockets:insert(server2)

while 1 do
    local readable, _, error = socket.select(sockets, nil)
    for _, input in readable do
        -- is it a server socket?
        local id = sockets:id(input)
        if input == server1 or input == server2 then
            local new = input:accept()
            if new then 
                new:timeout(1)
                sockets:insert(new) 
                io.write("Server ", id, " got client ", sockets:id(new), "\n")
            end
        -- it is a client socket
        else
            local line, error = input:receive()
            if error then 
                input:close()
                io.write("Removing client ", id, "\n")
                sockets:remove(input) 
            else
            	io.write("Broadcasting line '", id, "> ", line, "'.\n")
            	__, writable, error = socket.select(nil, sockets, 1)
            	if not error then
                	for ___, output in writable do
                        io.write("Sending to client ", sockets:id(output), "\n")
                    	output:send(id, "> ", line, "\r\n")
                	end
            	else io.write("No one ready to listen!!!\n") end
			end
        end
    end
end
