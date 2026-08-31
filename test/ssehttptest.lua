-- End-to-end coverage proving socket.http.request, the headers_callback
-- hook, and socket.sse cooperate correctly over a real socket -- using the
-- httpfixture.lua harness (see httpfixturetest.lua) instead of Apache or a
-- third-party host. Also covers the two headers_callback interactions that
-- only matter once other request-handling logic (redirects,
-- shouldreceivebody) is in the path.
local socket = require("socket")
local http = require("socket.http")
local ltn12 = require("ltn12")
local sse = require("socket.sse")
local fixture = require("httpfixture")

dofile("testsupport.lua")

local url = "http://" .. fixture.host .. ":" .. fixture.port .. "/"

local control, remote = fixture.connect()

io.write("testing a live SSE stream dispatches Messages incrementally, not batched until close: ")
do
    local received, elapsed = {}, {}
    local t0
    local factory = sse.responseheaders(function(message)
        table.insert(received, message)
        table.insert(elapsed, socket.gettime() - t0)
        return true
    end)

    -- Framed as HTTP chunked-transfer-encoding, one SSE Message per HTTP
    -- chunk: the "until-closed"/"default" body source reads in fixed
    -- socket.BLOCKSIZE (2048-byte) gulps, which would silently buffer both
    -- of these small Messages into one read and defeat this test; the
    -- chunked source instead reads exactly each chunk's declared size, so
    -- Message 1 surfaces as soon as its chunk arrives, independent of
    -- Message 2's delayed chunk.
    local function httpchunk(piece)
        return string.format("%x\r\n%s\r\n", #piece, piece)
    end

    -- generous relative to the artificial delay so a loaded CI runner's
    -- scheduling jitter can't turn correct incremental behavior into a
    -- flaky failure; the delay is deliberately long enough that "arrived
    -- before it" and "arrived after it" stay unambiguous even with slack
    local delay = 1.0
    local headersblock = fixture.response("200 OK", {
        "Content-Type: text/event-stream",
        "Transfer-Encoding: chunked",
        "Connection: close",
    }, "")
    fixture.accept_and_send(remote, {
        headersblock,
        httpchunk("data: first\n\n"),
        { httpchunk("data: second\n\n"), delay = delay },
        "0\r\n\r\n",
    })

    t0 = socket.gettime()
    local ok, code = assert(http.request{ url = url .. "sse", headers_callback = factory })
    assert(ok, "request failed")
    assert(code == 200, "status code mismatch: " .. tostring(code))
    assert(#received == 2, "expected two messages, got " .. #received)
    assert(received[1].data == "first", "wrong data for message 1: " .. tostring(received[1].data))
    assert(received[2].data == "second", "wrong data for message 2: " .. tostring(received[2].data))
    -- message 1 must have been dispatched well before the server even sent
    -- (let alone finished delaying) message 2 -- if delivery were batched
    -- until the connection closed instead, both messages would only appear
    -- once the full delay had elapsed
    assert(elapsed[1] < delay / 2,
        "message 1 dispatched too late (" .. elapsed[1] .. "s) to have arrived before message 2's delayed send")
    assert(elapsed[2] >= delay / 2,
        "message 2 dispatched suspiciously early (" .. elapsed[2] .. "s); the server's artificial delay may not have been exercised")
end
print("ok")

io.write("testing headers_callback is not invoked for a redirected (3xx) response: ")
do
    local calls = {}
    local function responseheaders(code)
        table.insert(calls, code)
        return true
    end

    local redirect = fixture.response("302 Found", {
        "Location: /final",
        "Content-Length: 0",
        "Connection: close",
    }, "")
    local finalbody = "landed"
    local final = fixture.response("200 OK", {
        "Content-Length: " .. #finalbody,
        "Connection: close",
    }, finalbody)
    fixture.accept_and_send_sequence(remote, { { redirect }, { final } })

    local target = {}
    local ok, code = assert(http.request{
        url = url .. "redirect-me",
        sink = ltn12.sink.table(target),
        headers_callback = responseheaders,
    })
    assert(ok, "request failed")
    assert(table.concat(target) == finalbody, "expected the redirected response's body")
    assert(code == 200, "expected the final response's status code, got " .. tostring(code))
    assert(#calls == 1, "expected headers_callback to be invoked exactly once, got " .. #calls)
    assert(calls[1] == 200, "headers_callback must only ever see the final response, got " .. tostring(calls[1]))
end
print("ok")

-- Shared by the three shouldreceivebody variants below (204, 304, HEAD):
-- scripts `response`, issues a request built from `reqtextra`, and asserts
-- headers_callback still fires with `expectedcode` while the sink it offers
-- is never actually invoked, since shouldreceivebody skips the body.
local function assertsinkswapskipped(reqtextra, response, expectedcode)
    local sinkcalls, invokedwith = 0, nil
    local function responseheaders(code)
        invokedwith = code
        return true, function() sinkcalls = sinkcalls + 1; return 1 end
    end
    fixture.accept_and_send(remote, { response })

    local reqt = { url = url .. "skip-body", headers_callback = responseheaders }
    for k, v in pairs(reqtextra or {}) do reqt[k] = v end
    local ok, code = assert(http.request(reqt))
    assert(ok, "request failed")
    assert(code == expectedcode, "status code mismatch: " .. tostring(code))
    assert(invokedwith == expectedcode, "expected headers_callback to still be invoked, got " .. tostring(invokedwith))
    assert(sinkcalls == 0, "the offered sink must never run when shouldreceivebody skips the body")
end

io.write("testing the headers_callback sink-swap offer is inert when a 204 response skips the body: ")
assertsinkswapskipped(nil, fixture.response("204 No Content", { "Connection: close" }, ""), 204)
print("ok")

io.write("testing the headers_callback sink-swap offer is inert when a 304 response skips the body: ")
assertsinkswapskipped(nil, fixture.response("304 Not Modified", { "Connection: close" }, ""), 304)
print("ok")

io.write("testing the headers_callback sink-swap offer is inert when a HEAD request skips the body: ")
do
    local body = "should never be read"
    local response = fixture.response("200 OK", {
        "Content-Length: " .. #body,
        "Connection: close",
    }, body)
    assertsinkswapskipped({ method = "HEAD" }, response, 200)
end
print("ok")

remote("os.exit()")

print("the library passed all tests")
