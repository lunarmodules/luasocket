local socket = require "socket"

local host, port = "127.0.0.1", "5462"

local srv = assert(socket.bind(host, port))

local sock_cli = socket.tcp()
assert(sock_cli:connect(host, port))

local fd do
  local sock_srv = assert(srv:accept())
  fd = assert(sock_srv:getfd())

  assert(not pcall(function() sock_srv:setfd(nil) end))
  sock_srv:setfd()
  assert(sock_srv:close())
end

local sock_srv = assert(socket.tcp(fd, "client"))
collectgarbage"collect"
collectgarbage"collect"

assert(5 == assert(sock_srv:send("hello")))
assert("hello" == assert(sock_cli:receive(5)))

sock_cli:close()
sock_srv:close()
srv:close()

print("done!")