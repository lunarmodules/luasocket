host = host or "127.0.0.1"
port = port or 7
if arg then
    host = arg[1] or host
    port = arg[2] or port
end
print("Binding to host '" ..host.. "' and port " ..port.. "...")
udp, err = udpsocket()
if not udp then print(err) exit() end
err = setsockname(udp, host, port)
if err then print(err) exit() end
timeout(udp, 5)
ip, port = getsockname(udp)
print("Waiting packets on " .. ip .. ":" .. port .. "...")
while 1 do
	dgram, ip, port = receivefrom(udp)
	if not dgram then print(ip) 
	else 
		print("Echoing from " .. ip .. ":" .. port)
		sendto(udp, dgram, ip, port)
	end
end
