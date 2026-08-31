-- Test fixture for exercising socket.http.request against a fully
-- controlled, scripted HTTP response -- no Apache, no Docker, no
-- third-party hosts. Built on top of the existing testsrvr.lua remote-
-- execution server (see test/testclnt.lua for the `remote()` protocol this
-- reuses): a control connection sends Lua snippets for testsrvr.lua to
-- `load()` and run, which is how it's told to accept the connection that
-- socket.http.request makes and write raw response bytes back to it.
local socket = require("socket")

local M = {}

M.host = "localhost"
M.port = "8383"

-- Connects to a running testsrvr.lua as a control channel and returns a
-- `remote(fmt, ...)` function that scripts a Lua snippet to run on the
-- server. Mirrors test/testclnt.lua's own remote(): the snippet is
-- squashed onto a single line (embedded newlines become ';', runs of
-- whitespace collapse to one space) since the control channel is
-- line-oriented, and the ack sent back is only proof the server received
-- the command, not that it finished running it -- so a snippet that blocks
-- (e.g. server:accept()) doesn't stall the caller.
function M.connect(host, port)
    local control = assert(socket.connect(host or M.host, port or M.port))
    control:setoption("tcp-nodelay", true)
    local function remote(fmt, ...)
        local s = string.format(fmt, ...)
        s = string.gsub(s, "\n", ";")
        s = string.gsub(s, "%s+", " ")
        s = string.gsub(s, "^%s*", "")
        assert(control:send(s .. "\n"))
        control:receive()
    end
    return control, remote
end

-- Turns a raw Lua string into a single-line, double-quoted Lua string
-- literal safe to embed in a remote()-scripted snippet: escapes backslash,
-- quote, and every whitespace control character so no byte in the
-- *encoded* text is itself whitespace. remote() collapses whitespace runs
-- and turns newlines into ';', which would otherwise corrupt raw response
-- bytes (status lines/headers/chunked framing all rely on literal CRLF).
local function quote(s)
    s = string.gsub(s, "\\", "\\\\")
    s = string.gsub(s, "\"", "\\\"")
    s = string.gsub(s, "\r", "\\r")
    s = string.gsub(s, "\n", "\\n")
    s = string.gsub(s, "\t", "\\t")
    return "\"" .. s .. "\""
end

-- Appends the script parts for one accept-send-close cycle (see
-- accept_and_send_sequence) onto `parts`.
local function append_connection(parts, chunks)
    parts[#parts + 1] = "if data then data:close() data = nil end"
    parts[#parts + 1] = "data = server:accept()"
    parts[#parts + 1] = "data:setoption(\"tcp-nodelay\", true)"
    for _, chunk in ipairs(chunks) do
        local body, delay
        if type(chunk) == "table" then
            body, delay = chunk[1], chunk.delay
        else
            body = chunk
        end
        if delay then
            parts[#parts + 1] = string.format("socket.sleep(%f)", delay)
        end
        parts[#parts + 1] = "data:send(" .. quote(body) .. ")"
    end
    parts[#parts + 1] = "data:close() data = nil"
end

-- Scripts the server to accept one connection (into the shared `data`
-- global, mirroring test/testclnt.lua's reconnect()), write a sequence of
-- raw byte chunks to it, then close it. `chunks` is an array of either
-- plain strings, or {body, delay = seconds} tables -- the delay (via
-- socket.sleep) is applied before sending that chunk, so callers can prove
-- incremental/partial delivery instead of one atomic send.
function M.accept_and_send(remote, chunks)
    local parts = {}
    append_connection(parts, chunks)
    remote(table.concat(parts, "\n"))
end

-- Like accept_and_send, but scripts several accept-send-close cycles as one
-- server-side script sent over a single remote() round trip. Needed for a
-- client call that opens more than one connection in sequence within a
-- single call of its own (e.g. socket.http.request following a redirect):
-- queuing a second accept_and_send for that connection ahead of time would
-- deadlock, since its remote() call can't get an ack until the server
-- finishes the first accept_and_send's blocking accept() -- which itself
-- can't complete until the client makes the very call that's stuck waiting
-- on that ack. `connections` is an array of `chunks` arrays, one per
-- connection, handled in order.
function M.accept_and_send_sequence(remote, connections)
    local parts = {}
    for _, chunks in ipairs(connections) do
        append_connection(parts, chunks)
    end
    remote(table.concat(parts, "\n"))
end

-- Builds a raw HTTP/1.1 response (status line + headers + body) as a
-- single CRLF-framed string, ready to hand to accept_and_send.
function M.response(status, headers, body)
    local lines = { "HTTP/1.1 " .. status }
    for _, h in ipairs(headers or {}) do
        lines[#lines + 1] = h
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = body or ""
    return table.concat(lines, "\r\n")
end

-- Encodes a list of body pieces as HTTP chunked-transfer-encoding, ending
-- with the terminating zero-size chunk. Saves callers from hand-rolling
-- the "<hex-size>\r\n<data>\r\n" framing for chunked test bodies.
function M.chunked(pieces)
    local out = {}
    for _, piece in ipairs(pieces) do
        out[#out + 1] = string.format("%x\r\n%s\r\n", #piece, piece)
    end
    out[#out + 1] = "0\r\n\r\n"
    return table.concat(out)
end

return M
