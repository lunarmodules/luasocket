-- Smoke tests proving out the httpfixture.lua harness: drive
-- socket.http.request against fully scripted, controlled raw HTTP
-- responses over a real socket via the testsrvr.lua remote-execution
-- server -- no Apache, no Docker, no third-party hosts. Later SSE tests
-- build on this same fixture for real-socket, incremental-delivery
-- coverage.
local http = require("socket.http")
local fixture = require("httpfixture")

dofile("testsupport.lua")

local url = "http://" .. fixture.host .. ":" .. fixture.port .. "/"

local control, remote = fixture.connect()

io.write("testing plain GET with a known body: ")
do
    local body = "hello, luasocket"
    local response = fixture.response("200 OK", {
        "Content-Length: " .. #body,
        "Connection: close",
    }, body)
    fixture.accept_and_send(remote, { response })

    local respbody, code = assert(http.request(url .. "get"))
    assert(respbody == body, "body mismatch: " .. tostring(respbody))
    assert(code == 200, "status code mismatch: " .. tostring(code))
end
print("ok")

io.write("testing chunked-transfer-encoded body: ")
do
    local pieces = { "Hello, ", "chunked ", "world!" }
    local response = fixture.response("200 OK", {
        "Transfer-Encoding: chunked",
        "Connection: close",
    }, fixture.chunked(pieces))
    fixture.accept_and_send(remote, { response })

    local respbody, code = assert(http.request(url .. "chunked"))
    assert(respbody == table.concat(pieces), "body mismatch: " .. tostring(respbody))
    assert(code == 200, "status code mismatch: " .. tostring(code))
end
print("ok")

io.write("testing a body delivered across separately-timed writes: ")
do
    local part1, part2 = "partial-", "delivery"
    local body = part1 .. part2
    local headersblock = fixture.response("200 OK", {
        "Content-Length: " .. #body,
        "Connection: close",
    }, "")
    fixture.accept_and_send(remote, {
        headersblock,
        { part1, delay = 0.2 },
        part2,
    })

    local respbody, code = assert(http.request(url .. "slow"))
    assert(respbody == body, "body mismatch: " .. tostring(respbody))
    assert(code == 200, "status code mismatch: " .. tostring(code))
end
print("ok")

remote("os.exit()")

print("the library passed all tests")
