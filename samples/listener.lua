host = host or "*"
port = port or 8080
if arg then
	host = arg[1] or host
	port = arg[2] or port
end
print("Binding to host '" ..host.. "' and port " ..port.. "...")
s, e = bind(host, port)
if not s then
	print(e)
	exit()
end
i, p = s:getsockname()
print("Waiting connection from talker on " .. i .. ":" .. p .. "...")
c, e = s:accept()
if not c then
	print(e)
	exit()
end
print("Connected. Here is the stuff:")
l, e = c:receive()
while not e do
	print(l)
	l, e = c:receive()
end
print(e)
