-----------------------------------------------------------------------------
-- UDP sample: echo protocol client
-- LuaSocket sample files
-- Author: Diego Nehab
-- RCS ID: $Id$
-----------------------------------------------------------------------------
host = host or "localhost"
port = port or 7
if arg then
    host = arg[1] or host
    port = arg[2] or port
end
host = socket.dns.toip(host)
udp, err = socket.udp()
assert(udp, err) 
ret, err = udp:setpeername(host, port)
assert(ret, err) 
print("Using host '" ..host.. "' and port " .. port .. "...")
while 1 do
	line = io.read()
	if not line then os.exit() end
	ret, err = udp:send(line)
	if not ret then print(err) os.exit() end
	dgram, err = udp:receive()
	if not dgram then print(err) os.exit() end
	print(dgram)
end
