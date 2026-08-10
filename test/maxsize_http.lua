-- Exercises the maxsize caps added to socket.http's line-based receive()
-- calls (see PLAN-RECEIVE-MAXSIZE.md). Self-contained: uses a single
-- process with a real TCP loopback connection, so it needs no paired
-- server script.
local socket = require "socket"
local http = require "socket.http"
local ltn12 = require "ltn12"

local host = "127.0.0.1"

-- connects `open_fn(host, port)` to a freshly bound loopback listener and
-- returns the client-side object it produced plus the server-side raw
-- socket accepted for that connection.
local function new_pair(open_fn)
    local server = assert(socket.bind(host, 0))
    local ip, port = server:getsockname()
    local client = assert(open_fn(ip, port))
    local srv = assert(server:accept())
    server:close()
    return client, srv
end

local failures = 0

local function check(ok, msg)
    if ok then
        print("PASS: " .. msg)
    else
        failures = failures + 1
        print("FAIL: " .. msg)
    end
end

local function http_open(ip, port)
    return http.open(ip, port, socket.tcp)
end

do -- sanity: normal status line + headers still parse
    http.MAXHEADERLINE, http.MAXHEADERSIZE = 8192, 65536
    local h, srv = new_pair(http_open)
    srv:send("HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n")
    local code = socket.protect(function() return h:receivestatusline() end)()
    local headers = socket.protect(function() return h:receiveheaders() end)()
    check(code == 200 and headers and headers["content-length"] == "0",
        "http: normal status line + headers parse")
    h:close(); srv:close()
end

do -- status line over MAXHEADERLINE is rejected
    http.MAXHEADERLINE, http.MAXHEADERSIZE = 16, 1024
    local h, srv = new_pair(http_open)
    srv:send("HTTP/1.1 200 " .. string.rep("x", 40) .. "\r\n")
    local code, err = socket.protect(function() return h:receivestatusline() end)()
    check(code == nil and err == "oversized",
        "http: status line over MAXHEADERLINE -> oversized")
    h:close(); srv:close()
end

do -- a single header line over MAXHEADERLINE is rejected
    http.MAXHEADERLINE, http.MAXHEADERSIZE = 32, 1024
    local h, srv = new_pair(http_open)
    srv:send("HTTP/1.1 200 OK\r\n")
    assert(socket.protect(function() return h:receivestatusline() end)() == 200)
    srv:send("X-Foo: " .. string.rep("y", 60) .. "\r\n\r\n")
    local headers, err = socket.protect(function() return h:receiveheaders() end)()
    check(headers == nil and err == "oversized",
        "http: single header line over MAXHEADERLINE -> oversized")
    h:close(); srv:close()
end

do -- each header line individually fits MAXHEADERLINE, but the total exceeds MAXHEADERSIZE
    http.MAXHEADERLINE, http.MAXHEADERSIZE = 32, 40
    local h, srv = new_pair(http_open)
    srv:send("HTTP/1.1 200 OK\r\n")
    assert(socket.protect(function() return h:receivestatusline() end)() == 200)
    -- each header line is ~23 bytes, individually under MAXHEADERLINE(32)
    srv:send("A: 111111111111111111\r\n")
    srv:send("B: 222222222222222222\r\n")
    local headers, err = socket.protect(function() return h:receiveheaders() end)()
    check(headers == nil and err == "oversized",
        "http: total headers over MAXHEADERSIZE -> oversized (no single line over MAXHEADERLINE)")
    h:close(); srv:close()
end

do -- chunk-size line over MAXHEADERLINE is rejected
    http.MAXHEADERLINE, http.MAXHEADERSIZE = 32, 1024
    local h, srv = new_pair(http_open)
    srv:send("HTTP/1.1 200 OK\r\n")
    assert(socket.protect(function() return h:receivestatusline() end)() == 200)
    srv:send("Transfer-Encoding: chunked\r\n\r\n")
    local headers = assert(socket.protect(function() return h:receiveheaders() end)())
    srv:send(string.rep("f", 40) .. "\r\n") -- oversized chunk-size line
    local t = {}
    local ok, err = socket.protect(function()
        return h:receivebody(headers, (ltn12.sink.table(t)))
    end)()
    check(ok == nil and err == "oversized",
        "http: chunk-size line over MAXHEADERLINE -> oversized")
    h:close(); srv:close()
end

http.MAXHEADERLINE, http.MAXHEADERSIZE = 8192, 65536

if failures == 0 then
    print("All http maxsize tests passed")
    os.exit(0)
else
    print(failures .. " http maxsize test(s) failed")
    os.exit(1)
end
