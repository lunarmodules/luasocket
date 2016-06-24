    socket = require"socket"
    socket.unix = require"socket.unix"
    u = assert(socket.unix.tcp())
    assert(u:bind("/tmp/foo"))
    assert(u:listen())
    c = assert(u:accept())
    while 1 do
        print(assert(c:receive()))
    end
