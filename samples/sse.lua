-----------------------------------------------------------------------------
-- Server-Sent Events (SSE) demo client
-- LuaSocket sample files
--
-- Usage: lua sse.lua [<url>] [<event-count>]
-- Both arguments are positional and optional; with none given, connects to
-- a public live test feed and stops after 5 events.
-----------------------------------------------------------------------------
local http = require("socket.http")
local sse = require("socket.sse")

-- default target: Wikimedia's public, continuously-streaming recent-changes
-- feed -- a real, live text/event-stream endpoint, handy for trying out
-- socket.sse without standing up a server of your own
local DEFAULT_URL = "https://stream.wikimedia.org/v2/stream/recentchange"
local DEFAULT_LIMIT = 5

-- shortens a long data payload for readable terminal output
local function preview(text, limit)
    limit = limit or 100
    if #text > limit then return string.sub(text, 1, limit) .. "..." end
    return text
end

-- builds a message callback that prints each received Message, then stops
-- the stream once "limit" of them have been printed. This module parses a
-- single request/response and never reconnects on its own (see
-- docs/adr/0001-sse-single-shot-no-auto-reconnect.md), so a caller who wants
-- to stop early just does what we do here: return an error from the
-- callback, which ends the request the same way any sink error would
local function makeprinter(limit)
    local count = 0
    return function(message)
        count = count + 1
        io.write(string.format("[%d] event=%s id=%s\n    data=%s\n",
            count, message.event, tostring(message.id), preview(message.data)))
        if count >= limit then
            return nil, string.format("stopped after %d events", limit)
        end
        return 1
    end
end

-- main program
arg = arg or {}
local url = arg[1] or DEFAULT_URL
local limit = tonumber(arg[2]) or DEFAULT_LIMIT

io.write("connecting to ", url, " (stopping after ", limit, " events)\n")
local ok, code = http.request{
    url = url,
    headers_callback = sse.responseheaders(makeprinter(limit))
}

if ok then
    -- the server closed the connection on its own before we hit our limit
    io.write("connection closed by server, code=", tostring(code), "\n")
else
    -- once the callback above returns an error, http.request reports it the
    -- same way it reports any failure: (nil, message) -- so "code" here is
    -- really our own "stopped after N events" message, not a real error
    io.write(code, "\n")
end
