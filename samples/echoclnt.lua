host = host or "localhost"
port = port or 7
if arg then
    host = arg[1] or host
    port = arg[2] or port
end
host = toip(host)
udp, err = udpsocket()
if not udp then print(err) exit() end
err = setpeername(udp, host, port)
if err then print(err) exit() end
print("Using host '" ..host.. "' and port " ..port.. "...")
while 1 do
	line = read()
	if not line then exit() end
	err = send(udp, line)
	if err then print(err) exit() end
	dgram, err = receive(udp)
	if not dgram then print(err) exit() end
	print(dgram)
end
