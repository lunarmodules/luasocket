-----------------------------------------------------------------------------
-- HTTP/1.1 client support for the Lua language.
-- LuaSocket 1.5 toolkit.
-- Author: Diego Nehab
-- Conforming to: RFC 2616, LTN7
-- RCS ID: $Id$
-----------------------------------------------------------------------------

local Public, Private = {}, {}
socket.http = Public

-----------------------------------------------------------------------------
-- Program constants
-----------------------------------------------------------------------------
-- connection timeout in seconds
Public.TIMEOUT = 60 
-- default port for document retrieval
Public.PORT = 80
-- user agent field sent in request
Public.USERAGENT = "LuaSocket 1.5"
-- block size used in transfers
Public.BLOCKSIZE = 8192

-----------------------------------------------------------------------------
-- Tries to get a pattern from the server and closes socket on error
--   sock: socket connected to the server
--   ...: pattern to receive
-- Returns
--   ...: received pattern
--   err: error message if any
-----------------------------------------------------------------------------
function Private.try_receive(...)
    local sock = arg[1]
    local data, err = sock.receive(unpack(arg))
    if err then
        sock:close()
        return nil, err
    end
    return data
end

-----------------------------------------------------------------------------
-- Tries to send data to the server and closes socket on error
--   sock: socket connected to the server
--   data: data to send
-- Returns
--   err: error message if any, nil if successfull
-----------------------------------------------------------------------------
function Private.try_send(sock, data)
    local err = sock:send(data)
    if err then sock:close() end
    return err
end

-----------------------------------------------------------------------------
-- Computes status code from HTTP status line
-- Input
--   line: HTTP status line
-- Returns
--   code: integer with status code, or nil if malformed line
-----------------------------------------------------------------------------
function Private.get_statuscode(line)
    local code, _
    _, _, code = string.find(line, "HTTP/%d*%.%d* (%d%d%d)")
    return tonumber(code)
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
function Private.receive_status(sock)
    local line, err
    line, err = Private.try_receive(sock)
    if not err then return Private.get_statuscode(line), line
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
function Private.receive_headers(sock, headers)
    local line, err
    local name, value, _
    -- get first line
    line, err = Private.try_receive(sock)
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
        line, err = Private.try_receive(sock)
        if err then return nil, err end
        -- unfold any folded values
        while not err and string.find(line, "^%s") do
            value = value .. line
            line, err = Private.try_receive(sock)
            if err then return nil, err end
        end
        -- save pair in table
        if headers[name] then headers[name] = headers[name] .. ", " .. value
        else headers[name] = value end
    end
    return headers
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
function Private.receivebody_bychunks(sock, headers, receive_cb)
    local chunk, size, line, err, go, uerr, _
    while 1 do
        -- get chunk size, skip extention
        line, err = Private.try_receive(sock)
        if err then 
            local go, uerr = receive_cb(nil, err)
            return uerr or err
        end
        size = tonumber(string.gsub(line, ";.*", ""), 16)
        if not size then 
            err = "invalid chunk size"
            sock:close()
            go, uerr = receive_cb(nil, err)
            return uerr or err
        end
        -- was it the last chunk?
        if size <= 0 then break end
        -- get chunk
        chunk, err = Private.try_receive(sock, size) 
        if err then 
            go, uerr = receive_cb(nil, err)
            return uerr or err
        end
        -- pass chunk to callback
        go, uerr = receive_cb(chunk) 
        if not go then
            sock:close()
            return uerr or "aborted by callback"
        end
        -- skip CRLF on end of chunk
        _, err = Private.try_receive(sock)
        if err then 
            go, uerr = receive_cb(nil, err)
            return uerr or err
        end
    end
    -- the server should not send trailer  headers because we didn't send a
    -- header informing  it we know  how to deal with  them. we do not risk
    -- being caught unprepaired.
    headers, err = Private.receive_headers(sock, headers)
    if err then
        go, uerr = receive_cb(nil, err)
        return uerr or err
    end
    -- let callback know we are done
    go, uerr = receive_cb("")
    return uerr
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
function Private.receivebody_bylength(sock, length, receive_cb)
    local uerr, go
    while length > 0 do
        local size = math.min(Public.BLOCKSIZE, length)
        local chunk, err = sock:receive(size)
        if err then 
            go, uerr = receive_cb(nil, err)
            return uerr or err
        end
        go, uerr = receive_cb(chunk)
        if not go then 
            sock:close()
            return uerr or "aborted by callback" 
        end
        length = length - size 
    end
    go, uerr = receive_cb("")
    return uerr
end

-----------------------------------------------------------------------------
-- Receives a message body by content-length
-- Input
--   sock: socket connected to the server
--   receive_cb: function to receive chunks
-- Returns
--   nil if successfull or an error message in case of error
-----------------------------------------------------------------------------
function Private.receivebody_untilclosed(sock, receive_cb)
    local err, go, uerr
    while 1 do
        local chunk, err = sock:receive(Public.BLOCKSIZE)
        if err == "closed" or not err then 
            go, uerr = receive_cb(chunk)
            if not go then
                sock:close()
                return uerr or "aborted by callback"
            end
            if err == "closed" then break end
        else 
            go, uerr = callback(nil, err)
            return uerr or err
        end
    end
    go, uerr = receive_cb("")
    return uerr
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
function Private.receive_body(sock, headers, receive_cb)
    local te = headers["transfer-encoding"]
    if te and te ~= "identity" then 
        -- get by chunked transfer-coding of message body
        return Private.receivebody_bychunks(sock, headers, receive_cb)
    elseif tonumber(headers["content-length"]) then
        -- get by content-length
        local length = tonumber(headers["content-length"])
        return Private.receivebody_bylength(sock, length, receive_cb)
    else 
        -- get it all until connection closes
        return Private.receivebody_untilclosed(sock, receive_cb) 
    end
end

-----------------------------------------------------------------------------
-- Drop HTTP response body
-- Input
--   sock: socket connected to the server
--   headers: response header fields
-- Returns
--    nil if successfull or an error message in case of error
-----------------------------------------------------------------------------
function Private.drop_body(sock, headers)
    return Private.receive_body(sock, headers, function (c, e) return 1 end)
end

-----------------------------------------------------------------------------
-- Sends data comming from a callback
-- Input
--   data: data connection
--   send_cb: callback to produce file contents
--   chunk, size: first callback return values
-- Returns
--   nil if successfull, or an error message in case of error
-----------------------------------------------------------------------------
function Private.send_indirect(data, send_cb, chunk, size)
    local sent, err
    sent = 0
    while 1 do
        if type(chunk) ~= "string" or type(size) ~= "number" then
            data:close()
            if not chunk and type(size) == "string" then return size
            else return "invalid callback return" end
        end
        err = data:send(chunk)
        if err then 
            data:close() 
            return err 
        end
        sent = sent + string.len(chunk)
        if sent >= size then break end
        chunk, size = send_cb()
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
function Private.send_headers(sock, headers)
    local err
    headers = headers or {}
    -- send request headers 
    for i, v in headers do
        err = Private.try_send(sock, i .. ": " .. v .. "\r\n")
        if err then return err end
    end
    -- mark end of request headers
    return Private.try_send(sock, "\r\n")
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
function Private.send_request(sock, method, uri, headers, body_cb)
    local chunk, size, done, err
    -- send request line
    err = Private.try_send(sock, method .. " " .. uri .. " HTTP/1.1\r\n")
    if err then return err end
    -- if there is a request message body, add content-length header
    if body_cb then
        chunk, size = body_cb()
        if type(chunk) == "string" and type(size) == "number" then
            headers["content-length"] = tostring(size)
        else
            sock:close()
            if not chunk and type(size) == "string" then return size
            else return "invalid callback return" end
        end
    end 
    -- send request headers 
    err = Private.send_headers(sock, headers)
    if err then return err end
    -- send request message body, if any
    if body_cb then 
        return Private.send_indirect(sock, body_cb, chunk, size) 
    end
end

-----------------------------------------------------------------------------
-- Determines if we should read a message body from the server response
-- Input
--   request: a table with the original request information
--   response: a table with the server response information
-- Returns
--   1 if a message body should be processed, nil otherwise
-----------------------------------------------------------------------------
function Private.has_body(request, response)
    if request.method == "HEAD" then return nil end
    if response.code == 204 or response.code == 304 then return nil end
    if response.code >= 100 and response.code < 200 then return nil end
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
function Private.fill_headers(headers, parsed)
    local lower = {}
    headers = headers or {}
    -- set default headers
    lower["user-agent"] = Public.USERAGENT
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
--   request: a table with the original request information
--   parsed: parsed request URL
--   response: a table with the server response information
-- Returns
--   1 if we should retry, nil otherwise
-----------------------------------------------------------------------------
function Private.should_authorize(request, parsed, response)
    -- if there has been an authorization attempt, it must have failed
    if request.headers["authorization"] then return nil end
    -- if we don't have authorization information, we can't retry
    if parsed.user and parsed.password then return 1
    else return nil end
end

-----------------------------------------------------------------------------
-- Returns the result of retrying a request with authorization information
-- Input
--   request: a table with the original request information
--   parsed: parsed request URL
--   response: a table with the server response information
-- Returns
--   response: result of target redirection
-----------------------------------------------------------------------------
function Private.authorize(request, parsed, response)
    request.headers["authorization"] = "Basic " .. 
        socket.code.base64(parsed.user .. ":" .. parsed.password)
    local authorize = {
        redirects = request.redirects,
        method = request.method,
        url = request.url,
        body_cb = request.body_cb,
        headers = request.headers
    }
    return Public.request_cb(authorize, response)
end

-----------------------------------------------------------------------------
-- Decides wether we should follow a server redirect message
-- Input
--   request: a table with the original request information
--   response: a table with the server response information
-- Returns
--   1 if we should redirect, nil otherwise
-----------------------------------------------------------------------------
function Private.should_redirect(request, response)
    local follow = not request.stay
    follow = follow and (response.code == 301 or response.code == 302)
    follow = follow and (request.method == "GET" or request.method == "HEAD")
    follow = follow and not (request.redirects and request.redirects >= 5)
    return follow
end

-----------------------------------------------------------------------------
-- Returns the result of a request following a server redirect message.
-- Input
--   request: a table with the original request information
--   response: a table with the following fields:
--     body_cb: response method body receive-callback
-- Returns
--   response: result of target redirection
-----------------------------------------------------------------------------
function Private.redirect(request, response)
    local redirects = request.redirects or 0
    redirects = redirects + 1
    local redirect = {
        redirects = redirects,
        method = request.method,
        -- the RFC says the redirect URL has to be absolute, but some
        -- servers do not respect that 
        url = socket.url.absolute(request.url, response.headers["location"]),
        body_cb = request.body_cb,
        headers = request.headers
    }
    local response = Public.request_cb(redirect, response)
    -- we pass the location header as a clue we tried to redirect
    if response.headers then response.headers.location = redirect.url end
    return response
end

-----------------------------------------------------------------------------
-- Computes the request URI from the parsed request URL
-- Input
--   parsed: parsed URL
-- Returns
--   uri: request URI for parsed URL
-----------------------------------------------------------------------------
function Private.request_uri(parsed)
    local uri = ""
    if parsed.path then uri = uri .. parsed.path end
    if parsed.params then uri = uri .. ";" .. parsed.params end
    if parsed.query then uri = uri .. "?" .. parsed.query end
    if parsed.fragment then uri = uri .. "#" .. parsed.fragment end
    return uri
end

-----------------------------------------------------------------------------
-- Builds a request table from a URL or request table
-- Input
--   url_or_request: target url or request table (a table with the fields:
--     url: the target URL
--     user: account user name
--     password: account password)
-- Returns
--   request: request table
-----------------------------------------------------------------------------
function Private.build_request(data)
    local request = {}
    if type(data) == "table" then for i, v in data do request[i] = v end
    else request.url = data end
    return request
end

-----------------------------------------------------------------------------
-- Sends a HTTP request and retrieves the server reply using callbacks to
-- send the request body and receive the response body
-- Input
--   request: a table with the following fields
--     method: "GET", "PUT", "POST" etc (defaults to "GET")
--     url: target uniform resource locator
--     user, password: authentication information
--     headers: request headers to send, or nil if none
--     body_cb: request message body send-callback, or nil if none
--     stay: should we refrain from following a server redirect message?
--   response: a table with the following fields:
--     body_cb: response method body receive-callback
-- Returns
--   response: a table with the following fields: 
--     headers: response header fields received, or nil if failed
--     status: server response status line, or nil if failed
--     code: server status code, or nil if failed
--     error: error message, or nil if successfull
-----------------------------------------------------------------------------
function Public.request_cb(request, response)
    local parsed = socket.url.parse(request.url, {
        host = "",
        port = Public.PORT, 
        path ="/",
		scheme = "http"
    })
	if parsed.scheme ~= "http" then
		response.error = string.format("unknown scheme '%s'", parsed.scheme)
		return response
	end
    -- explicit authentication info overrides that given by the URL
    parsed.user = request.user or parsed.user
    parsed.password = request.password or parsed.password
    -- default method
    request.method = request.method or "GET"
    -- fill default headers
    request.headers = Private.fill_headers(request.headers, parsed)
    -- try to connect to server
    local sock
    sock, response.error = socket.connect(parsed.host, parsed.port)
    if not sock then return response end
    -- set connection timeout so that we do not hang forever
    sock:timeout(Public.TIMEOUT)
    -- send request message
    response.error = Private.send_request(sock, request.method, 
        Private.request_uri(parsed), request.headers, request.body_cb)
    if response.error then return response end
    -- get server response message
    response.code, response.status, response.error = 
        Private.receive_status(sock)
    if response.error then return response end
    -- deal with 1xx status
    if response.code == 100 then
        response.headers, response.error = Private.receive_headers(sock, {})
        if response.error then return response end
        response.code, response.status, response.error = 
            Private.receive_status(sock)
        if response.error then return response end
    end
    -- receive all headers
    response.headers, response.error = Private.receive_headers(sock, {})
    if response.error then return response end
    -- decide what to do based on request and response parameters
    if Private.should_redirect(request, response) then
        Private.drop_body(sock, response.headers)
        sock:close()
        return Private.redirect(request, response)
    elseif Private.should_authorize(request, parsed, response) then
        Private.drop_body(sock, response.headers)
        sock:close()
        return Private.authorize(request, parsed, response)
    elseif Private.has_body(request, response) then
        response.error = Private.receive_body(sock, response.headers,
            response.body_cb)
        if response.error then return response end
        sock:close()
        return response
    end
    sock:close()
    return response
end

-----------------------------------------------------------------------------
-- Sends a HTTP request and retrieves the server reply
-- Input
--   request: a table with the following fields
--     method: "GET", "PUT", "POST" etc (defaults to "GET")
--     url: request URL, i.e. the document to be retrieved
--     user, password: authentication information
--     headers: request header fields, or nil if none
--     body: request message body as a string, or nil if none
--     stay: should we refrain from following a server redirect message?
-- Returns
--   response: a table with the following fields:
--     body: response message body, or nil if failed
--     headers: response header fields, or nil if failed
--     status: server response status line, or nil if failed
--     code: server response status code, or nil if failed
--     error: error message if any
-----------------------------------------------------------------------------
function Public.request(request)
    local response = {}
    if request.body then 
        request.body_cb = function() 
            return request.body, string.len(request.body) 
        end
    end
    local cat = socket.concat.create()
    response.body_cb = function(chunk, err)
        if chunk then cat:addstring(chunk) end
        return 1
    end
    response = Public.request_cb(request, response)
    response.body = cat:getresult()
    response.body_cb = nil
    return response
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
function Public.get(url_or_request)
    local request = Private.build_request(url_or_request)
    request.method = "GET"
    local response = Public.request(request)
    return response.body, response.headers, 
        response.code, response.error
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
function Public.post(url_or_request, body)
    local request = Private.build_request(url_or_request)
    request.method = "POST"
    request.body = request.body or body
    local response = Public.request(request)
    return response.body, response.headers, 
        response.code, response.error
end
