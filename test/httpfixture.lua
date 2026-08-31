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

-- Scripts the server to accept one connection (into the shared `data`
-- global, mirroring test/testclnt.lua's reconnect()), write a sequence of
-- raw byte chunks to it, then close it. `chunks` is an array of either
-- plain strings, or {body, delay = seconds} tables -- the delay (via
-- socket.sleep) is applied before sending that chunk, so callers can prove
-- incremental/partial delivery instead of one atomic send.
function M.accept_and_send(remote, chunks)
    local parts = {
        "if data then data:close() data = nil end",
        "data = server:accept()",
        "data:setoption(\"tcp-nodelay\", true)",
    }
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
