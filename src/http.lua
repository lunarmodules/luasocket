-----------------------------------------------------------------------------
-- HTTP/1.1 client support for the Lua language.
-- LuaSocket toolkit.
-- Author: Diego Nehab
-- RCS ID: $Id$
-----------------------------------------------------------------------------

-----------------------------------------------------------------------------
-- Load required modules
-------------------------------------------------------------------------------
local socket = require("socket")
local ltn12 = require("ltn12")
local mime = require("mime")
local url = require("url")

-----------------------------------------------------------------------------
-- Program constants
-----------------------------------------------------------------------------
-- connection timeout in seconds
TIMEOUT = 60 
-- default port for document retrieval
PORT = 80
-- user agent field sent in request
USERAGENT = socket.VERSION
-- block size used in transfers
BLOCKSIZE = 2048

-----------------------------------------------------------------------------
-- Low level HTTP API
-----------------------------------------------------------------------------
local metat = { __index = {} }

function open(host, port)
    local con = socket.try(socket.tcp()) 
    socket.try(con:settimeout(TIMEOUT))
    port = port or PORT
    socket.try(con:connect(host, port))
    return setmetatable({ con = con }, metat)
end

function metat.__index:sendrequestline(method, uri)
    local reqline = string.format("%s %s HTTP/1.1\r\n", method or "GET", uri) 
    return socket.try(self.con:send(reqline))
end

function metat.__index:sendheaders(headers)
    for i, v in pairs(headers) do
        socket.try(self.con:send(i .. ": " .. v .. "\r\n"))
    end
    -- mark end of request headers
    socket.try(self.con:send("\r\n"))
    return 1
end

function metat.__index:sendbody(headers, source, step)
    source = source or ltn12.source.empty()
    step = step or ltn12.pump.step
    -- if we don't know the size in advance, send chunked and hope for the best
    local mode
    if headers["content-length"] then mode = "keep-open"
    else mode = "http-chunked" end
    return socket.try(ltn12.pump.all(source, socket.sink(mode, self.con), step))
end

function metat.__index:receivestatusline()
    local status = socket.try(self.con:receive())
    local code = socket.skip(2, string.find(status, "HTTP/%d*%.%d* (%d%d%d)"))
    return socket.try(tonumber(code), status)
end

function metat.__index:receiveheaders()
    local line, name, value
    local headers = {}
    -- get first line
    line = socket.try(self.con:receive())
    -- headers go until a blank line is found
    while line ~= "" do
        -- get field-name and value
        name, value = socket.skip(2, string.find(line, "^(.-):%s*(.*)"))
        socket.try(name and value, "malformed reponse headers")
        name = string.lower(name)
        -- get next line (value might be folded)
        line  = socket.try(self.con:receive())
        -- unfold any folded values
        while string.find(line, "^%s") do
            value = value .. line
            line = socket.try(self.con:receive())
        end
        -- save pair in table
        if headers[name] then headers[name] = headers[name] .. ", " .. value
        else headers[name] = value end
    end
    return headers
end

function metat.__index:receivebody(headers, sink, step)
    sink = sink or ltn12.sink.null()
    step = step or ltn12.pump.step
    local length = tonumber(headers["content-length"])
    local TE = headers["transfer-encoding"]
    local mode
    if TE and TE ~= "identity" then mode = "http-chunked"
    elseif tonumber(headers["content-length"]) then mode = "by-length"
    else mode = "default" end
    return socket.try(ltn12.pump.all(socket.source(mode, self.con, length), 
        sink, step))
end

function metat.__index:close()
    return self.con:close()
end

-----------------------------------------------------------------------------
-- High level HTTP API
-----------------------------------------------------------------------------
local function uri(reqt)
    local u = reqt
    if not reqt.proxy and not PROXY then
        u = {
           path = socket.try(reqt.path, "invalid path 'nil'"),
           params = reqt.params,
           query = reqt.query,
           fragment = reqt.fragment
        }
    end
    return url.build(u)
end

local function adjustheaders(headers, host)
    local lower = {}
    -- override with user values
    for i,v in (headers or lower) do
        lower[string.lower(i)] = v
    end
    lower["user-agent"] = lower["user-agent"] or USERAGENT
    -- these cannot be overriden
    lower["host"] = host
    return lower
end

local default = {
    host = "",
    port = PORT,
    path ="/",
    scheme = "http"
}

local function adjustrequest(reqt)
    -- parse url if provided
    local nreqt = reqt.url and url.parse(reqt.url, default) or {}
    -- explicit components override url
    for i,v in reqt do nreqt[i] = reqt[i] end
    socket.try(nreqt.host, "invalid host '" .. tostring(nreqt.host) .. "'")
    -- compute uri if user hasn't overriden
    nreqt.uri = nreqt.uri or uri(nreqt)
    -- adjust headers in request
    nreqt.headers = adjustheaders(nreqt.headers, nreqt.host)
    return nreqt
end

local function shouldredirect(reqt, code)
    return (reqt.redirect ~= false) and
           (code == 301 or code == 302) and
           (not reqt.method or reqt.method == "GET" or reqt.method == "HEAD")
           and (not reqt.nredirects or reqt.nredirects < 5)
end

local function shouldauthorize(reqt, code)
    -- if there has been an authorization attempt, it must have failed
    if reqt.headers and reqt.headers["authorization"] then return nil end
    -- if last attempt didn't fail due to lack of authentication,
    -- or we don't have authorization information, we can't retry
    return code == 401 and reqt.user and reqt.password
end

local function shouldreceivebody(reqt, code)
    if reqt.method == "HEAD" then return nil end
    if code == 204 or code == 304 then return nil end
    if code >= 100 and code < 200 then return nil end
    return 1
end

-- forward declarations
local trequest, tauthorize, tredirect

function tauthorize(reqt)
    local auth = "Basic " ..  (mime.b64(reqt.user .. ":" .. reqt.password))
    reqt.headers["authorization"] = auth
    return trequest(reqt)
end

function tredirect(reqt, headers)
    -- the RFC says the redirect URL has to be absolute, but some
    -- servers do not respect that
    return trequest {
        url = url.absolute(reqt, headers["location"]),
        source = reqt.source,
        sink = reqt.sink,
        headers = reqt.headers,
        proxy = reqt.proxy,
        nredirects = (reqt.nredirects or 0) + 1
    }
end

function trequest(reqt)
    reqt = adjustrequest(reqt)
    local con = open(reqt.host, reqt.port)
    con:sendrequestline(reqt.method, reqt.uri)
    con:sendheaders(reqt.headers)
    con:sendbody(reqt.headers, reqt.source, reqt.step)
    local code, headers, status
    code, status = con:receivestatusline()
    headers = con:receiveheaders()
    if shouldredirect(reqt, code) then 
        con:close()
        return tredirect(reqt, headers)
    elseif shouldauthorize(reqt, code) then 
        con:close()
        return tauthorize(reqt)
    elseif shouldreceivebody(reqt, code) then
        con:receivebody(headers, reqt.sink, reqt.step)
    end
    con:close()
    return 1, code, headers, status
end

local function srequest(u, body)
    local t = {}
    local reqt = { 
        url = u,
        sink = ltn12.sink.table(t)
    }
    if body then 
        reqt.source = ltn12.source.string(body) 
        reqt.headers = { ["content-length"] = string.len(body) }
        reqt.method = "POST"
    end
    local code, headers, status = socket.skip(1, trequest(reqt))
    return table.concat(t), code, headers, status
end

request = socket.protect(function(reqt, body)
    if type(reqt) == "string" then return srequest(reqt, body)
    else return trequest(reqt) end
end)
