socket = require("socket")
f = loadlib("etc-1.0.dylib", "unix_open")
f(socket)
u = socket.unix()
print(u:bind("/tmp/luasocket"))
print(u:listen())
c = u:accept()
while 1 do
    print(assert(c:receive()))
end
