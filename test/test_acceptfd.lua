local socket = require "socket"

local host, port = "127.0.0.1", "5462"

local srv = assert(socket.bind(host, port))

local sock = socket.tcp()
assert(sock:connect(host, port))

local fd = assert(srv:acceptfd())
assert(type(fd) == "number")

local cli = assert(socket.tcp(fd, "client"))

assert(5 == assert(cli:send("hello")))
assert("hello" == assert(sock:receive(5)))

cli:close()
sock:close()
srv:close()

print("done!")