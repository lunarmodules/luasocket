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
-- create smtp namespace inside LuaSocket namespace
local http = {}
socket.http = http
-- make all module globals fall into smtp namespace
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
USERAGENT = "LuaSocket 2.0"
-- block size used in transfers
BLOCKSIZE = 8192

-----------------------------------------------------------------------------
-- Tries to get a pattern from the server and closes socket on error
--   sock: socket connected to the server
--   pattern: pattern to receive
-- Returns
--   received pattern on success
--   nil followed by error message on error
-----------------------------------------------------------------------------
local function try_receiving(sock, pattern)
    local data, err = sock:receive(pattern)
    if not data then sock:close() end
--print(data)
    return data, err
end

-----------------------------------------------------------------------------
-- Tries to send data to the server and closes socket on error
--   sock: socket connected to the server
--   data: data to send
-- Returns
--   err: error message if any, nil if successfull
-----------------------------------------------------------------------------
local function try_sending(sock, ...)
    local sent, err = sock:send(unpack(arg))
    if not sent then sock:close() end
--io.write(unpack(arg))
    return err
end

-----------------------------------------------------------------------------
-- Receive server reply messages, parsing for status code
-- Input
--   sock: socket connected to the server
-- Returns
--   code: server status code or nil if error
--   line: full HTTP status line
--   err: error message if any
-----------------------------------------------------------------------------
local function receive_status(sock)
    local line, err
    line, err = try_receiving(sock)
    if not err then 
        local code, _
        _, _, code = string.find(line, "HTTP/%d*%.%d* (%d%d%d)")
        return tonumber(code), line
    else return nil, nil, err end
end

-----------------------------------------------------------------------------
-- Receive and parse response header fields
-- Input
--   sock: socket connected to the server
--   headers: a table that might already contain headers
-- Returns
--   headers: a table with all headers fields in the form
--        {name_1 = "value_1", name_2 = "value_2" ... name_n = "value_n"} 
--        all name_i are lowercase
--   nil and error message in case of error
-----------------------------------------------------------------------------
local function receive_headers(sock, headers)
    local line, err
    local name, value, _
    headers = headers or {}
    -- get first line
    line, err = try_receiving(sock)
    if err then return nil, err end
    -- headers go until a blank line is found
    while line ~= "" do
        -- get field-name and value
        _,_, name, value = string.find(line, "^(.-):%s*(.*)")
        if not name or not value then 
            sock:close()
            return nil, "malformed reponse headers" 
        end
        name = string.lower(name)
        -- get next line (value might be folded)
        line, err = try_receiving(sock)
        if err then return nil, err end
        -- unfold any folded values
        while not err and string.find(line, "^%s") do
            value = value .. line
            line, err = try_receiving(sock)
            if err then return nil, err end
        end
        -- save pair in table
        if headers[name] then headers[name] = headers[name] .. ", " .. value
        else headers[name] = value end
    end
    return headers
end

-----------------------------------------------------------------------------
-- Aborts a receive callback
-- Input
--   cb: callback function
--   err: error message to pass to callback
-- Returns
--   callback return or if nil err
-----------------------------------------------------------------------------
local function abort(cb, err) 
    local go, err_or_f = cb(nil, err)
    return err_or_f or err
end

-----------------------------------------------------------------------------
-- Receives a chunked message body
-- Input
--   sock: socket connected to the server
--   headers: header set in which to include trailer headers
--   receive_cb: function to receive chunks
-- Returns
--   nil if successfull or an error message in case of error
-----------------------------------------------------------------------------
local function receive_body_bychunks(sock, headers, receive_cb)
    local chunk, size, line, err, go, err_or_f, _
    while 1 do
        -- get chunk size, skip extention
        line, err = try_receiving(sock)
        if err then return abort(receive_cb, err) end
        size = tonumber(string.gsub(line, ";.*", ""), 16)
        if not size then return abort(receive_cb, "invalid chunk size") end
        -- was it the last chunk?
        if size <= 0 then break end
        -- get chunk
        chunk, err = try_receiving(sock, size) 
        if err then return abort(receive_cb, err) end
        -- pass chunk to callback
        go, err_or_f = receive_cb(chunk) 
        -- see if callback needs to be replaced
        receive_cb = err_or_f or receive_cb
        -- see if callback aborted
        if not go then return err_or_f or "aborted by callback" end
        -- skip CRLF on end of chunk
        _, err = try_receiving(sock)
        if err then return abort(receive_cb, err) end
    end
    -- the server should not send trailer  headers because we didn't send a
    -- header informing  it we know  how to deal with  them. we do not risk
    -- being caught unprepaired.
    _, err = receive_headers(sock, headers)
    if err then return abort(receive_cb, err) end
    -- let callback know we are done
    _, err_or_f = receive_cb("")
    return err_or_f
end

-----------------------------------------------------------------------------
-- Receives a message body by content-length
-- Input
--   sock: socket connected to the server
--   length: message body length
--   receive_cb: function to receive chunks
-- Returns
--   nil if successfull or an error message in case of error
-----------------------------------------------------------------------------
local function receive_body_bylength(sock, length, receive_cb)
    while length > 0 do
        local size = math.min(BLOCKSIZE, length)
        local chunk, err = sock:receive(size)
        local go, err_or_f = receive_cb(chunk)
        length = length - string.len(chunk)
        -- see if callback aborted
        if not go then return err_or_f or "aborted by callback" end
        -- see if callback needs to be replaced
        receive_cb = err_or_f or receive_cb
        -- see if there was an error 
        if err and length > 0 then return abort(receive_cb, err) end
    end
    local _, err_or_f = receive_cb("")
    return err_or_f
end

-----------------------------------------------------------------------------
-- Receives a message body by content-length
-- Input
--   sock: socket connected to the server
--   receive_cb: function to receive chunks
-- Returns
--   nil if successfull or an error message in case of error
-----------------------------------------------------------------------------
local function receive_body_untilclosed(sock, receive_cb)
    while 1 do
        local chunk, err = sock:receive(BLOCKSIZE)
        local go, err_or_f = receive_cb(chunk)
        -- see if callback aborted
        if not go then return err_or_f or "aborted by callback" end
        -- see if callback needs to be replaced
        receive_cb = err_or_f or receive_cb
        -- see if we are done
        if err == "closed" then
            if chunk ~= "" then
                go, err_or_f = receive_cb("")
                return err_or_f
            end
        end
        -- see if there was an error
        if err then return abort(receive_cb, err) end
    end
end

-----------------------------------------------------------------------------
-- Receives HTTP response body
-- Input
--   sock: socket connected to the server
--   headers: response header fields
--   receive_cb: function to receive chunks
-- Returns
--    nil if successfull or an error message in case of error
-----------------------------------------------------------------------------
local function receive_body(sock, headers, receive_cb)
    local te = headers["transfer-encoding"]
    if te and te ~= "identity" then 
        -- get by chunked transfer-coding of message body
        return receive_body_bychunks(sock, headers, receive_cb)
    elseif tonumber(headers["content-length"]) then
        -- get by content-length
        local length = tonumber(headers["content-length"])
        return receive_body_bylength(sock, length, receive_cb)
    else 
        -- get it all until connection closes
        return receive_body_untilclosed(sock, receive_cb) 
    end
end

-----------------------------------------------------------------------------
-- Sends data comming from a callback
-- Input
--   data: data connection
--   send_cb: callback to produce file contents
-- Returns
--   nil if successfull, or an error message in case of error
-----------------------------------------------------------------------------
local function send_body_bychunks(data, send_cb)
    while 1 do
        local chunk, err_or_f = send_cb()
        -- check if callback aborted
        if not chunk then return err_or_f or "aborted by callback" end
        -- check if callback should be replaced
        send_cb = err_or_f or send_cb
        -- if we are done, send last-chunk
        if chunk == "" then return try_sending(data, "0\r\n\r\n") end
        -- else send middle chunk
        local err = try_sending(data, 
            string.format("%X\r\n", string.len(chunk)),
            chunk, 
            "\r\n"
        )
        if err then return err end
    end
end

-----------------------------------------------------------------------------
-- Sends data comming from a callback
-- Input
--   data: data connection
--   send_cb: callback to produce body contents
-- Returns
--   nil if successfull, or an error message in case of error
-----------------------------------------------------------------------------
local function send_body_bylength(data, send_cb)
    while 1 do
        local chunk, err_or_f = send_cb()
        -- check if callback aborted
        if not chunk then return err_or_f or "aborted by callback" end
        -- check if callback should be replaced
        send_cb = err_or_f or send_cb
        -- check if callback is done
        if chunk == "" then return end
        -- send data
        local err = try_sending(data, chunk)
        if err then return err end
    end
end

-----------------------------------------------------------------------------
-- Sends mime headers
-- Input
--   sock: server socket
--   headers: table with mime headers to be sent
-- Returns
--   err: error message if any
-----------------------------------------------------------------------------
local function send_headers(sock, headers)
    local err
    headers = headers or {}
    -- send request headers 
    for i, v in headers do
        err = try_sending(sock, i .. ": " .. v .. "\r\n")
        if err then return err end
    end
    -- mark end of request headers
    return try_sending(sock, "\r\n")
end

-----------------------------------------------------------------------------
-- Sends a HTTP request message through socket
-- Input
--   sock: socket connected to the server
--   method: request method to  be used
--   uri: request uri
--   headers: request headers to be sent
--   body_cb: callback to send request message body
-- Returns
--   err: nil in case of success, error message otherwise
-----------------------------------------------------------------------------
local function send_request(sock, method, uri, headers, body_cb)
    local chunk, size, done, err
    -- send request line
    err = try_sending(sock, method .. " " .. uri .. " HTTP/1.1\r\n")
    if err then return err end
    if body_cb and not headers["content-length"] then
        headers["transfer-encoding"] = "chunked"   
    end
    -- send request headers 
    err = send_headers(sock, headers)
    if err then return err end
    -- send request message body, if any
    if body_cb then 
        if not headers["content-length"] then
            return send_body_bychunks(sock, body_cb) 
        else
            return send_body_bylength(sock, body_cb) 
        end
    end
end

-----------------------------------------------------------------------------
-- Determines if we should read a message body from the server response
-- Input
--   reqt: a table with the original request information
--   respt: a table with the server response information
-- Returns
--   1 if a message body should be processed, nil otherwise
-----------------------------------------------------------------------------
local function should_receive_body(reqt, respt)
    if reqt.method == "HEAD" then return nil end
    if respt.code == 204 or respt.code == 304 then return nil end
    if respt.code >= 100 and respt.code < 200 then return nil end
    return 1
end

-----------------------------------------------------------------------------
-- Converts field names to lowercase and adds a few needed headers
-- Input
--   headers: request header fields
--   parsed: parsed request URL
-- Returns
--   lower: a table with the same headers, but with lowercase field names
-----------------------------------------------------------------------------
local function fill_headers(headers, parsed)
    local lower = {}
    headers = headers or {}
    -- set default headers
    lower["user-agent"] = USERAGENT
    -- override with user values
    for i,v in headers do
        lower[string.lower(i)] = v
    end
    lower["host"] = parsed.host
    -- this cannot be overriden
    lower["connection"] = "close"
    return lower
end

-----------------------------------------------------------------------------
-- Decides wether we should follow retry with authorization formation
-- Input
--   reqt: a table with the original request information
--   parsed: parsed request URL
--   respt: a table with the server response information
-- Returns
--   1 if we should retry, nil otherwise
-----------------------------------------------------------------------------
local function should_authorize(reqt, parsed, respt)
    -- if there has been an authorization attempt, it must have failed
    if reqt.headers["authorization"] then return nil end
    -- if we don't have authorization information, we can't retry
    if parsed.user and parsed.password then return 1
    else return nil end
end

-----------------------------------------------------------------------------
-- Returns the result of retrying a request with authorization information
-- Input
--   reqt: a table with the original request information
--   parsed: parsed request URL
--   respt: a table with the server response information
-- Returns
--   respt: result of target authorization
-----------------------------------------------------------------------------
local function authorize(reqt, parsed, respt)
    reqt.headers["authorization"] = "Basic " .. 
        (socket.mime.b64(parsed.user .. ":" .. parsed.password))
    local autht = {
        nredirects = reqt.nredirects,
        method = reqt.method,
        url = reqt.url,
        body_cb = reqt.body_cb,
        headers = reqt.headers,
        timeout = reqt.timeout,
        proxyhost = reqt.proxyhost,
        proxyport = reqt.proxyport
    }
    return request_cb(autht, respt)
end

-----------------------------------------------------------------------------
-- Decides wether we should follow a server redirect message
-- Input
--   reqt: a table with the original request information
--   respt: a table with the server response information
-- Returns
--   1 if we should redirect, nil otherwise
-----------------------------------------------------------------------------
local function should_redirect(reqt, respt)
    return (reqt.redirect ~= false) and 
           (respt.code == 301 or respt.code == 302) and 
           (reqt.method == "GET" or reqt.method == "HEAD") and
            not (reqt.nredirects and reqt.nredirects >= 5)
end

-----------------------------------------------------------------------------
-- Returns the result of a request following a server redirect message.
-- Input
--   reqt: a table with the original request information
--   respt: a table with the following fields:
--     body_cb: response method body receive-callback
-- Returns
--   respt: result of target redirection
-----------------------------------------------------------------------------
local function redirect(reqt, respt)
    local nredirects = reqt.nredirects or 0
    nredirects = nredirects + 1
    local redirt = {
        nredirects = nredirects,
        method = reqt.method,
        -- the RFC says the redirect URL has to be absolute, but some
        -- servers do not respect that 
        url = socket.url.absolute(reqt.url, respt.headers["location"]),
        body_cb = reqt.body_cb,
        headers = reqt.headers,
        timeout = reqt.timeout,
        proxyhost = reqt.proxyhost,
        proxyport = reqt.proxyport
    }
    respt = request_cb(redirt, respt)
    -- we pass the location header as a clue we tried to redirect
    if respt.headers then respt.headers.location = redirt.url end
    return respt
end

-----------------------------------------------------------------------------
-- Computes the request URI from the parsed request URL
-- If we are using a proxy, we use the absoluteURI format. 
-- Otherwise, we use the abs_path format.
-- Input
--   parsed: parsed URL
-- Returns
--   uri: request URI for parsed URL
-----------------------------------------------------------------------------
local function request_uri(reqt, parsed)
    local url
    if not reqt.proxyhost and not reqt.proxyport then
        url = { 
           path = parsed.path, 
           params = parsed.params, 
           query = parsed.query, 
           fragment = parsed.fragment
        }
    else url = parsed end
    return socket.url.build(url)
end

-----------------------------------------------------------------------------
-- Builds a request table from a URL or request table
-- Input
--   url_or_request: target url or request table (a table with the fields:
--     url: the target URL
--     user: account user name
--     password: account password)
-- Returns
--   reqt: request table
-----------------------------------------------------------------------------
local function build_request(data)
    local reqt = {}
    if type(data) == "table" then 
		for i, v in data 
			do reqt[i] = v 
		end
    else reqt.url = data end
    return reqt
end

-----------------------------------------------------------------------------
-- Sends a HTTP request and retrieves the server reply using callbacks to
-- send the request body and receive the response body
-- Input
--   reqt: a table with the following fields
--     method: "GET", "PUT", "POST" etc (defaults to "GET")
--     url: target uniform resource locator
--     user, password: authentication information
--     headers: request headers to send, or nil if none
--     body_cb: request message body send-callback, or nil if none
--     redirect: should we refrain from following a server redirect message?
--   respt: a table with the following fields:
--     body_cb: response method body receive-callback
-- Returns
--   respt: a table with the following fields: 
--     headers: response header fields received, or nil if failed
--     status: server response status line, or nil if failed
--     code: server status code, or nil if failed
--     error: error message, or nil if successfull
-----------------------------------------------------------------------------
function request_cb(reqt, respt)
    local sock, ret
    local parsed = socket.url.parse(reqt.url, {
        host = "",
        port = PORT, 
        path ="/",
		scheme = "http"
    })
	if parsed.scheme ~= "http" then
		respt.error = string.format("unknown scheme '%s'", parsed.scheme)
		return respt
	end
    -- explicit authentication info overrides that given by the URL
    parsed.user = reqt.user or parsed.user
    parsed.password = reqt.password or parsed.password
    -- default method
    reqt.method = reqt.method or "GET"
    -- fill default headers
    reqt.headers = fill_headers(reqt.headers, parsed)
    -- try to connect to server
    sock, respt.error = socket.tcp()
    if not sock then return respt end
    -- set connection timeout so that we do not hang forever
    sock:settimeout(reqt.timeout or TIMEOUT)
    ret, respt.error = sock:connect(
        reqt.proxyhost or PROXYHOST or parsed.host, 
        reqt.proxyport or PROXYPORT or parsed.port
    )
    if not ret then 
        sock:close()
        return respt 
    end
    -- send request message
    respt.error = send_request(sock, reqt.method, 
        request_uri(reqt, parsed), reqt.headers, reqt.body_cb)
    if respt.error then 
        sock:close()
        return respt 
    end
    -- get server response message
    respt.code, respt.status, respt.error = receive_status(sock)
    if respt.error then return respt end
    -- deal with continue 100 
    -- servers should not send them, but some do!
    if respt.code == 100 then
        respt.headers, respt.error = receive_headers(sock, {})
        if respt.error then return respt end
        respt.code, respt.status, respt.error = receive_status(sock)
        if respt.error then return respt end
    end
    -- receive all headers
    respt.headers, respt.error = receive_headers(sock, {})
    if respt.error then return respt end
    -- decide what to do based on request and response parameters
    if should_redirect(reqt, respt) then
        -- drop the body
        receive_body(sock, respt.headers, function (c, e) return 1 end)
        -- we are done with this connection
        sock:close()
        return redirect(reqt, respt)
    elseif should_authorize(reqt, parsed, respt) then
        -- drop the body
        receive_body(sock, respt.headers, function (c, e) return 1 end)
        -- we are done with this connection
        sock:close()
        return authorize(reqt, parsed, respt)
    elseif should_receive_body(reqt, respt) then
        respt.error = receive_body(sock, respt.headers, respt.body_cb)
        if respt.error then return respt end
        sock:close()
        return respt
    end
    sock:close()
    return respt
end

-----------------------------------------------------------------------------
-- Sends a HTTP request and retrieves the server reply
-- Input
--   reqt: a table with the following fields
--     method: "GET", "PUT", "POST" etc (defaults to "GET")
--     url: request URL, i.e. the document to be retrieved
--     user, password: authentication information
--     headers: request header fields, or nil if none
--     body: request message body as a string, or nil if none
--     redirect: should we refrain from following a server redirect message?
-- Returns
--   respt: a table with the following fields:
--     body: response message body, or nil if failed
--     headers: response header fields, or nil if failed
--     status: server response status line, or nil if failed
--     code: server response status code, or nil if failed
--     error: error message if any
-----------------------------------------------------------------------------
function request(reqt)
    local respt = {}
    reqt.body_cb = socket.callback.send.string(reqt.body) 
    local concat = socket.concat.create()
    respt.body_cb = socket.callback.receive.concat(concat)
    respt = request_cb(reqt, respt)
    respt.body = concat:getresult()
    respt.body_cb = nil
    return respt
end

-----------------------------------------------------------------------------
-- Retrieves a URL by the method "GET"
-- Input
--   url_or_request: target url or request table (a table with the fields:
--     url: the target URL
--     user: account user name
--     password: account password)
-- Returns
--   body: response message body, or nil if failed
--   headers: response header fields received, or nil if failed
--   code: server response status code, or nil if failed
--   error: error message if any
-----------------------------------------------------------------------------
function get(url_or_request)
    local reqt = build_request(url_or_request)
    reqt.method = "GET"
    local respt = request(reqt)
    return respt.body, respt.headers, respt.code, respt.error
end

-----------------------------------------------------------------------------
-- Retrieves a URL by the method "POST"
-- Input
--   url_or_request: target url or request table (a table with the fields:
--     url: the target URL
--     body: request message body
--     user: account user name
--     password: account password)
--   body: request message body, or nil if none
-- Returns
--   body: response message body, or nil if failed
--   headers: response header fields received, or nil if failed
--   code: server response status code, or nil if failed
--   error: error message, or nil if successfull
-----------------------------------------------------------------------------
function post(url_or_request, body)
    local reqt = build_request(url_or_request)
    reqt.method = "POST"
    reqt.body = reqt.body or body
    reqt.headers = reqt.headers or 
        { ["content-length"] = string.len(reqt.body) }
    local respt = request(reqt)
    return respt.body, respt.headers, respt.code, respt.error
end

return http
