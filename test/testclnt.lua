host = host or "localhost"
port = port or "8080"

function pass(...)
    local s = string.format(unpack(arg))
    io.write(s, "\n")
end

function fail(...)
    local s = string.format(unpack(arg))
    io.write("ERROR: ", s, "!\n")
    os.exit()
end

function warn(...)
    local s = string.format(unpack(arg))
    io.write("WARNING: ", s, "\n")
end

pad = string.rep(" ", 8192)

function remote(...)
    local s = string.format(unpack(arg))
    s = string.gsub(s, "\n", ";")
    s = string.gsub(s, "%s+", " ")
    s = string.gsub(s, "^%s*", "")
    control:send(pad, s, "\n")
    control:receive()
end

function test(test)
    io.write("----------------------------------------------\n",
        "testing: ", test, "\n",
        "----------------------------------------------\n")
end

function check_timeout(tm, sl, elapsed, err, opp, mode, alldone)
    if tm < sl then
        if opp == "send" then
            if not err then warn("must be buffered")
            elseif err == "timeout" then pass("proper timeout")
            else fail("unexpected error '%s'", err) end
        else 
            if err ~= "timeout" then fail("should have timed out") 
            else pass("proper timeout") end
        end
    else
        if mode == "total" then
            if elapsed > tm then 
                if err ~= "timeout" then fail("should have timed out")
                else pass("proper timeout") end
            elseif elapsed < tm then
                if err then fail(err) 
                else pass("ok") end
            else 
                if alldone then 
                    if err then fail("unexpected error '%s'", err) 
                    else pass("ok") end
                else
                    if err ~= "timeout" then fail(err) 
                    else pass("proper timeoutk") end
                end
            end
        else 
            if err then fail(err) 
            else pass("ok") end 
        end
    end
end

if not socket.debug then
    fail("Please define LUASOCKET_DEBUG and recompile LuaSocket")
end

io.write("----------------------------------------------\n",
"LuaSocket Test Procedures\n",
"----------------------------------------------\n")

start = socket.time()

function reconnect()
    io.write("attempting data connection... ")
    if data then data:close() end
    remote [[
        if data then data:close() data = nil end
        data = server:accept()
        data:setoption("tcp-nodelay", true)
    ]]
    data, err = socket.connect(host, port)
    if not data then fail(err) 
    else pass("connected!") end
    data:setoption("tcp-nodelay", true)
end

pass("attempting control connection...")
control, err = socket.connect(host, port)
if err then fail(err)
else pass("connected!") end
control:setoption("tcp-nodelay", true)

------------------------------------------------------------------------
function test_methods(sock, methods)
    for _, v in methods do
        if type(sock[v]) ~= "function" then 
            fail(sock.class .. " method '" .. v .. "' not registered") 
        end
    end
    pass(sock.class .. " methods are ok")
end

------------------------------------------------------------------------
function test_mixed(len)
    reconnect()
    local inter = math.ceil(len/4)
    local p1 = "unix " .. string.rep("x", inter) .. "line\n"
    local p2 = "dos " .. string.rep("y", inter) .. "line\r\n"
    local p3 = "raw " .. string.rep("z", inter) .. "bytes"
    local p4 = "end" .. string.rep("w", inter) .. "bytes"
    local bp1, bp2, bp3, bp4
remote (string.format("str = data:receive(%d)", 
            string.len(p1)+string.len(p2)+string.len(p3)+string.len(p4)))
    sent, err = data:send(p1, p2, p3, p4)
    if err then fail(err) end
remote "data:send(str); data:close()"
    bp1, bp2, bp3, bp4, err = data:receive("*l", "*l", string.len(p3), "*a")
    if err then fail(err) end
    if bp1.."\n" == p1 and bp2.."\r\n" == p2 and bp3 == p3 and bp4 == p4 then
        pass("patterns match")
    else fail("patterns don't match") end
end

------------------------------------------------------------------------
function test_asciiline(len)
    reconnect()
    local str, str10, back, err
    str = string.rep("x", math.mod(len, 10))
    str10 = string.rep("aZb.c#dAe?", math.floor(len/10))
    str = str .. str10
remote "str = data:receive()"
    sent, err = data:send(str, "\n")
    if err then fail(err) end
remote "data:send(str, '\\n')"
    back, err = data:receive()
    if err then fail(err) end
    if back == str then pass("lines match")
    else fail("lines don't match") end
end

------------------------------------------------------------------------
function test_rawline(len)
    reconnect()
    local str, str10, back, err
    str = string.rep(string.char(47), math.mod(len, 10))
    str10 = string.rep(string.char(120,21,77,4,5,0,7,36,44,100), 
            math.floor(len/10))
    str = str .. str10
remote "str = data:receive()"
    sent, err = data:send(str, "\n")
    if err then fail(err) end
remote "data:send(str, '\\n')"
    back, err = data:receive()
    if err then fail(err) end
    if back == str then pass("lines match")
    else fail("lines don't match") end
end

------------------------------------------------------------------------
function test_raw(len)
    reconnect()
    local half = math.floor(len/2)
    local s1, s2, back, err
    s1 = string.rep("x", half)
    s2 = string.rep("y", len-half)
remote (string.format("str = data:receive(%d)", len))
    sent, err = data:send(s1)
    if err then fail(err) end
    sent, err = data:send(s2)
    if err then fail(err) end
remote "data:send(str)"
    back, err = data:receive(len)
    if err then fail(err) end
    if back == s1..s2 then pass("blocks match")
    else fail("blocks don't match") end
end

------------------------------------------------------------------------
function test_totaltimeoutreceive(len, tm, sl)
    reconnect()
    local str, err, total
    pass("%d bytes, %ds total timeout, %ds pause", len, tm, sl)
    remote (string.format ([[
        data:settimeout(%d)
        str = string.rep('a', %d)
        data:send(str)
        print('server: sleeping for %ds')
        socket.sleep(%d)
        print('server: woke up')
        data:send(str)
    ]], 2*tm, len, sl, sl))
    data:settimeout(tm, "total")
    str, err, elapsed = data:receive(2*len)
    check_timeout(tm, sl, elapsed, err, "receive", "total", 
        string.len(str) == 2*len)
end

------------------------------------------------------------------------
function test_totaltimeoutsend(len, tm, sl)
    reconnect()
    local str, err, total
    pass("%d bytes, %ds total timeout, %ds pause", len, tm, sl)
    remote (string.format ([[
        data:settimeout(%d)
        str = data:receive(%d)
        print('server: sleeping for %ds')
        socket.sleep(%d)
        print('server: woke up')
        str = data:receive(%d)
    ]], 2*tm, len, sl, sl, len))
    data:settimeout(tm, "total")
    str = string.rep("a", 2*len)
    total, err, elapsed = data:send(str)
    check_timeout(tm, sl, elapsed, err, "send", "total", 
        total == 2*len)
end

------------------------------------------------------------------------
function test_blockingtimeoutreceive(len, tm, sl)
    reconnect()
    local str, err, total
    pass("%d bytes, %ds blocking timeout, %ds pause", len, tm, sl)
    remote (string.format ([[
        data:settimeout(%d)
        str = string.rep('a', %d)
        data:send(str)
        print('server: sleeping for %ds')
        socket.sleep(%d)
        print('server: woke up')
        data:send(str)
    ]], 2*tm, len, sl, sl))
    data:settimeout(tm)
    str, err, elapsed = data:receive(2*len)
    check_timeout(tm, sl, elapsed, err, "receive", "blocking", 
        string.len(str) == 2*len)
end

------------------------------------------------------------------------
function test_blockingtimeoutsend(len, tm, sl)
    reconnect()
    local str, err, total
    pass("%d bytes, %ds blocking timeout, %ds pause", len, tm, sl)
    remote (string.format ([[
        data:settimeout(%d)
        str = data:receive(%d)
        print('server: sleeping for %ds')
        socket.sleep(%d)
        print('server: woke up')
        str = data:receive(%d)
    ]], 2*tm, len, sl, sl, len))
    data:settimeout(tm)
    str = string.rep("a", 2*len)
    total, err,  elapsed = data:send(str)
    check_timeout(tm, sl, elapsed, err, "send", "blocking",
        total == 2*len)
end

------------------------------------------------------------------------
function empty_connect()
    reconnect()
    if data then data:close() data = nil end
    remote [[
        if data then data:close() data = nil end
        data = server:accept()
    ]]
    data, err = socket.connect("", port)
    if not data then 
        pass("ok")
        data = socket.connect(host, port)
    else fail("should not have connected!") end
end

------------------------------------------------------------------------
function isclosed(c)
    return c:getfd() == -1 or c:getfd() == (2^32-1)
end

function active_close()
    reconnect()
    if isclosed(data) then fail("should not be closed") end
    data:close()
    if not isclosed(data) then fail("should be closed") end
    data = nil
    local udp = socket.udp()
    if isclosed(udp) then fail("should not be closed") end
    udp:close()
    if not isclosed(udp) then fail("should be closed") end
    pass("ok")
end

------------------------------------------------------------------------
function test_closed()
    local back, err
    local str = 'little string'
    reconnect()
    pass("trying read detection")
    remote (string.format ([[
        data:send('%s')
        data:close()
        data = nil
    ]], str))
    -- try to get a line 
    back, err = data:receive()
    if not err then fail("shold have gotten 'closed'.")
    elseif err ~= "closed" then fail("got '"..err.."' instead of 'closed'.")
    elseif str ~= back then fail("didn't receive partial result.")
    else pass("graceful 'closed' received") end
    reconnect()
    pass("trying write detection")
    remote [[
        data:close()
        data = nil
    ]]
    total, err = data:send(string.rep("ugauga", 100000))
    if not err then 
        pass("failed: output buffer is at least %d bytes long!", total)
    elseif err ~= "closed" then 
        fail("got '"..err.."' instead of 'closed'.")
    else 
        pass("graceful 'closed' received after %d bytes were sent", total) 
    end
end

------------------------------------------------------------------------
function test_selectbugs()
    local r, s, e = socket.select(nil, nil, 0.1)
    assert(type(r) == "table" and type(s) == "table" and e == "timeout")
    pass("both nil: ok")
    local udp = socket.udp()
    udp:close()
    r, s, e = socket.select({ udp }, { udp }, 0.1)
    assert(type(r) == "table" and type(s) == "table" and e == "timeout")
    pass("closed sockets: ok")
    e = pcall(socket.select, "wrong", 1, 0.1)
    assert(e == false)
    e = pcall(socket.select, {}, 1, 0.1)
    assert(e == false)
    pass("invalid input: ok")
end

------------------------------------------------------------------------
function accept_timeout()
    io.write("accept with timeout (if it hangs, it failed): ")
    local s, e = socket.bind("*", 0, 0)
    assert(s, e)
    local t = socket.time()
    s:settimeout(1)
    local c, e = s:accept()
    assert(not c, "should not accept") 
    assert(e == "timeout", string.format("wrong error message (%s)", e))
    t = socket.time() - t
    assert(t < 2, string.format("took to long to give up (%gs)", t))
    s:close()
    pass("good")
end

------------------------------------------------------------------------
function connect_timeout()
    io.write("connect with timeout (if it hangs, it failed): ")
    local c, e = socket.tcp()
    assert(c, e)
    c:settimeout(0.1)
    ip = socket.dns.toip("ibere.tecgraf.puc-rio.br")
    if not ip then return end
    local t = socket.time()
    local r, e = c:connect(ip, 80)
    assert(not r, "should not connect")
    assert(e == "timeout", e)
    assert(socket.time() - t < 2, "took too long to give up.") 
    c:close()
end

------------------------------------------------------------------------
function accept_errors()
    io.write("not listening: ")
    local d, e = socket.bind("*", 0)
    assert(d, e);
    local c, e = socket.tcp();
    assert(c, e);
    d:setfd(c:getfd())
    local r, e = d:accept()
    assert(not r and e == "not listening", e)
    print("ok")
    io.write("not supported: ")
    local c, e = socket.udp()
    assert(c, e);
    d:setfd(c:getfd())
    local r, e = d:accept()
    assert(not r and e == "not supported" or e == "not listening", e)
    print("ok")
end

------------------------------------------------------------------------
function connect_errors()
    io.write("connection refused: ")
    local c, e = socket.connect("localhost", 1);
    assert(not c and e == "connection refused", e)
    print("ok")
    io.write("host not found: ")
    local c, e = socket.connect("not.exist.com", 1);
    assert(not c and e == "host not found", e)
    print("ok")
end

------------------------------------------------------------------------
function rebind_test()
    local c = socket.bind("localhost", 0)
    local i, p = c:getsockname()
    local s, e = socket.tcp()
    assert(s, e)
    s:setoption("reuseaddr", false)
    r, e = s:bind("localhost", p)
    assert(not r, "managed to rebind!")
    assert(e == "address already in use")
    print("ok")
end

------------------------------------------------------------------------
test("method registration")
test_methods(socket.tcp(), {
   "accept",
    "bind",
    "close",
    "connect",
    "getpeername",
    "getsockname",
    "listen",
    "receive",
    "send",
    "setoption",
    "setpeername",
    "setsockname",
    "settimeout",
    "shutdown",
})

test_methods(socket.udp(), {
    "close", 
    "getpeername",
    "getsockname",
    "receive", 
    "receivefrom", 
    "send", 
    "sendto", 
    "setoption",
    "setpeername",
    "setsockname",
    "settimeout", 
    "shutdown",
})

test("select function")
test_selectbugs()

test("connect function")
connect_timeout()
empty_connect()
connect_errors()

test("rebinding: ")
rebind_test()

test("active close: ")
active_close()

test("closed connection detection: ")
test_closed()

test("accept function: ")
accept_timeout()
accept_errors()


test("mixed patterns")
test_mixed(1)
test_mixed(17)
test_mixed(200)
test_mixed(4091)
test_mixed(801990)
test_mixed(4091)
test_mixed(200)
test_mixed(17)
test_mixed(1)

test("character line")
test_asciiline(1)
test_asciiline(17)
test_asciiline(200)
test_asciiline(4091)
test_asciiline(80199)
test_asciiline(8000000)
test_asciiline(80199)
test_asciiline(4091)
test_asciiline(200)
test_asciiline(17)
test_asciiline(1)

test("binary line")
reconnect()
test_rawline(1)
test_rawline(17)
test_rawline(200)
test_rawline(4091)
test_rawline(80199)
test_rawline(8000000)
test_rawline(80199)
test_rawline(4091)
test_rawline(200)
test_rawline(17)
test_rawline(1)

test("raw transfer")
reconnect()
test_raw(1)
test_raw(17)
test_raw(200)
test_raw(4091)
test_raw(80199)
test_raw(8000000)
test_raw(80199)
test_raw(4091)
test_raw(200)
test_raw(17)
test_raw(1)

test("non-blocking transfer")
reconnect()
-- the value is not important, we only want 
-- to test non-blockin I/O anyways
data:settimeout(200)
test_raw(1)
test_raw(17)
test_raw(200)
test_raw(4091)
test_raw(80199)
test_raw(8000000)
test_raw(80199)
test_raw(4091)
test_raw(200)
test_raw(17)
test_raw(1)

test("total timeout on send")
test_totaltimeoutsend(800091, 1, 3)
test_totaltimeoutsend(800091, 2, 3)
test_totaltimeoutsend(800091, 3, 2)
test_totaltimeoutsend(800091, 3, 1)

test("total timeout on receive")
test_totaltimeoutreceive(800091, 1, 3)
test_totaltimeoutreceive(800091, 2, 3)
test_totaltimeoutreceive(800091, 3, 2)
test_totaltimeoutreceive(800091, 3, 1)

test("blocking timeout on send")
test_blockingtimeoutsend(800091, 1, 3)
test_blockingtimeoutsend(800091, 2, 3)
test_blockingtimeoutsend(800091, 3, 2)
test_blockingtimeoutsend(800091, 3, 1)

test("blocking timeout on receive")
test_blockingtimeoutreceive(800091, 1, 3)
test_blockingtimeoutreceive(800091, 2, 3)
test_blockingtimeoutreceive(800091, 3, 2)
test_blockingtimeoutreceive(800091, 3, 1)

test(string.format("done in %.2fs", socket.time() - start))
