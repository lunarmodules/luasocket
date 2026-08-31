local socket = require("socket")
local sse = require("socket.sse")

dofile("testsupport.lua")

-- collects everything a parser sink dispatches to it (Messages and, when
-- enabled, Comments) into an ordered list; the "collect" name signals it
-- passes through unchanged rather than transforming
local function collect()
    local list = {}
    local snk = function(item, err)
        if err then return nil, err end
        table.insert(list, item)
        return 1
    end
    return snk, list
end

-- feeds a parser sink the given raw chunks, then signals end of stream
local function feed(parser, ...)
    for _, chunk in ipairs({...}) do
        local ok, err = parser(chunk)
        if not ok then return nil, err end
    end
    return parser(nil)
end

--------------------------------
io.write("testing event/data/id parsing on a single Message, retry line consumed but not attached: ")
do
    local snk, list = collect()
    local parser = sse.parser(snk)
    local ok = feed(parser,
        "event: greeting\r\n" ..
        "data: hello\r\n" ..
        "id: 1\r\n" ..
        "retry: 3000\r\n" ..
        "\r\n")
    assert(ok, "parser returned error")
    assert(#list == 1, "expected exactly one message")
    assert(list[1].event == "greeting", "wrong event")
    assert(list[1].data == "hello", "wrong data")
    assert(list[1].id == "1", "wrong id")
    assert(list[1].retry == nil, "Message must not carry a retry field; retry only lives on the context table")
    print("ok")
end

--------------------------------
io.write("testing multiple data: lines are joined with \\n: ")
do
    local snk, list = collect()
    local parser = sse.parser(snk)
    local ok = feed(parser, "data: line one\ndata: line two\ndata: line three\n\n")
    assert(ok, "parser returned error")
    assert(#list == 1, "expected exactly one message")
    assert(list[1].data == "line one\nline two\nline three", "data not joined correctly: " .. list[1].data)
    print("ok")
end

--------------------------------
io.write("testing event defaults to 'message' when omitted: ")
do
    local snk, list = collect()
    local parser = sse.parser(snk)
    local ok = feed(parser, "data: no event here\n\n")
    assert(ok, "parser returned error")
    assert(#list == 1, "expected exactly one message")
    assert(list[1].event == "message", "expected default event type, got " .. tostring(list[1].event))
    print("ok")
end

--------------------------------
io.write("testing id persists forward onto later Messages: ")
do
    local snk, list = collect()
    local parser = sse.parser(snk)
    local ok = feed(parser,
        "id: abc\ndata: first\n\n" ..
        "data: second\n\n" ..
        "id: def\ndata: third\n\n" ..
        "data: fourth\n\n")
    assert(ok, "parser returned error")
    assert(#list == 4, "expected four messages, got " .. #list)
    assert(list[1].id == "abc", "message 1 id")
    assert(list[2].id == "abc", "message 2 id should persist from message 1")
    assert(list[3].id == "def", "message 3 id")
    assert(list[4].id == "def", "message 4 id should persist from message 3")
    print("ok")
end

--------------------------------
io.write("testing comment lines are silently absorbed when comments is off: ")
do
    local snk, list = collect()
    local parser = sse.parser(snk)
    local ok = feed(parser, ": this is a comment\ndata: real message\n\n")
    assert(ok, "parser returned error")
    assert(#list == 1, "expected only the message, comment should be absorbed")
    assert(list[1].data == "real message", "wrong data")
    print("ok")
end

--------------------------------
io.write("testing comment lines are dispatched distinctly when comments is on: ")
do
    local snk, list = collect()
    local parser = sse.parser(snk, { comments = true })
    local ok = feed(parser, ": keep-alive\ndata: real message\n\n")
    assert(ok, "parser returned error")
    assert(#list == 2, "expected comment and message, got " .. #list)
    assert(list[1].comment == "keep-alive", "wrong comment text: " .. tostring(list[1].comment))
    assert(list[1].event == nil, "comment must not look like a message")
    assert(list[2].data == "real message", "wrong data")
    print("ok")
end

--------------------------------
io.write("testing context table gets last_event_id/retry written and retains them after parsing ends: ")
do
    local snk = collect()
    local context = {}
    local parser = sse.parser(snk, { context = context })
    local ok = feed(parser, "id: xyz\nretry: 5000\ndata: hi\n\n")
    assert(ok, "parser returned error")
    assert(context.last_event_id == "xyz", "context.last_event_id not written")
    assert(context.retry == 5000, "context.retry not written")
    print("ok")
end

--------------------------------
io.write("testing context.retry persists across later events that don't repeat it, and no Message ever carries a retry field: ")
do
    local snk, list = collect()
    local context = {}
    local parser = sse.parser(snk, { context = context })
    local ok = feed(parser,
        "retry: 2000\ndata: first\n\n" ..
        "data: second\n\n")
    assert(ok, "parser returned error")
    assert(#list == 2, "expected two messages, got " .. #list)
    assert(list[1].retry == nil, "message 1 must not carry a retry field")
    assert(list[2].retry == nil, "message 2 must not carry a retry field")
    assert(context.retry == 2000, "context.retry should still reflect the most recent retry hint after a later event that didn't repeat it")
    print("ok")
end

--------------------------------
io.write("testing an oversized line produces a distinct error and aborts: ")
do
    local snk, list = collect()
    local parser = sse.parser(snk)
    local huge = string.rep("x", sse.MAXLINESIZE + 1)
    local ok, err = feed(parser, "data: " .. huge .. "\n\n")
    assert(not ok, "expected parser to fail on oversized line")
    assert(err == "oversized", "expected 'oversized' error, got " .. tostring(err))
    assert(#list == 0, "no message should have been dispatched")
    print("ok")
end

--------------------------------
io.write("testing an oversized event (many lines under MAXEVENTSIZE total) produces a distinct error: ")
do
    local snk, list = collect()
    local parser = sse.parser(snk)
    local line = "data: " .. string.rep("y", 100) .. "\n"
    local lines = string.rep(line, math.ceil(sse.MAXEVENTSIZE / #line) + 1)
    local ok, err = feed(parser, lines)
    assert(not ok, "expected parser to fail on oversized event")
    assert(err == "oversized", "expected 'oversized' error, got " .. tostring(err))
    assert(#list == 0, "no message should have been dispatched")
    print("ok")
end

--------------------------------
io.write("testing a field split across two raw-byte chunks is parsed correctly: ")
do
    local snk, list = collect()
    local parser = sse.parser(snk)
    -- split mid field-name, mid value, and mid line-terminator
    local ok = feed(parser, "eve", "nt: greet", "ing\ndata: hel", "lo\r", "\n\r\n")
    assert(ok, "parser returned error")
    assert(#list == 1, "expected exactly one message, got " .. #list)
    assert(list[1].event == "greeting", "wrong event: " .. tostring(list[1].event))
    assert(list[1].data == "hello", "wrong data: " .. tostring(list[1].data))
    print("ok")
end

--------------------------------
io.write("testing a Message-sink error aborts the parser sink chain: ")
do
    local calls = 0
    local snk = function(message)
        calls = calls + 1
        if calls == 1 then return 1 end
        return nil, "sink refused message"
    end
    local parser = sse.parser(snk)
    local ok, err = feed(parser, "data: first\n\ndata: second\n\n")
    assert(not ok, "expected parser to propagate message sink error")
    assert(err == "sink refused message", "unexpected error: " .. tostring(err))
    assert(calls == 2, "expected the sink to be invoked twice")
    print("ok")
end

--------------------------------
io.write("testing a Message with no data: line is not dispatched: ")
do
    local snk, list = collect()
    local parser = sse.parser(snk)
    local ok = feed(parser, "event: ping\nid: 1\n\ndata: real\n\n")
    assert(ok, "parser returned error")
    assert(#list == 1, "the dataless block should not have produced a message")
    assert(list[1].data == "real", "wrong data")
    print("ok")
end

--------------------------------
io.write("testing callbacksink lets a plain callback act as a message sink: ")
do
    local received = {}
    local callback = function(message) table.insert(received, message); return true end
    local snk = sse.callbacksink(callback)
    local parser = sse.parser(snk)
    local ok = feed(parser, "data: first\n\ndata: second\n\n")
    assert(ok, "parser returned error")
    assert(#received == 2, "expected two messages, got " .. #received)
    assert(received[1].data == "first", "wrong data")
    assert(received[2].data == "second", "wrong data")
    print("ok")
end

--------------------------------
io.write("testing callbacksink propagates an error returned by the callback: ")
do
    local calls = 0
    local callback = function(message)
        calls = calls + 1
        if message.data == "bad" then return nil, "callback refused" end
        return true
    end
    local snk = sse.callbacksink(callback)
    local parser = sse.parser(snk)
    local ok, err = feed(parser, "data: good\n\ndata: bad\n\ndata: unreachable\n\n")
    assert(not ok, "expected callback error to abort the chain")
    assert(err == "callback refused", "unexpected error: " .. tostring(err))
    assert(calls == 2, "expected the callback to stop being invoked after it errors, got " .. calls)
    print("ok")
end

--------------------------------
io.write("testing callbacksink does not swallow a sink that fails with a falsy ok and no error message: ")
do
    local calls = 0
    local rawsink = function(message)
        calls = calls + 1
        if message.data == "bad" then return false end
        return 1
    end
    local snk = sse.callbacksink(rawsink)
    local parser = sse.parser(snk)
    local ok, err = feed(parser, "data: good\n\ndata: bad\n\ndata: unreachable\n\n")
    assert(not ok, "expected the falsy ok to abort the chain even without an error message")
    assert(err == nil, "no error message was given, so none should be invented")
    assert(calls == 2, "expected the sink to stop being invoked once it fails, got " .. calls)
    print("ok")
end

--------------------------------
io.write("testing callbacksink treats a callback that returns nothing as an error, not a default success: ")
do
    local snk = sse.callbacksink(function(message) end)
    local parser = sse.parser(snk)
    local ok = feed(parser, "data: hi\n\n")
    assert(not ok, "a callback must explicitly return truthy to signal success, matching a raw sink's contract")
    print("ok")
end

--------------------------------
io.write("testing responseheaders forwards its config (context/comments) to the parser: ")
do
    local received = {}
    local context = {}
    local factory = sse.responseheaders(
        function(message) table.insert(received, message); return true end,
        { comments = true, context = context })
    local ok, sink = factory(200, { ["content-type"] = "text/event-stream" }, "HTTP/1.1 200 OK")
    assert(ok, "expected success")
    local fed = feed(sink, ": keep-alive\nid: xyz\ndata: hello\n\n")
    assert(fed, "sink chain returned an error")
    assert(#received == 2, "expected the comment and the message, got " .. #received)
    assert(received[1].comment == "keep-alive", "comments config was not forwarded to the parser")
    assert(context.last_event_id == "xyz", "context table was not forwarded to the parser")
    print("ok")
end

--------------------------------
io.write("testing responseheaders installs the sink chain on a matching Content-Type: ")
do
    local received = {}
    local factory = sse.responseheaders(function(message) table.insert(received, message); return true end)
    local reqt = {}
    reqt.headers_callback = factory
    local ok, sink = reqt.headers_callback(200, { ["content-type"] = "text/event-stream" }, "HTTP/1.1 200 OK")
    assert(ok, "expected success on a matching content-type")
    assert(type(sink) == "function", "expected a sink function on a matching content-type")
    reqt.sink = sink
    local fed = feed(reqt.sink, "data: hello\n\n")
    assert(fed, "sink chain returned an error")
    assert(#received == 1, "expected one message dispatched through the installed sink")
    assert(received[1].data == "hello", "wrong data")
    print("ok")
end

--------------------------------
io.write("testing responseheaders also accepts a raw ltn12-style message sink directly: ")
do
    local received = {}
    -- a raw sink following full ltn12 protocol: truthy on success, (nil, err) on failure
    local rawsink = function(message)
        table.insert(received, message)
        return 1
    end
    local factory = sse.responseheaders(rawsink)
    local ok, sink = factory(200, { ["content-type"] = "text/event-stream" }, "HTTP/1.1 200 OK")
    assert(ok, "expected success")
    local fed = feed(sink, "data: raw\n\n")
    assert(fed, "sink chain returned an error")
    assert(#received == 1, "expected one message")
    assert(received[1].data == "raw", "wrong data")
    print("ok")
end

--------------------------------
io.write("testing responseheaders matches a Content-Type with trailing parameters: ")
do
    local factory = sse.responseheaders(function() end)
    local ok, sink = factory(200, { ["content-type"] = "text/event-stream; charset=utf-8" }, "HTTP/1.1 200 OK")
    assert(ok, "expected success")
    assert(type(sink) == "function", "expected a sink for a parameterized but matching content-type")
    print("ok")
end

--------------------------------
io.write("testing responseheaders declines cleanly on a non-matching Content-Type: ")
do
    local calledback = false
    local factory = sse.responseheaders(function() calledback = true end)
    local reqt = { sink = "original sink placeholder" }
    local ok, sink = factory(200, { ["content-type"] = "text/html" }, "HTTP/1.1 200 OK")
    assert(ok, "a non-matching content-type must still succeed (just decline the sink swap)")
    assert(sink == nil, "a non-matching content-type must not offer a sink swap")
    -- mirror what http.lua does with the factory's return values, to prove
    -- the caller's existing sink survives untouched
    if sink then reqt.sink = sink end
    assert(reqt.sink == "original sink placeholder", "existing sink must be left untouched")
    assert(not calledback, "message callback must not fire for a non-matching content-type")
    print("ok")
end

--------------------------------
io.write("testing responseheaders declines cleanly when Content-Type is missing: ")
do
    local factory = sse.responseheaders(function() end)
    local ok, sink = factory(200, {}, "HTTP/1.1 200 OK")
    assert(ok, "missing content-type must still succeed (just decline the sink swap)")
    assert(sink == nil, "missing content-type must not offer a sink swap")
    print("ok")
end

print("the library passed all tests")
