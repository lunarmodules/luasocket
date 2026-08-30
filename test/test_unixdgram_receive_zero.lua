#!/usr/bin/env lua

-- Same reasoning as test_udp_receive_zero.lua: "receive 0 bytes" on a
-- datagram socket is really two different requests sharing one call
-- shape -- (a) a side-effect-free readiness probe, and (b) "my protocol's
-- messages are always empty-payload signals, receive one normally, I
-- just don't need a payload back" (a zero-length datagram is a
-- completely legitimate thing to put on the wire).
--
-- receive() has no sender-address field to disambiguate (a) from (b), so
-- it stays the deterministic no-op it already was via the shared
-- socket_recv() guard (unaffected here, same as TCP). receivefrom() does
-- have that field: unlike inet UDP, unixdgram.c already handled an
-- unpopulated sender path gracefully (it pre-zeroes sun_path and just
-- returns whatever's there -- see the "may be empty when client sent
-- without bind" comment in unixdgram.c), so receivefrom(0) here was
-- never at risk of the getnameinfo crash inet UDP had. It's left making
-- the real recvfrom() call: nothing pending is platform-dependent
-- (blocks on Linux/Windows, returns immediately on Darwin/BSD -- see the
-- platform table in test_udp_receive_zero.lua), but a pending datagram is
-- always correctly consumed and its sender always correctly reported.

local socket = require "socket"
local unix = require "socket.unix"

local function new_pair(server_path, client_path)
    os.remove(server_path)
    os.remove(client_path)
    local server = assert(unix.dgram())
    assert(server:bind(server_path))
    local client = assert(unix.dgram())
    assert(client:bind(client_path))
    assert(client:connect(server_path))
    server:settimeout(1)
    return server, client
end

local function cleanup(server, client, server_path, client_path)
    client:close()
    server:close()
    os.remove(server_path)
    os.remove(client_path)
end

-- Detects which of the three documented recvfrom(0)-with-nothing-pending
-- behaviors applies here, so the test below can assert the right one by
-- name instead of accepting either shape. "unknown" is the honest answer
-- when uname isn't available to tell Linux and Darwin/BSD apart (e.g. a
-- locked-down sandbox); the test falls back to accepting either
-- documented shape in that case, rather than guessing.
local function detect_platform()
    if package.config:sub(1, 1) == "\\" then
        return "windows"
    end
    local handle = io.popen("uname -s 2>/dev/null")
    if not handle then
        return "unknown"
    end
    local name = handle:read("*l")
    handle:close()
    if not name then
        return "unknown"
    end
    name = name:lower()
    if name:find("linux") then
        return "linux"
    elseif name:find("darwin") or name:find("bsd") then
        return "darwin"
    end
    return "unknown"
end

local platform = detect_platform()

-- === receive(0): deterministic no-op, nothing pending ===
do
    local spath, cpath = "/tmp/luasocket-test-udgram-1-srv.sock", "/tmp/luasocket-test-udgram-1-clt.sock"
    local server, client = new_pair(spath, cpath)

    local t0 = socket.gettime()
    local rdata, rerr = server:receive(0)
    local elapsed = socket.gettime() - t0
    assert(rdata == "" and rerr == nil,
        "receive(0) with nothing pending returned " .. tostring(rdata) .. ", " .. tostring(rerr))
    assert(elapsed < 0.5,
        "receive(0) with nothing pending blocked for " .. elapsed .. "s")

    cleanup(server, client, spath, cpath)
end

-- === receive(0): deterministic no-op, a datagram pending must be left untouched ===
do
    local spath, cpath = "/tmp/luasocket-test-udgram-2-srv.sock", "/tmp/luasocket-test-udgram-2-clt.sock"
    local server, client = new_pair(spath, cpath)

    assert(client:send("world"))
    socket.sleep(0.1)

    local data, err = server:receive(0)
    assert(data == "" and err == nil,
        "receive(0) with data pending returned " .. tostring(data) .. ", " .. tostring(err))

    data, err = assert(server:receive())
    assert(data == "world",
        "receive(0) consumed or corrupted the pending datagram: got " .. tostring(data))

    cleanup(server, client, spath, cpath)
end

-- === receivefrom(0): nothing pending -- the outcome is platform-specific
-- (see the comment block at the top of test_udp_receive_zero.lua),
-- asserted explicitly per platform so it's clear which behavior is
-- expected where ===
do
    local spath, cpath = "/tmp/luasocket-test-udgram-3-srv.sock", "/tmp/luasocket-test-udgram-3-clt.sock"
    local server, client = new_pair(spath, cpath)

    local data, addr = server:receivefrom(0)

    if platform == "linux" or platform == "windows" then
        -- both block until a real datagram arrives; nothing does, so the
        -- call must time out, not fabricate a result
        assert(data == nil and addr == "timeout",
            "receivefrom(0) with nothing pending on " .. platform ..
            " should time out, got " .. tostring(data) .. ", " .. tostring(addr))

    elseif platform == "darwin" then
        -- the kernel's zero-length recvfrom() is always immediately
        -- satisfiable, so this must return right away, with no sender path
        assert(data == "" and addr == "",
            "receivefrom(0) with nothing pending on darwin should return " ..
            "immediately with no sender path, got " ..
            tostring(data) .. ", " .. tostring(addr))

    else
        -- platform could not be determined: accept either documented
        -- shape rather than assert one and risk a false failure
        local timed_out_like_linux_or_windows = data == nil and addr == "timeout"
        local returned_immediately_like_darwin = data == "" and addr == ""
        assert(timed_out_like_linux_or_windows or returned_immediately_like_darwin,
            "receivefrom(0) with nothing pending returned an unexpected shape: " ..
            tostring(data) .. ", " .. tostring(addr))
    end

    cleanup(server, client, spath, cpath)
end

-- === receivefrom(0): a datagram is pending -- must be consumed and its
-- sender correctly reported, on every platform ===
do
    local spath, cpath = "/tmp/luasocket-test-udgram-4-srv.sock", "/tmp/luasocket-test-udgram-4-clt.sock"
    local server, client = new_pair(spath, cpath)

    assert(client:send("hello"))
    socket.sleep(0.1)

    local data, addr = server:receivefrom(0)
    assert(data == "" and addr == cpath,
        "receivefrom(0) with data pending returned " .. tostring(data) .. ", " .. tostring(addr))

    server:settimeout(0.3)
    data = server:receive()
    assert(data == nil,
        "receivefrom(0) did not actually consume the pending datagram: receive() still got " ..
        tostring(data))

    cleanup(server, client, spath, cpath)
end

-- === the real-world case this whole file is about: a protocol whose
-- messages are always empty-payload signals. receivefrom(0) must work as
-- a normal receive path for it -- reporting the (empty) payload and the
-- sender -- not just as a probe for some other, larger message. ===
do
    local spath, cpath = "/tmp/luasocket-test-udgram-5-srv.sock", "/tmp/luasocket-test-udgram-5-clt.sock"
    local server, client = new_pair(spath, cpath)

    -- sanity check: a genuine zero-length datagram, read with a
    -- normal-sized buffer, already works (untouched by any of this)
    assert(client:send(""))
    socket.sleep(0.1)
    local data, addr = server:receivefrom()
    assert(data == "" and addr == cpath,
        "a real zero-length datagram, read normally, returned " ..
        tostring(data) .. ", " .. tostring(addr))

    -- the actual point: a receiver that knows every message on this
    -- socket is an empty signal can use receivefrom(0) as its normal
    -- receive call, and still learn who signaled it
    assert(client:send(""))
    socket.sleep(0.1)
    data, addr = server:receivefrom(0)
    assert(data == "" and addr == cpath,
        "receivefrom(0) as a normal receive path for a signal datagram returned " ..
        tostring(data) .. ", " .. tostring(addr))

    cleanup(server, client, spath, cpath)
end

print("done!")
