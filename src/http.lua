-----------------------------------------------------------------------------
-- HTTP/1.1 client support for the Lua language.
-- LuaSocket toolkit.
-- Author: Diego Nehab
-- Conforming to RFC 2616
-- RCS ID: $Id$
-----------------------------------------------------------------------------

-----------------------------------------------------------------------------
-- Load other required modules
-------------------------------------------------------------------------------
local socket = require("socket")
local ltn12 = require("ltn12")
local mime = require("mime")
local url = require("url")

-----------------------------------------------------------------------------
-- Setup namespace
-------------------------------------------------------------------------------
http = {}
-- make all module globals fall into namespace
setmetatable(http, { __index = _G })
setfenv(1, http)

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

local function receive_headers(reqt, respt, tmp)
    local sock = tmp.sock
    local line, name, value
    local headers = {}
    -- store results
    respt.headers = headers
    -- get first line
    line = socket.try(sock:receive())
    -- headers go until a blank line is found
    while line ~= "" do
        -- get field-name and value
        name, value = socket.skip(2, string.find(line, "^(.-):%s*(.*)"))
        socket.try(name and value, "malformed reponse headers")
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

local function receive_body(reqt, respt, tmp)
    local sink = reqt.sink or ltn12.sink.null()
    local step = reqt.step or ltn12.pump.step
    local source
    local te = respt.headers["transfer-encoding"]
    if te and te ~= "identity" then 
        -- get by chunked transfer-coding of message body
        source = socket.source("http-chunked", tmp.sock)
    elseif tonumber(respt.headers["content-length"]) then
        -- get by content-length
        local length = tonumber(respt.headers["content-length"])
        source = socket.source("by-length", tmp.sock, length)
    else 
        -- get it all until connection closes
        source = socket.source(tmp.sock)
    end
    socket.try(ltn12.pump.all(source, sink, step))
end

local function send_headers(sock, headers)
    -- send request headers 
    for i, v in pairs(headers) do
        socket.try(sock:send(i .. ": " .. v .. "\r\n"))
    end
    -- mark end of request headers
    socket.try(sock:send("\r\n"))
end

local function should_receive_body(reqt, respt, tmp)
    if reqt.method == "HEAD" then return nil end
    if respt.code == 204 or respt.code == 304 then return nil end
    if respt.code >= 100 and respt.code < 200 then return nil end
    return 1
end

local function receive_status(reqt, respt, tmp)
    local status = socket.try(tmp.sock:receive())
    local code = third(string.find(status, "HTTP/%d*%.%d* (%d%d%d)"))
    -- store results
    respt.code, respt.status = tonumber(code), status
end

local function request_uri(reqt, respt, tmp)
    local u = tmp.parsed
    if not reqt.proxy then
        local parsed = tmp.parsed
        u = { 
           path = parsed.path, 
           params = parsed.params, 
           query = parsed.query, 
           fragment = parsed.fragment
        }
    end
    return url.build(u)
end

local function send_request(reqt, respt, tmp)
    local uri = request_uri(reqt, respt, tmp)
    local headers = tmp.headers
    local step = reqt.step or ltn12.pump.step
    -- send request line
    socket.try(tmp.sock:send((reqt.method or "GET") 
        .. " " .. uri .. " HTTP/1.1\r\n"))
    if reqt.source and not headers["content-length"] then
        headers["transfer-encoding"] = "chunked"   
    end
    send_headers(tmp.sock, headers)
    -- send request message body, if any
    if not reqt.source then return end
    if headers["content-length"] then 
        socket.try(ltn12.pump.all(reqt.source, 
            socket.sink(tmp.sock), step))
    else 
        socket.try(ltn12.pump.all(reqt.source, 
            socket.sink("http-chunked", tmp.sock), step))
    end
end

local function open(reqt, respt, tmp)
    local proxy = reqt.proxy or PROXY
    local host, port
    if proxy then 
        local pproxy = url.parse(proxy) 
        socket.try(pproxy.port and pproxy.host, "invalid proxy")
        host, port = pproxy.host, pproxy.port
    else 
        host, port = tmp.parsed.host, tmp.parsed.port 
    end
    -- store results
    tmp.sock = socket.try(socket.tcp())
    socket.try(tmp.sock:settimeout(reqt.timeout or TIMEOUT))
    socket.try(tmp.sock:connect(host, port))
end

local function adjust_headers(reqt, respt, tmp)
    local lower = {}
    -- override with user values
    for i,v in (reqt.headers or lower) do
        lower[string.lower(i)] = v
    end
    lower["user-agent"] = lower["user-agent"] or USERAGENT
    -- these cannot be overriden
    lower["host"] = tmp.parsed.host
    lower["connection"] = "close"
    -- store results
    tmp.headers = lower
end

local function parse_url(reqt, respt, tmp)
    -- parse url with default fields
    local parsed = url.parse(reqt.url, {
        host = "",
        port = PORT, 
        path ="/",
		scheme = "http"
    })
    -- scheme has to be http
	socket.try(parsed.scheme == "http", 
        string.format("unknown scheme '%s'", parsed.scheme))
    -- explicit authentication info overrides that given by the URL
    parsed.user = reqt.user or parsed.user
    parsed.password = reqt.password or parsed.password
    -- store results
    tmp.parsed = parsed
end

-- forward declaration
local request_p

local function should_authorize(reqt, respt, tmp)
    -- if there has been an authorization attempt, it must have failed
    if reqt.headers and reqt.headers["authorization"] then return nil end
    -- if last attempt didn't fail due to lack of authentication,
    -- or we don't have authorization information, we can't retry
    return respt.code == 401 and tmp.parsed.user and tmp.parsed.password 
end

local function clone(headers)
    if not headers then return nil end
    local copy = {}
    for i,v in pairs(headers) do
        copy[i] = v
    end
    return copy
end

local function authorize(reqt, respt, tmp)
    local headers = clone(reqt.headers) or {}
    headers["authorization"] = "Basic " ..
        (mime.b64(tmp.parsed.user .. ":" .. tmp.parsed.password))
    local autht = {
        method = reqt.method,
        url = reqt.url,
        source = reqt.source,
        sink = reqt.sink,
        headers = headers,
        timeout = reqt.timeout,
        proxy = reqt.proxy,
    }
    request_p(autht, respt, tmp)
end

local function should_redirect(reqt, respt, tmp)
    return (reqt.redirect ~= false) and
           (respt.code == 301 or respt.code == 302) and
           (not reqt.method or reqt.method == "GET" or reqt.method == "HEAD") 
           and (not tmp.nredirects or tmp.nredirects < 5)
end

local function redirect(reqt, respt, tmp)
    tmp.nredirects = (tmp.nredirects or 0) + 1
    local redirt = {
        method = reqt.method,
        -- the RFC says the redirect URL has to be absolute, but some
        -- servers do not respect that
        url = url.absolute(reqt.url, respt.headers["location"]),
        source = reqt.source,
        sink = reqt.sink,
        headers = reqt.headers,
        timeout = reqt.timeout,
        proxy = reqt.proxy
    }
    request_p(redirt, respt, tmp)
    -- we pass the location header as a clue we redirected
    if respt.headers then respt.headers.location = redirt.url end
end

local function skip_continue(reqt, respt, tmp)
    if respt.code == 100 then
        receive_status(reqt, respt, tmp)
    end
end

-- execute a request of through an exception
function request_p(reqt, respt, tmp)
    parse_url(reqt, respt, tmp)
    adjust_headers(reqt, respt, tmp)
    open(reqt, respt, tmp)
    send_request(reqt, respt, tmp)
    receive_status(reqt, respt, tmp)
    skip_continue(reqt, respt, tmp)
    receive_headers(reqt, respt, tmp)
    if should_redirect(reqt, respt, tmp) then
        tmp.sock:close()
        redirect(reqt, respt, tmp)
    elseif should_authorize(reqt, respt, tmp) then
        tmp.sock:close()
        authorize(reqt, respt, tmp)
    elseif should_receive_body(reqt, respt, tmp) then
        receive_body(reqt, respt, tmp)
    end
end

function request(reqt)
    local respt, tmp = {}, {}
    local s, e = pcall(request_p, reqt, respt, tmp)
    if not s then respt.error = e end
    if tmp.sock then tmp.sock:close() end
    return respt
end

function get(u)
    local t = {}
    respt = request { 
        url = u, 
        sink = ltn12.sink.table(t) 
    }
    return (table.getn(t) > 0 or nil) and table.concat(t), respt.headers, 
        respt.code, respt.error
end

function post(u, body)
    local t = {}
    respt = request { 
        url = u, 
        method = "POST", 
        source = ltn12.source.string(body),
        sink = ltn12.sink.table(t),
        headers = { ["content-length"] = string.len(body) } 
    }
    return (table.getn(t) > 0 or nil) and table.concat(t), 
        respt.headers, respt.code, respt.error
end

return http
