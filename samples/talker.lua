-----------------------------------------------------------------------------
-- TCP sample: Little program to send text lines to a given host/port
-- LuaSocket sample files
-- Author: Diego Nehab
-- RCS ID: $Id$
-----------------------------------------------------------------------------
host = host or "localhost"
port = port or 8080
if arg then
	host = arg[1] or host
	port = arg[2] or port
end
print("Attempting connection to host '" ..host.. "' and port " ..port.. "...")
c, e = socket.connect(host, port)
if not c then
	print(e)
	os.exit()
end
print("Connected! Please type stuff (empty line to stop):")
l = io.read()
while l and l ~= "" and not e do
	t, e = c:send(l, "\n")
	if e then
		print(e)
		os.exit()
	end
	l = io.read()
end
