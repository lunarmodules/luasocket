host = host or "127.0.0.1"
port = port or 13
if arg then
    host = arg[1] or host
    port = arg[2] or port
end
host = toip(host)
udp = udpsocket()
print("Using host '" ..host.. "' and port " ..port.. "...")
err = udp:sendto("anything", host, port)
if err then print(err) exit() end
dgram, err = udp:receive()
if not dgram then print(err) exit() end
write(dgram)
