-----------------------------------------------------------------------------
-- Server-Sent Events (SSE) parsing support for the Lua language.
-- LuaSocket toolkit.
-----------------------------------------------------------------------------

-----------------------------------------------------------------------------
-- Declare module and import dependencies
-----------------------------------------------------------------------------
local socket = require("socket")
local string = require("string")
socket.sse = {}
local _M = socket.sse

-----------------------------------------------------------------------------
-- Program constants
-----------------------------------------------------------------------------
-- maximum size of a single SSE line
_M.MAXLINESIZE = 8192
-- maximum total size of all lines making up a single event/comment block
_M.MAXEVENTSIZE = 65536

-----------------------------------------------------------------------------
-- Strips a single leading space, per the SSE field-value trimming rule
-----------------------------------------------------------------------------
local function striponeleadingspace(value)
    if string.sub(value, 1, 1) == " " then return string.sub(value, 2) end
    return value
end

-----------------------------------------------------------------------------
-- Parses one SSE field line ("name: value", "name:value" or "name") into
-- its name/value pair
-----------------------------------------------------------------------------
local function parsefield(line)
    local colon = string.find(line, ":", 1, true)
    if not colon then return line, "" end
    local name = string.sub(line, 1, colon - 1)
    local value = striponeleadingspace(string.sub(line, colon + 1))
    return name, value
end

-----------------------------------------------------------------------------
-- Builds a Parser sink: an ltn12 sink that consumes raw SSE response bytes
-- and dispatches parsed Messages (and, if enabled, Comments) to msgsink, a
-- Message sink. config is an optional table:
--   comments: boolean, dispatch Comments to msgsink when true (default false)
--   context: caller-owned table that last_event_id/retry get written into
-- as parsing progresses
-----------------------------------------------------------------------------
function _M.parser(msgsink, config)
    config = config or {}
    local comments = config.comments
    local context = config.context or {}

    local linebuffer = ""
    local eventsize = 0

    -- id persists across Messages that omit their own id: line, per spec,
    -- so it lives outside reset(); retry is a stream-level reconnection
    -- hint with no per-Message meaning at all, so it is tracked only on
    -- context.retry, never as event-local state
    local id
    local eventtype, data, hasdata

    local function reset()
        eventtype = nil
        data = nil
        hasdata = false
        eventsize = 0
    end
    reset()

    -- dispatches the current Message, if any data was accumulated for it,
    -- then resets event-local state for the next one
    local function dispatch()
        if not hasdata then
            reset()
            return 1
        end
        local message = {
            event = eventtype or "message",
            data = data,
            id = id,
        }
        reset()
        local ok, err = msgsink(message)
        if not ok then return nil, err end
        return 1
    end

    local function processline(line)
        if line == "" then return dispatch() end
        if string.sub(line, 1, 1) == ":" then
            if comments then
                local text = striponeleadingspace(string.sub(line, 2))
                local ok, err = msgsink({ comment = text })
                if not ok then return nil, err end
            end
            return 1
        end
        local name, value = parsefield(line)
        if name == "event" then
            eventtype = value
        elseif name == "data" then
            data = hasdata and (data .. "\n" .. value) or value
            hasdata = true
        elseif name == "id" then
            if not string.find(value, "\0", 1, true) then
                id = value
                context.last_event_id = id
            end
        elseif name == "retry" then
            if string.find(value, "^%d+$") then
                context.retry = tonumber(value)
            end
        end
        return 1
    end

    return function(chunk, err)
        if not chunk then
            if err then return nil, err end
            return 1
        end
        linebuffer = linebuffer .. chunk
        while true do
            local nl = string.find(linebuffer, "\n", 1, true)
            if not nl then
                if #linebuffer > _M.MAXLINESIZE then return nil, "oversized" end
                break
            end
            local line = string.sub(linebuffer, 1, nl - 1)
            linebuffer = string.sub(linebuffer, nl + 1)
            if #line > _M.MAXLINESIZE then return nil, "oversized" end
            if string.sub(line, -1) == "\r" then line = string.sub(line, 1, -2) end
            eventsize = eventsize + #line + 1
            if eventsize > _M.MAXEVENTSIZE then return nil, "oversized" end
            local ok, procerr = processline(line)
            if not ok then return nil, procerr end
        end
        return 1
    end
end

-----------------------------------------------------------------------------
-- The media type this module activates on, ignoring Content-Type parameters
-----------------------------------------------------------------------------
_M.EVENTSTREAMTYPE = "text/event-stream"

-----------------------------------------------------------------------------
-- Extracts the media type portion of a Content-Type header value, dropping
-- any trailing parameters (e.g. "; charset=utf-8") and normalizing case
-----------------------------------------------------------------------------
local function mediatype(contenttype)
    local mt = string.match(contenttype or "", "^%s*([^;%s]*)")
    return string.lower(mt or "")
end

-----------------------------------------------------------------------------
-- Wraps a plain function(message) ... end callback into a Message sink, so
-- it can be used anywhere one is expected. Follows the same contract as any
-- ltn12 sink: the callback must return a truthy value to signal success;
-- any falsy return is an error, propagated as-is (even with no err message)
-- rather than swallowed. A raw sink passed in here already speaks that
-- contract, so wrapping it is a no-op.
-----------------------------------------------------------------------------
function _M.callbacksink(callback)
    return function(message)
        local ok, err = callback(message)
        if not ok then return nil, err end
        return 1
    end
end

-----------------------------------------------------------------------------
-- Builds a function suitable for reqt.headers_callback: given (code,
-- headers, status), checks headers["content-type"] for the
-- text/event-stream media type (ignoring trailing parameters) and, only on
-- a match, offers a sink chaining the Parser sink (see _M.parser) to
-- msgsink -- a Message sink or a plain callback, per _M.callbacksink -- as
-- the request's sink. On no match, declines by returning true with no
-- sink, leaving http.request's own sink handling untouched.
-----------------------------------------------------------------------------
function _M.responseheaders(msgsink, config)
    return function(code, headers, status)
        if not headers or mediatype(headers["content-type"]) ~= _M.EVENTSTREAMTYPE then
            return true
        end
        return true, _M.parser(_M.callbacksink(msgsink), config)
    end
end

return _M
