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

server1 = bind(host, port1)
server1:timeout(1)
server1.is_server = 1
server2 = bind(host, port2)
server2:timeout(1)
server2.is_server = 1

set = {server1, server2}
number = 1

while 1 do
    local r, s, e, l, n
    r, _, e = select(set, nil)
    for i, v in r do
        if v.is_server then
            s = v:accept()
            if s then 
                s:timeout(1)
				s.number = number
				number = number + 1
                set_add(set, s) 
                write("Added client number ", s.number, ". ", 
					getn(set)-2, " total.\n")
            end
        else
            l, e = v:receive()
			n = v.number
            if e then 
                v:close()
                set_remove(set, v) 
                write("Removed client number ", n, ". ",
					getn(set)-2, " total.\n")
            else
            	write("Broadcasting line '", tostring(n), "> ", 
					tostring(l), "'.\n")
            	_, s, e = select(nil, set, 1)
            	if not e then
                	for i,v in s do
                    	v:send(tostring(n), "> ", l, "\r\n")
                	end
            	else
                	write("No one ready to listen!!!\n")
            	end
			end
        end
    end
end
