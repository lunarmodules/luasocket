function set_add(set, sock)
    tinsert(set, sock)
end

function set_remove(set, sock)
    for i = 1, getn(set) do
        if set[i] == sock then
           tremove(set, i)
           break
        end
    end 
end

host = host or "*"
port1 = port1 or 8080
port2 = port2 or 8081
if arg then
    host = arg[1] or host
    port1 = arg[2] or port1
    port2 = arg[3] or port2
end

server1, error = bind(host, port1)
if not server1 then print(error) exit() end
server1:timeout(1)
server2, error = bind(host, port2)
if not server2 then print(error) exit() end
server2:timeout(1)

sock_set = {server1, server2}

sock_id = {}
sock_id[server1] = 1
sock_id[server2] = 2
next_id = 3

while 1 do
    local readable, _, error = select(sock_set, nil)
    for _, sock in readable do
        -- is it a server socket
        if sock_id[sock] < 3 then
            local incomming = sock:accept()
            if incomming then 
                incomming:timeout(1)
				sock_id[incomming] = next_id
                set_add(sock_set, incomming) 
                write("Added client id ", next_id, ". ", 
					getn(sock_set)-2, " total.\n")
				next_id = next_id + 1
            end
        -- it is a client socket
        else
            local line, error = sock:receive()
			local id = sock_id[sock]
            if error then 
                sock:close()
                set_remove(sock_set, sock) 
                write("Removed client number ", id, ". ",
					getn(sock_set)-2, " total.\n")
            else
            	write("Broadcasting line '", id, "> ", line, "'.\n")
            	_, writable, error = select(nil, sock_set, 1)
            	if not error then
                	for _, outgoing in writable do
                        write("Sending to client ", sock_id[outgoing], "\n")
                    	outgoing:send(id, "> ", line, "\r\n")
                	end
            	else write("No one ready to listen!!!\n") end
			end
        end
    end
end
