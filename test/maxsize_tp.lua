-- Exercises the maxsize caps added to socket.tp's line-based receive()
-- calls (see PLAN-RECEIVE-MAXSIZE.md). socket.tp is the shared control
-- channel underneath both socket.ftp and socket.smtp, so this covers both.
-- Self-contained: uses a single process with a real TCP loopback
-- connection, so it needs no paired server script.
local socket = require "socket"
local tp = require "socket.tp"

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

local function tp_open(ip, port)
    return tp.connect(ip, port, 5)
end

do -- sanity: normal single-line reply still parses
    tp.MAXLINE, tp.MAXREPLY = 8192, 65536
    local c, srv = new_pair(tp_open)
    srv:send("230 logged in\r\n")
    local code, reply = c:check("2..")
    check(code == 230 and reply == "230 logged in",
        "tp: normal single-line reply parses")
    c:close(); srv:close()
end

do -- sanity: normal multiline reply still parses
    tp.MAXLINE, tp.MAXREPLY = 8192, 65536
    local c, srv = new_pair(tp_open)
    srv:send("214-first line\r\n214-second line\r\n214 done\r\n")
    local code, reply = c:check("2..")
    check(code == 214 and reply == "214-first line\n214-second line\n214 done",
        "tp: normal multiline reply parses")
    c:close(); srv:close()
end

do -- a single reply line over MAXLINE is rejected
    tp.MAXLINE, tp.MAXREPLY = 8, 65536
    local c, srv = new_pair(tp_open)
    srv:send("230 this line is way over the line cap\r\n")
    local code, err = c:check("2..")
    check(code == nil and err == "oversized",
        "tp: single line over MAXLINE -> oversized")
    c:close(); srv:close()
end

do -- each line individually fits MAXLINE, but the reply total exceeds MAXREPLY
    tp.MAXLINE, tp.MAXREPLY = 16, 20
    local c, srv = new_pair(tp_open)
    -- first line: 14 payload bytes, under both MAXLINE(16) and MAXREPLY(20)
    srv:send("123-aaaaaaaaaa\r\n")
    -- second line: another 14 payload bytes, individually under MAXLINE(16),
    -- but only 6 bytes remain in the MAXREPLY(20) budget
    srv:send("123-bbbbbbbbbb\r\n")
    local code, err = c:check("2..")
    check(code == nil and err == "oversized",
        "tp: multiline reply over MAXREPLY -> oversized (no single line over MAXLINE)")
    c:close(); srv:close()
end

tp.MAXLINE, tp.MAXREPLY = 8192, 65536

if failures == 0 then
    print("All tp maxsize tests passed")
    os.exit(0)
else
    print(failures .. " tp maxsize test(s) failed")
    os.exit(1)
end
