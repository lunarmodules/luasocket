-----------------------------------------------------------------------------
-- HTTP/1.1 client support for the Lua language.
-- LuaSocket toolkit.
-- Author: Diego Nehab
-- Conforming to: RFC 2616, LTN7
-- RCS ID: $Id$
-----------------------------------------------------------------------------
-- make sure LuaSocket is loaded
if not LUASOCKET_LIBNAME then error('module requires LuaSocket') end
-- get LuaSocket namespace
local socket = _G[LUASOCKET_LIBNAME] 
if not socket then error('module requires LuaSocket') end
-- create namespace inside LuaSocket namespace
socket.http  = socket.http or {}
-- make all module globals fall into namespace
setmetatable(socket.http, { __index = _G })
setfenv(1, socket.http)

-----------------------------------------------------------------------------
-- Program constants
-----------------------------------------------------------------------------
-- connection timeout in seconds
TIMEOUT = 60 
-- default port for document retrieval
PORT = 80
-- user agent field sent in request
USERAGENT = socket.version
-- block size used in transfers
BLOCKSIZE = 2048

-----------------------------------------------------------------------------
-- Function return value selectors
-----------------------------------------------------------------------------
local function second(a, b)
    return b
end

local function third(a, b, c)
    return c
end

local function shift(a, b, c, d)
    return c, d
end

-- resquest_p forward declaration
local request_p

local function receive_headers(sock, headers)
    local line, name, value
    -- get first line
    line = socket.try(sock:receive())
    -- headers go until a blank line is found
    while line ~= "" do
        -- get field-name and value
        name, value = shift(string.find(line, "^(.-):%s*(.*)"))
        assert(name and value, "malformed reponse headers")
        name = string.lower(name)
        -- get next line (value might be folded)
        line  = socket.try(sock:receive())
        -- unfold any folded values
        while string.find(line, "^%s") do
            value = value .. line
            line = socket.try(sock:receive())
        end
        -- save pair in table
        if headers[name] then headers[name] = headers[name] .. ", " .. value
        else headers[name] = value end
    end
end

local function abort(cb, err) 
    local go, cb_err = cb(nil, err)
    error(cb_err or err)
end

local function hand(cb, chunk) 
    local go, cb_err = cb(chunk)
    assert(go, cb_err or "aborted by callback")
end

local function receive_body_bychunks(sock, sink)
    while 1 do
        -- get chunk size, skip extention
        local line, err = sock:receive()
        if err then abort(sink, err) end
        local size = tonumber(string.gsub(line, ";.*", ""), 16)
        if not size then abort(sink, "invalid chunk size") end
        -- was it the last chunk?
        if size <= 0 then break end
        -- get chunk
        local chunk, err = sock:receive(size) 
        if err then abort(sink, err) end
        -- pass chunk to callback
        hand(sink, chunk) 
        -- skip CRLF on end of chunk
        err = second(sock:receive())
        if err then abort(sink, err) end
    end
    -- let callback know we are done
    hand(sink, nil)
    -- servers shouldn't send trailer headers, but who trusts them?
    receive_headers(sock, {})
end

local function receive_body_bylength(sock, length, sink)
    while length > 0 do
        local size = math.min(BLOCKSIZE, length)
        local chunk, err = sock:receive(size)
        if err then abort(sink, err) end
        length = length - string.len(chunk)
        -- see if there was an error 
        hand(sink, chunk)
    end
    -- let callback know we are done
    hand(sink, nil)
end

local function receive_body_untilclosed(sock, sink)
    while true do
        local chunk, err, partial = sock:receive(BLOCKSIZE)
        -- see if we are done
        if err == "closed" then 
            hand(sink, partial)
            break 
        end
        hand(sink, chunk)
        -- see if there was an error
        if err then abort(sink, err) end
    end
    -- let callback know we are done
    hand(sink, nil)
end

local function receive_body(reqt, respt)
    local sink = reqt.sink or ltn12.sink.null()
    local headers = respt.headers
    local sock = respt.tmp.sock
    local te = headers["transfer-encoding"]
    if te and te ~= "identity" then 
        -- get by chunked transfer-coding of message body
        receive_body_bychunks(sock, sink)
    elseif tonumber(headers["content-length"]) then
        -- get by content-length
        local length = tonumber(headers["content-length"])
        receive_body_bylength(sock, length, sink)
    else 
        -- get it all until connection closes
        receive_body_untilclosed(sock, sink) 
    end
end

local function send_body_bychunks(data, source)
    while true do
        local chunk, err = source()
        assert(chunk or not err, err) 
        if not chunk then break end
        socket.try(data:send(string.format("%X\r\n", string.len(chunk))))
        socket.try(data:send(chunk, "\r\n"))
    end
    socket.try(data:send("0\r\n\r\n"))
end

local function send_body(data, source)
    while true do
        local chunk, err = source()
        assert(chunk or not err, err) 
        if not chunk then break end
        socket.try(data:send(chunk))
    end
end

local function send_headers(sock, headers)
    -- send request headers 
    for i, v in pairs(headers) do
        socket.try(sock:send(i .. ": " .. v .. "\r\n"))
    end
    -- mark end of request headers
    socket.try(sock:send("\r\n"))
end

local function should_receive_body(reqt, respt)
    if reqt.method == "HEAD" then return nil end
    if respt.code == 204 or respt.code == 304 then return nil end
    if respt.code >= 100 and respt.code < 200 then return nil end
    return 1
end

local function receive_status(reqt, respt)
    local sock = respt.tmp.sock
    local status = socket.try(sock:receive())
    local code = third(string.find(status, "HTTP/%d*%.%d* (%d%d%d)"))
    -- store results
    respt.code, respt.status = tonumber(code), status
end

local function request_uri(reqt, respt)
    local url
    local parsed = respt.tmp.parsed
    if not reqt.proxy then
        url = { 
           path = parsed.path, 
           params = parsed.params, 
           query = parsed.query, 
           fragment = parsed.fragment
        }
    else url = respt.tmp.parsed end
    return socket.url.build(url)
end

local function send_request(reqt, respt)
    local uri = request_uri(reqt, respt)
    local sock = respt.tmp.sock
    local headers = respt.tmp.headers
    -- send request line
    socket.try(sock:send((reqt.method or "GET") 
        .. " " .. uri .. " HTTP/1.1\r\n"))
    -- send request headers headeres
    if reqt.source and not headers["content-length"] then
        headers["transfer-encoding"] = "chunked"   
    end
    send_headers(sock, headers)
    -- send request message body, if any
    if reqt.source then 
        if headers["content-length"] then send_body(sock, reqt.source) 
        else send_body_bychunks(sock, reqt.source) end
    end
end

local function open(reqt, respt)
    local parsed = respt.tmp.parsed
    local proxy = reqt.proxy or PROXY
    local host, port
    if proxy then 
        local pproxy = socket.url.parse(proxy) 
        assert(pproxy.port and pproxy.host, "invalid proxy")
        host, port = pproxy.host, pproxy.port
    else 
        host, port = parsed.host, parsed.port 
    end
    local sock = socket.try(socket.tcp())
    -- store results
    respt.tmp.sock = sock
    sock:settimeout(reqt.timeout or TIMEOUT)
    socket.try(sock:connect(host, port))
end

function adjust_headers(reqt, respt)
    local lower = {}
    local headers = reqt.headers or {}
    -- set default headers
    lower["user-agent"] = USERAGENT
    -- override with user values
    for i,v in headers do
        lower[string.lower(i)] = v
    end
    lower["host"] = respt.tmp.parsed.host
    -- this cannot be overriden
    lower["connection"] = "close"
    -- store results
    respt.tmp.headers = lower
end

function parse_url(reqt, respt)
    -- parse url with default fields
    local parsed = socket.url.parse(reqt.url, {
        host = "",
        port = PORT, 
        path ="/",
		scheme = "http"
    })
    -- scheme has to be http
	if parsed.scheme ~= "http" then
        error(string.format("unknown scheme '%s'", parsed.scheme))
    end 
    -- explicit authentication info overrides that given by the URL
    parsed.user = reqt.user or parsed.user
    parsed.password = reqt.password or parsed.password
    -- store results
    respt.tmp.parsed = parsed
end

local function should_authorize(reqt, respt)
    -- if there has been an authorization attempt, it must have failed
    if reqt.headers and reqt.headers["authorization"] then return nil end
    -- if we don't have authorization information, we can't retry
    return respt.tmp.parsed.user and respt.tmp.parsed.password 
end

local function clone(headers)
    if not headers then return nil end
    local copy = {}
    for i,v in pairs(headers) do
        copy[i] = v
    end
    return copy
end

local function authorize(reqt, respt)
    local headers = clone(reqt.headers) or {}
    local parsed = respt.tmp.parsed
    headers["authorization"] = "Basic " ..
        (mime.b64(parsed.user .. ":" .. parsed.password))
    local autht = {
        method = reqt.method,
        url = reqt.url,
        source = reqt.source,
        sink = reqt.sink,
        headers = headers,
        timeout = reqt.timeout,
        proxy = reqt.proxy,
    }
    request_p(autht, respt)
end

local function should_redirect(reqt, respt)
    return (reqt.redirect ~= false) and
           (respt.code == 301 or respt.code == 302) and
           (not reqt.method or reqt.method == "GET" or reqt.method == "HEAD") 
           and (not respt.tmp.nredirects or respt.tmp.nredirects < 5)
end

local function redirect(reqt, respt)
    respt.tmp.nredirects = (respt.tmp.nredirects or 0) + 1
    local redirt = {
        method = reqt.method,
        -- the RFC says the redirect URL has to be absolute, but some
        -- servers do not respect that
        url = socket.url.absolute(reqt.url, respt.headers["location"]),
        source = reqt.source,
        sink = reqt.sink,
        headers = reqt.headers,
        timeout = reqt.timeout,
        proxy = reqt.proxy
    }
    request_p(redirt, respt)
    -- we pass the location header as a clue we redirected
    if respt.headers then respt.headers.location = redirt.url end
end

function request_p(reqt, respt)
    parse_url(reqt, respt)
    adjust_headers(reqt, respt)
    open(reqt, respt)
    send_request(reqt, respt)
    receive_status(reqt, respt)
    respt.headers = {}
    receive_headers(respt.tmp.sock, respt.headers)
    if should_redirect(reqt, respt) then
        respt.tmp.sock:close()
        redirect(reqt, respt)
    elseif should_authorize(reqt, respt) then
        respt.tmp.sock:close()
        authorize(reqt, respt)
    elseif should_receive_body(reqt, respt) then
        receive_body(reqt, respt)
    end
end

function request(reqt)
    local respt = { tmp = {} }
    local s, e = pcall(request_p, reqt, respt)
    if not s then respt.error = e end
    if respt.tmp.sock then respt.tmp.sock:close() end
    respt.tmp = nil
    return respt
end

function get(url)
    local t = {}
    respt = request { 
        url = url, 
        sink = ltn12.sink.table(t) 
    }
    return table.getn(t) > 0 and table.concat(t), respt.headers, 
        respt.code, respt.error
end

function post(url, body)
    local t = {}
    respt = request { 
        url = url, 
        method = "POST", 
        source = ltn12.source.string(body),
        sink = ltn12.sink.table(t),
        headers = { ["content-length"] = string.len(body) } 
    }
    return table.getn(t) > 0 and table.concat(t), 
        respt.headers, respt.code, respt.error
end
