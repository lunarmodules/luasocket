HOST = HOST or "localhost"
PORT = PORT or "8080"

function pass(...)
    local s = call(format, arg)
    write(s, "\n")
end

function fail(...)
    local s = call(format, arg)
    write("ERROR: ", s, "!\n")
    exit()
end

function warn(...)
    local s = call(format, arg)
    write("WARNING: ", s, "\n")
end

function remote(...)
    local s = call(format, arg)
    s = gsub(s, "\n", ";")
    s = gsub(s, "%s+", " ")
    s = gsub(s, "^%s*", "")
    control:send(s, "\n")
    control:receive()
end

function test(test)
    write("----------------------------------------------\n",
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
        if mode == "return" then
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

write("----------------------------------------------\n",
"LuaSocket Test Procedures\n",
"----------------------------------------------\n")

if not _time or not _sleep then fail("not compiled with _DEBUG") end

start = _time()

function tcpreconnect()
    write("attempting data connection... ")
    if data then data:close() end
    remote [[
        if data then data:close() data = nil end
        data = server:accept()
    ]]
    data, error = connect(HOST, PORT)
    if not data then fail(error) 
    else pass("connected!") end
end
reconnect = tcpreconnect

pass("attempting control connection...")
control, error = connect(HOST, PORT)
if error then fail(error)
else pass("connected!") end

------------------------------------------------------------------------
test("bugs")

write("empty host connect: ")
function empty_connect()
    if data then data:close() data = nil end
    remote [[
        if data then data:close() data = nil end
        data = server:accept()
    ]]
    data, err = connect("", PORT)
    if not data then 
        pass("ok")
        data = connect(HOST, PORT)
    else fail("should not have connected!") end
end

empty_connect()

------------------------------------------------------------------------
test("method registration")

function test_methods(sock, methods)
    for _, v in methods do
        if type(sock[v]) ~= "function" then 
            fail(type(sock) .. " method " .. v .. "not registered") 
        end
    end
    pass(type(sock) .. " methods are ok")
end

test_methods(control, {
    "close", 
    "timeout", 
    "send", 
    "receive", 
    "getpeername",
    "getsockname"
})

if udpsocket then
    test_methods(udpsocket(), {
        "close", 
        "timeout", 
        "send", 
        "sendto", 
        "receive", 
        "receivefrom", 
        "getpeername",
        "getsockname",
        "setsockname",
        "setpeername"
    })
end

test_methods(bind("*", 0), {
    "close", 
    "timeout", 
    "accept" 
})

if pipe then
    local p1, p2 = pipe()
    test_methods(p1, {
        "close", 
        "timeout", 
        "send",
        "receive" 
    })
    test_methods(p2, {
        "close", 
        "timeout", 
        "send",
        "receive" 
    })
end

if filesocket then
    test_methods(filesocket(0), {
        "close", 
        "timeout", 
        "send",
        "receive" 
    })
end

------------------------------------------------------------------------
test("select function")
function test_selectbugs()
    local r, s, e = select(nil, nil, 0.1)
    assert(type(r) == "table" and type(s) == "table" and e == "timeout")
    pass("both nil: ok")
    local udp = udpsocket()
    udp:close()
    r, s, e = select({ data }, { data }, 0.1)
    assert(type(r) == "table" and type(s) == "table" and e == "timeout")
    pass("closed sockets: ok")
    e = call(select, {"wrong", 1, 0.1}, "x", nil)
    assert(e == nil)
    pass("invalid input: ok")
end

test_selectbugs()

------------------------------------------------------------------------
test("character line")
reconnect()

function test_asciiline(len)
    local str, str10, back, err
    str = strrep("x", mod(len, 10))
    str10 = strrep("aZb.c#dAe?", floor(len/10))
    str = str .. str10
    pass(len .. " byte(s) line")
remote "str = data:receive()"
    err = data:send(str, "\n")
    if err then fail(err) end
remote "data:send(str, '\\n')"
    back, err = data:receive()
    if err then fail(err) end
    if back == str then pass("lines match")
    else fail("lines don't match") end
end

test_asciiline(1)
test_asciiline(17)
test_asciiline(200)
test_asciiline(4091)
test_asciiline(80199)
test_asciiline(800000)

------------------------------------------------------------------------
test("binary line")
reconnect()

function test_rawline(len)
    local str, str10, back, err
    str = strrep(strchar(47), mod(len, 10))
    str10 = strrep(strchar(120,21,77,4,5,0,7,36,44,100), floor(len/10))
    str = str .. str10
    pass(len .. " byte(s) line")
remote "str = data:receive()"
    err = data:send(str, "\n")
    if err then fail(err) end
remote "data:send(str, '\\n')"
    back, err = data:receive()
    if err then fail(err) end
    if back == str then pass("lines match")
    else fail("lines don't match") end
end

test_rawline(1)
test_rawline(17)
test_rawline(200)
test_rawline(4091)
test_rawline(80199)
test_rawline(800000)
test_rawline(80199)
test_rawline(4091)
test_rawline(200)
test_rawline(17)
test_rawline(1)

------------------------------------------------------------------------
test("raw transfer")
reconnect()

function test_raw(len)
    local half = floor(len/2)
    local s1, s2, back, err
    s1 = strrep("x", half)
    s2 = strrep("y", len-half)
    pass(len .. " byte(s) block")
remote (format("str = data:receive(%d)", len))
    err = data:send(s1)
    if err then fail(err) end
    err = data:send(s2)
    if err then fail(err) end
remote "data:send(str)"
    back, err = data:receive(len)
    if err then fail(err) end
    if back == s1..s2 then pass("blocks match")
    else fail("blocks don't match") end
end

test_raw(1)
test_raw(17)
test_raw(200)
test_raw(4091)
test_raw(80199)
test_raw(800000)
test_raw(80199)
test_raw(4091)
test_raw(200)
test_raw(17)
test_raw(1)
------------------------------------------------------------------------
test("non-blocking transfer")
reconnect()

-- the value is not important, we only want 
-- to test non-blockin I/O anyways
data:timeout(200)
test_raw(1)
test_raw(17)
test_raw(200)
test_raw(4091)
test_raw(80199)
test_raw(800000)
test_raw(80199)
test_raw(4091)
test_raw(200)
test_raw(17)
test_raw(1)

------------------------------------------------------------------------
test("mixed patterns")
reconnect()

function test_mixed(len)
    local inter = floor(len/3)
    local p1 = "unix " .. strrep("x", inter) .. "line\n"
    local p2 = "dos " .. strrep("y", inter) .. "line\r\n"
    local p3 = "raw " .. strrep("z", inter) .. "bytes"
    local bp1, bp2, bp3
    pass(len .. " byte(s) patterns")
remote (format("str = data:receive(%d)", strlen(p1)+strlen(p2)+strlen(p3)))
    err = data:send(p1, p2, p3)
    if err then fail(err) end
remote "data:send(str)"
    bp1, bp2, bp3, err = data:receive("*lu", "*l", strlen(p3))
    if err then fail(err) end
    if bp1.."\n" == p1 and bp2.."\r\n" == p2 and bp3 == p3 then
        pass("patterns match")
    else fail("patterns don't match") end
end

test_mixed(1)
test_mixed(17)
test_mixed(200)
test_mixed(4091)
test_mixed(80199)
test_mixed(800000)
test_mixed(80199)
test_mixed(4091)
test_mixed(200)
test_mixed(17)
test_mixed(1)

------------------------------------------------------------------------
test("closed connection detection")

function test_closed()
    local back, err
    local str = 'little string'
    reconnect()
    pass("trying read detection")
    remote (format ([[
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
    err, total = data:send(strrep("ugauga", 100000))
    if not err then 
pass("failed: output buffer is at least %d bytes long!", total)
    elseif err ~= "closed" then 
fail("got '"..err.."' instead of 'closed'.")
    else 
pass("graceful 'closed' received after %d bytes were sent", total) 
    end
end

test_closed()

------------------------------------------------------------------------
test("return timeout on receive")
function test_blockingtimeoutreceive(len, tm, sl)
    local str, err, total
    reconnect()
    pass("%d bytes, %ds return timeout, %ds pause", len, tm, sl)
    remote (format ([[
        data:timeout(%d)
        str = strrep('a', %d)
        data:send(str)
        print('server: sleeping for %ds')
        _sleep(%d)
        print('server: woke up')
        data:send(str)
    ]], 2*tm, len, sl, sl))
    data:timeout(tm, "return")
    str, err, elapsed = data:receive(2*len)
    check_timeout(tm, sl, elapsed, err, "receive", "return", 
        strlen(str) == 2*len)
end
test_blockingtimeoutreceive(800091, 1, 3)
test_blockingtimeoutreceive(800091, 2, 3)
test_blockingtimeoutreceive(800091, 3, 2)
test_blockingtimeoutreceive(800091, 3, 1)

------------------------------------------------------------------------
test("return timeout on send")
function test_returntimeoutsend(len, tm, sl)
    local str, err, total
    reconnect()
    pass("%d bytes, %ds return timeout, %ds pause", len, tm, sl)
    remote (format ([[
        data:timeout(%d)
        str = data:receive(%d)
        print('server: sleeping for %ds')
        _sleep(%d)
        print('server: woke up')
        str = data:receive(%d)
    ]], 2*tm, len, sl, sl, len))
    data:timeout(tm, "return")
    str = strrep("a", 2*len)
    err, total, elapsed = data:send(str)
    check_timeout(tm, sl, elapsed, err, "send", "return", 
        total == 2*len)
end
test_returntimeoutsend(800091, 1, 3)
test_returntimeoutsend(800091, 2, 3)
test_returntimeoutsend(800091, 3, 2)
test_returntimeoutsend(800091, 3, 1)


------------------------------------------------------------------------
test("blocking timeout on receive")
function test_blockingtimeoutreceive(len, tm, sl)
    local str, err, total
    reconnect()
    pass("%d bytes, %ds blocking timeout, %ds pause", len, tm, sl)
    remote (format ([[
        data:timeout(%d)
        str = strrep('a', %d)
        data:send(str)
        print('server: sleeping for %ds')
        _sleep(%d)
        print('server: woke up')
        data:send(str)
    ]], 2*tm, len, sl, sl))
    data:timeout(tm)
    str, err, elapsed = data:receive(2*len)
    check_timeout(tm, sl, elapsed, err, "receive", "blocking", 
        strlen(str) == 2*len)
end
test_blockingtimeoutreceive(800091, 1, 3)
test_blockingtimeoutreceive(800091, 2, 3)
test_blockingtimeoutreceive(800091, 3, 2)
test_blockingtimeoutreceive(800091, 3, 1)


------------------------------------------------------------------------
test("blocking timeout on send")
function test_blockingtimeoutsend(len, tm, sl)
    local str, err, total
    reconnect()
    pass("%d bytes, %ds blocking timeout, %ds pause", len, tm, sl)
    remote (format ([[
        data:timeout(%d)
        str = data:receive(%d)
        print('server: sleeping for %ds')
        _sleep(%d)
        print('server: woke up')
        str = data:receive(%d)
    ]], 2*tm, len, sl, sl, len))
    data:timeout(tm)
    str = strrep("a", 2*len)
    err, total, elapsed = data:send(str)
    check_timeout(tm, sl, elapsed, err, "send", "blocking",
        total == 2*len)
end
test_blockingtimeoutsend(800091, 1, 3)
test_blockingtimeoutsend(800091, 2, 3)
test_blockingtimeoutsend(800091, 3, 2)
test_blockingtimeoutsend(800091, 3, 1)

------------------------------------------------------------------------
test(format("done in %.2fs", _time() - start))
