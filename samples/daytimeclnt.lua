host = host or "127.0.0.1"
port = port or 13
if arg then
    host = arg[1] or host
    port = arg[2] or port
end
host = socket.toip(host)
udp = socket.udp()
print("Using host '" ..host.. "' and port " ..port.. "...")
udp:setpeername(host, port)
sent, err = udp:send("anything")
if err then print(err) exit() end
dgram, err = udp:receive()
if not dgram then print(err) exit() end
io.write(dgram)
