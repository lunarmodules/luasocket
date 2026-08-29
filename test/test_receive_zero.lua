-- a TCP receive(0) must never block: requesting zero bytes is trivially
-- satisfied without touching the transport layer, POSIX recv(fd, buf, 0, 0)
-- returns immediately regardless of whether data is available.
local socket = require "socket"

local host, port = "127.0.0.1", "5464"

local server = assert(socket.bind(host, port))
local client = assert(socket.connect(host, port))
local peer = assert(server:accept())

client:settimeout(2)

-- no data has been sent by the peer: the read buffer is empty, so if
-- receive(0) touches the network it will block until the timeout expires
local t0 = socket.gettime()
local data, err = client:receive(0)
local elapsed = socket.gettime() - t0

assert(data == "", "receive(0) on empty buffer returned " .. tostring(data))
assert(err == nil, "receive(0) on empty buffer returned error " .. tostring(err))
assert(elapsed < 1, "receive(0) on empty buffer blocked for " .. elapsed .. "s")

-- receive(0) must also not consume any bytes when data *is* available
assert(peer:send("hello"))
data, err = client:receive(0)
assert(data == "", "receive(0) with data pending returned " .. tostring(data))
assert(err == nil, "receive(0) with data pending returned error " .. tostring(err))
data = assert(client:receive(5))
assert(data == "hello", "receive(0) consumed bytes meant for receive(5)")

client:close()
peer:close()
server:close()

print("done!")
