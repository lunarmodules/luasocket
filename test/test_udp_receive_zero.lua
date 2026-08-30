#!/usr/bin/env lua

-- "receive 0 bytes" on a UDP socket is really two different requests that
-- happen to share one call shape:
--
--   (a) "give me a side-effect-free readiness probe" -- don't touch
--       anything, just tell me instantly whether I'd have blocked.
--   (b) "my protocol's messages are always empty-payload signals (UDP
--       explicitly allows a zero-length datagram on the wire -- see
--       udp-zero-length-send-recv in this same directory); receive one
--       like any other, I just don't need a payload back."
--
-- These two conflict on at least one real platform. A Darwin/BSD kernel's
-- recvfrom() returns 0 bytes immediately for a zero-length request
-- whether or not anything was actually queued -- so byte count alone can
-- never distinguish (a) from (b) there. Linux and (per MSDN's
-- recv()/recvfrom() docs -- no exception is carved out for SOCK_DGRAM the
-- way there is for "byte stream-style sockets" and WSAEINVAL, though this
-- is not independently confirmed against a live Windows kernel) Windows
-- both block until something real arrives, so they don't have this
-- ambiguity at all.
--
--   platform    | nothing pending              | datagram pending
--   ------------+------------------------------+---------------------------
--   Linux       | blocks until one arrives     | consumed & reported
--   Windows     | blocks until one arrives *   | consumed & reported *
--   Darwin/BSD  | returns 0 immediately,       | consumed & reported
--               | never blocks                 |
--
-- What breaks the tie: receivefrom() also reports the sender's address,
-- and that address comes back unpopulated when nothing was queued and
-- correctly populated when a real datagram was consumed -- on every
-- platform, Darwin included. So while byte count can't disambiguate (a)
-- from (b) on Darwin, the address can. receivefrom(0) is therefore left
-- to make the real recvfrom() call: it correctly serves use case (b)
-- everywhere, and on Darwin specifically it gives an honest "nil address"
-- for (a) instead of the alternative this test suite used to ship -- a
-- crash out of getnameinfo() on a garbage/unpopulated sockaddr.
--
-- receive() has no such disambiguator (no address field to check), so
-- unguarding it would only buy back blocking-until-signal on Linux/
-- Windows while remaining just as ambiguous as before on Darwin. It's
-- left as the deterministic no-op it already was (LuaSocket's TCP
-- receive(0) fix, inherited via the shared socket_recv()) -- and that
-- happens to be exactly what Python's socket.recv(0) already does
-- (CPython's sock_recv_guts), for the same reason.
--
-- How other cross-platform standard libraries handle this, checked at the
-- source level rather than the docs:
--
--   language | receive()-equivalent   | receivefrom()-equivalent
--   ---------+-------------------------+---------------------------------------
--   Go       | UDPConn.Read: guarded, | UDPConn.ReadFrom: unguarded, and built
--            | deterministic no-op    | the same way LuaSocket's own
--            | (internal/poll.        | socket_recvfrom() is: try the syscall
--            | FD.Read)               | first (internal/poll.FD.ReadFrom calls
--            |                        | syscall.Recvfrom directly), only wait
--            |                        | after EAGAIN. Almost certainly shares
--            |                        | the Darwin quirk above as a result;
--            |                        | not confirmed whether Go's sockaddr
--            |                        | conversion crashes or silently zeroes
--            |                        | on an address the kernel never filled
--            |                        | in.
--   Python   | socket.recv():         | socket.recvfrom(): sock_recvfrom_guts
--            | guarded, determin-     | has no len==0 guard either, but does
--            | istic no-op            | NOT hit the Darwin quirk in practice --
--            | (sock_recv_guts)       | it blocks for the full timeout with
--            |                        | nothing pending, same as Linux would.
--            |                        | CPython's sock_call_ex runs a real
--            |                        | select()/poll() readiness gate
--            |                        | (internal_select()) before ever
--            |                        | calling recvfrom(), for any operation
--            |                        | with a timeout. That gate reports
--            |                        | "not readable" honestly regardless of
--            |                        | the requested length, so the quirk
--            |                        | never gets a chance to fire. It's a
--            |                        | side effect of Python's general
--            |                        | blocking-with-timeout architecture,
--            |                        | not anything specific to recvfrom()
--            |                        | or to len==0.
--   Rust     | UdpSocket::recv:       | UdpSocket::recv_from: unguarded,
--            | unguarded, platform-   | platform-dependent -- straight to
--            | dependent              | libc::recvfrom, no select-gate, no
--            |                        | len==0 guard anywhere.
--
-- So "platform-dependent" isn't actually the right label for every
-- unguarded implementation. Go shares LuaSocket's original exposure to
-- the Darwin quirk because it shares the same try-syscall-first shape;
-- Python avoids the quirk entirely, but via unrelated select-gating
-- machinery, not via anything resembling the address-population check
-- this fix adds. None of the three has that specific fix; LuaSocket adds
-- it here.

local socket = require "socket"

local host = "127.0.0.1"

local function new_pair(port)
    local server = assert(socket.udp())
    assert(server:setsockname(host, port))
    local client = assert(socket.udp())
    assert(client:setpeername(host, port))
    server:settimeout(1)
    return server, client
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
    local server, client = new_pair("5465")

    local t0 = socket.gettime()
    local data, err = server:receive(0)
    local elapsed = socket.gettime() - t0
    assert(data == "" and err == nil,
        "receive(0) with nothing pending returned " .. tostring(data) .. ", " .. tostring(err))
    assert(elapsed < 0.5,
        "receive(0) with nothing pending blocked for " .. elapsed .. "s")

    client:close()
    server:close()
end

-- === receive(0): deterministic no-op, a datagram pending must be left untouched ===
do
    local server, client = new_pair("5466")

    assert(client:send("world"))
    socket.sleep(0.1)

    local data, err = server:receive(0)
    assert(data == "" and err == nil,
        "receive(0) with data pending returned " .. tostring(data) .. ", " .. tostring(err))

    data = assert(server:receive())
    assert(data == "world",
        "receive(0) consumed or corrupted the pending datagram: got " .. tostring(data))

    client:close()
    server:close()
end

-- === receivefrom(0): nothing pending -- the outcome is platform-specific
-- (see the comment block at the top of this file), asserted explicitly
-- per platform so it's clear which behavior is expected where ===
do
    local server, client = new_pair("5467")

    local data, ip, port = server:receivefrom(0)

    if platform == "linux" or platform == "windows" then
        -- both block until a real datagram arrives; nothing does, so the
        -- call must time out, not fabricate a result
        assert(data == nil and ip == "timeout",
            "receivefrom(0) with nothing pending on " .. platform ..
            " should time out, got " .. tostring(data) .. ", " .. tostring(ip))

    elseif platform == "darwin" then
        -- the kernel's zero-length recvfrom() is always immediately
        -- satisfiable, so this must return right away, with no address
        assert(data == "" and ip == nil and port == nil,
            "receivefrom(0) with nothing pending on darwin should return " ..
            "immediately with no address, got " ..
            tostring(data) .. ", " .. tostring(ip) .. ", " .. tostring(port))

    else
        -- platform could not be determined: accept either documented
        -- shape rather than assert one and risk a false failure
        local timed_out_like_linux_or_windows = data == nil and ip == "timeout"
        local returned_immediately_like_darwin = data == "" and ip == nil and port == nil
        assert(timed_out_like_linux_or_windows or returned_immediately_like_darwin,
            "receivefrom(0) with nothing pending returned an unexpected shape: " ..
            tostring(data) .. ", " .. tostring(ip) .. ", " .. tostring(port))
    end

    client:close()
    server:close()
end

-- === receivefrom(0): a datagram is pending -- must be consumed and its
-- sender correctly reported, on every platform ===
do
    local server, client = new_pair("5468")

    assert(client:send("hello"))
    socket.sleep(0.1)

    local data, ip, port = server:receivefrom(0)
    assert(data == "" and ip == "127.0.0.1" and type(port) == "number",
        "receivefrom(0) with data pending returned " ..
        tostring(data) .. ", " .. tostring(ip) .. ", " .. tostring(port))

    -- the payload is gone (all that a 0-byte request can ever return), but
    -- unlike a crash or a phantom no-op, the caller correctly learned that
    -- something arrived and who sent it
    server:settimeout(0.3)
    data = server:receive()
    assert(data == nil,
        "receivefrom(0) did not actually consume the pending datagram: receive() still got " ..
        tostring(data))

    client:close()
    server:close()
end

-- === the real-world case this whole file is about: a protocol whose
-- messages are always empty-payload signals. A 0-length UDP datagram is
-- a completely legitimate thing to put on the wire (see
-- udp-zero-length-send-recv), and receivefrom(0) must work as a normal
-- receive path for it -- reporting the (empty) payload and the sender --
-- not just as a probe for some other, larger message. ===
do
    local server, client = new_pair("5469")

    -- sanity check: a genuine zero-length datagram over the wire, read
    -- with a normal-sized buffer, already works (untouched by any of this)
    assert(client:send(""))
    socket.sleep(0.1)
    local data, ip, port = server:receivefrom()
    assert(data == "" and ip == "127.0.0.1" and type(port) == "number",
        "a real zero-length datagram, read normally, returned " ..
        tostring(data) .. ", " .. tostring(ip) .. ", " .. tostring(port))

    -- the actual point: a receiver that knows every message on this
    -- socket is an empty signal can use receivefrom(0) as its normal
    -- receive call, and still learn who signaled it
    assert(client:send(""))
    socket.sleep(0.1)
    data, ip, port = server:receivefrom(0)
    assert(data == "" and ip == "127.0.0.1" and type(port) == "number",
        "receivefrom(0) as a normal receive path for a signal datagram returned " ..
        tostring(data) .. ", " .. tostring(ip) .. ", " .. tostring(port))

    client:close()
    server:close()
end

print("done!")
