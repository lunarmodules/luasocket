host = host or "127.0.0.1"
port = port or 7
if arg then
    host = arg[1] or host
    port = arg[2] or port
end
print("Binding to host '" ..host.. "' and port " ..port.. "...")
udp, err = udpsocket()
if not udp then print(err) exit() end
err = udp:setsockname(host, port)
if err then print(err) exit() end
udp:timeout(5)
ip, port = udp:getsockname()
print("Waiting packets on " .. ip .. ":" .. port .. "...")
while 1 do
	dgram, ip, port = udp:receivefrom()
	if not dgram then print(ip) 
	else 
		print("Echoing from " .. ip .. ":" .. port)
		udp:sendto(dgram, ip, port)
	end
end
