-----------------------------------------------------------------------------
-- UDP sample: echo protocol client
-- LuaSocket 1.5 sample files
-- Author: Diego Nehab
-- RCS ID: $Id$
-----------------------------------------------------------------------------
host = host or "localhost"
port = port or 7
if arg then
    host = arg[1] or host
    port = arg[2] or port
end
host = socket.toip(host)
udp, err = socket.udp()
if not udp then print(err) exit() end
err = udp:setpeername(host, port)
if err then print(err) exit() end
print("Using host '" ..host.. "' and port " .. port .. "...")
while 1 do
	line = io.read()
	if not line then os.exit() end
	err = udp:send(line)
	if err then print(err) os.exit() end
	dgram, err = udp:receive()
	if not dgram then print(err) os.exit() end
	print(dgram)
end
