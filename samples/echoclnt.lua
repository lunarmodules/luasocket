-----------------------------------------------------------------------------
-- UDP sample: echo protocol client
-- LuaSocket sample files
-- Author: Diego Nehab
-- RCS ID: $Id$
-----------------------------------------------------------------------------
require"luasocket"
host = host or "localhost"
port = port or 7
if arg then
    host = arg[1] or host
    port = arg[2] or port
end
host = socket.dns.toip(host)
udp = socket.try(socket.udp())
socket.try(udp:setpeername(host, port))
print("Using remote host '" ..host.. "' and port " .. port .. "...")
while 1 do
	line = io.read()
	if not line then os.exit() end
	socket.try(udp:send(line))
	dgram = socket.try(udp:receive())
	print(dgram)
end
