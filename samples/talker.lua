host = host or "localhost"
port = port or 8080
if arg then
	host = arg[1] or host
	port = arg[2] or port
end
print("Attempting connection to host '" ..host.. "' and port " ..port.. "...")
c, e = connect(host, port)
if not c then
	print(e)
	exit()
end
print("Connected! Please type stuff (empty line to stop):")
l = read()
while l and l ~= "" and not e do
	e = c:send(l, "\n")
	if e then
		print(e)
		exit()
	end
	l = read()
end
