-----------------------------------------------------------------------------
-- Full HTTP/1.1 client support for the Lua language using the 
-- LuaSocket 1.2 toolkit.
-- Author: Diego Nehab
-- Date: 26/12/2000
-- Conforming to: RFC 2068
-----------------------------------------------------------------------------

-----------------------------------------------------------------------------
-- Program constants
-----------------------------------------------------------------------------
-- connection timeout in seconds
local TIMEOUT = 60 
-- default port for document retrieval
local PORT = 80
-- user agent field sent in request
local USERAGENT = "LuaSocket 1.3b HTTP 1.1"
-- block size used in transfers
local BLOCKSIZE = 4096

-----------------------------------------------------------------------------
-- Tries to get a pattern from the server and closes socket on error
--   sock: socket connected to the server
--   pattern: pattern to receive
-- Returns
--   data: line received or nil in case of error
--   err: error message if any
-----------------------------------------------------------------------------
local try_get = function(...)
    local sock = arg[1]
    local data, err = call(sock.receive,  arg)
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
local try_send = function(sock, data)
    err = sock:send(data)
    if err then sock:close() end
    return err
end

-----------------------------------------------------------------------------
-- Retrieves status code from http status line
-- Input
--   line: http status line
-- Returns
--   code: integer with status code
-----------------------------------------------------------------------------
local get_statuscode = function(line)
    local _,_, code = strfind(line, " (%d%d%d) ")
    return tonumber(code)
end

-----------------------------------------------------------------------------
-- Receive server reply messages
-- Input
--   sock: socket connected to the server
-- Returns
--   code: server status code or nil if error
--   line: full http status line
--   err: error message if any
-----------------------------------------------------------------------------
local get_status = function(sock)
    local line, err
    line, err = %try_get(sock)
    if not err then return %get_statuscode(line), line
    else return nil, nil, err end
end

-----------------------------------------------------------------------------
-- Receive and parse responce header fields
-- Input
--   sock: socket connected to the server
--   hdrs: a table that might already contain headers
-- Returns
--   hdrs: a table with all headers fields in the form
--        {name_1 = "value_1", name_2 = "value_2" ... name_n = "value_n"} 
--        all name_i are lowercase
--   nil and error message in case of error
-----------------------------------------------------------------------------
local get_hdrs = function(sock, hdrs)
    local line, err
    local name, value
    -- get first line
    line, err = %try_get(sock)
    if err then return nil, err end
    -- headers go until a blank line is found
    while line ~= "" do
        -- get field-name and value
        _,_, name, value = strfind(line, "(.-):%s*(.*)")
        if not name or not value then 
            sock:close()
            return nil, "malformed reponse headers" 
        end
        name = strlower(name)
        -- get next line (value might be folded)
        line, err = %try_get(sock)
        if err then return nil, err end
        -- unfold any folded values
        while not err and strfind(line, "^%s") do
            value = value .. line
            line, err = %try_get(sock)
            if err then return nil, err end
        end
        -- save pair in table
        if hdrs[name] then hdrs[name] = hdrs[name] .. ", " .. value
        else hdrs[name] = value end
    end
    return hdrs
end

-----------------------------------------------------------------------------
-- Receives a chunked message body
-- Input
--   sock: socket connected to the server
--   receive_cb: function to receive chunks
-- Returns
--   nil if successfull or an error message in case of error
-----------------------------------------------------------------------------
local try_getchunked = function(sock, receive_cb)
    local chunk, size, line, err, go, uerr, _
    repeat 
        -- get chunk size, skip extention
        line, err = %try_get(sock)
        if err then 
            local _, uerr = receive_cb(nil, err)
            return uerr or err
        end
        size = tonumber(gsub(line, ";.*", ""), 16)
        if not size then 
            err = "invalid chunk size"
            sock:close()
            _, uerr = receive_cb(nil, err)
            return uerr or err
        end
        -- get chunk
        chunk, err = %try_get(sock, size) 
        if err then 
            _, uerr = receive_cb(nil, err)
            return uerr or err
        end
        -- pass chunk to callback
        go, uerr = receive_cb(chunk) 
        if not go then
            sock:close()
            return uerr or "aborted by callback"
        end
        -- skip blank line
        _, err = %try_get(sock)
        if err then 
            _, uerr = receive_cb(nil, err)
            return uerr or err
        end
    until size <= 0
    -- let callback know we are done
    _, uerr = receive_cb("")
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
local try_getbylength = function(sock, length, receive_cb)
    local uerr, go
    while length > 0 do
        local size = min(%BLOCKSIZE, length)
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
local try_getuntilclosed = function(sock, receive_cb)
    local err, go, uerr
    while 1 do
        local chunk, err = sock:receive(%BLOCKSIZE)
        if err == "closed" or not err then 
            go, uerr = receive_cb(chunk)
            if not go then
                sock:close()
                return uerr or "aborted by callback"
            end
            if err then break end
        else 
            go, uerr = callback(nil, err)
            return uerr or err
        end
    end
    go, uerr = receive_cb("")
    return uerr
end

-----------------------------------------------------------------------------
-- Receives http response body
-- Input
--   sock: socket connected to the server
--   resp_hdrs: response header fields
--   receive_cb: function to receive chunks
-- Returns
--    nil if successfull or an error message in case of error
-----------------------------------------------------------------------------
local try_getbody = function(sock, resp_hdrs, receive_cb)
    local err
    if resp_hdrs["transfer-encoding"] == "chunked" then
        -- get by chunked transfer-coding of message body
        return %try_getchunked(sock, receive_cb)
    elseif tonumber(resp_hdrs["content-length"]) then
        -- get by content-length
        local length = tonumber(resp_hdrs["content-length"])
        return %try_getbylength(sock, length, receive_cb)
    else 
        -- get it all until connection closes
        return %try_getuntilclosed(sock, receive_cb) 
    end
end

-----------------------------------------------------------------------------
-- Parses a url and returns its scheme, user, password, host, port 
-- and path components, according to RFC 1738
-- Input
--   url: uniform resource locator of request
--   default: table containing default values to be returned
-- Returns
--   table with the following fields:
--     host: host to connect
--     path: url path
--     port: host port to connect
--     user: user name
--     pass: password
--     scheme: protocol
-----------------------------------------------------------------------------
local split_url = function(url, default)
    -- initialize default parameters
    local parsed = default or {}
    -- get scheme
    url = gsub(url, "^(.+)://", function (s) %parsed.scheme = s end)
    -- get user name and password. both can be empty!
    -- moreover, password can be ommited
    url = gsub(url, "^([^@:/]*)(:?)([^:@/]-)@", function (u, c, p)
        %parsed.user = u
        -- there can be an empty password, but the ':' has to be there
        -- or else there is no password
        %parsed.pass = nil -- kill default password
        if c == ":" then %parsed.pass = p end
    end)
    -- get host
    url = gsub(url, "^([%w%.%-]+)", function (h) %parsed.host = h end)
    -- get port if any
    url = gsub(url, "^:(%d+)", function (p) %parsed.port = p end)
    -- whatever is left is the path
    if url ~= "" then parsed.path = url end
    return parsed
end

-----------------------------------------------------------------------------
-- Sends data comming from a callback
-- Input
--   data: data connection
--   send_cb: callback to produce file contents
--   chunk, size: first callback results
-- Returns
--   nil if successfull, or an error message in case of error
-----------------------------------------------------------------------------
local try_sendindirect = function(data, send_cb, chunk, size)
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
        sent = sent + strlen(chunk)
        if sent >= size then break end
        chunk, size = send_cb()
    end
end

-----------------------------------------------------------------------------
-- Sends a http request message through socket
-- Input
--   sock: socket connected to the server
--   method: request method to  be used
--   path: url path
--   req_hdrs: request headers to be sent
--   req_body_cb: callback to send request message body
-- Returns
--   err: nil in case of success, error message otherwise
-----------------------------------------------------------------------------
local send_request = function(sock, method, path, req_hdrs, req_body_cb)
    local chunk, size, done, err
    -- send request line
    err = %try_send(sock, method .. " " .. path .. " HTTP/1.1\r\n")
    if err then return err end
    -- if there is a request message body, add content-length header
    if req_body_cb then
        chunk, size = req_body_cb()
        if type(chunk) == "string" and type(size) == "number" then
            req_hdrs["content-length"] = tostring(size)
        else
            sock:close()
			if not chunk and type(size) == "string" then return size
			else return "invalid callback return" end
        end
    end 
    -- send request headers 
    for i, v in req_hdrs do
        err = %try_send(sock, i .. ": " .. v .. "\r\n")
        if err then return err end
    end
    -- mark end of request headers
    err = %try_send(sock, "\r\n")
    if err then return err end
    -- send request message body, if any
    if req_body_cb then 
        return %try_sendindirect(sock, req_body_cb, chunk, size) 
    end
end

-----------------------------------------------------------------------------
-- Determines if we should read a message body from the server response
-- Input
--   method: method used in request
--   code: server response status code
-- Returns
--   1 if a message body should be processed, nil otherwise
-----------------------------------------------------------------------------
function has_respbody(method, code)
    if method == "HEAD" then return nil end
    if code == 204 or code == 304 then return nil end
    if code >= 100 and code < 200 then return nil end
    return 1
end

-----------------------------------------------------------------------------
-- We need base64 convertion routines for Basic Authentication Scheme
-----------------------------------------------------------------------------
dofile("base64.lua")

-----------------------------------------------------------------------------
-- Converts field names to lowercase and adds a few needed headers
-- Input
--   hdrs: request header fields
--   parsed: parsed url components
-- Returns
--   lower: a table with the same headers, but with lowercase field names
-----------------------------------------------------------------------------
local fill_hdrs = function(hdrs, parsed)
    local lower = {}
    hdrs = hdrs or {}
    for i,v in hdrs do
        lower[strlower(i)] = v
    end
    lower["connection"] = "close"
    lower["host"] = parsed.host
    lower["user-agent"] = %USERAGENT
    if parsed.user and parsed.pass then -- Basic Authentication
        lower["authorization"] = "Basic ".. 
            base64(parsed.user .. ":" .. parsed.pass)
    end
    return lower
end

-----------------------------------------------------------------------------
-- Sends a HTTP request and retrieves the server reply using callbacks to
-- send the request body and receive the response body
-- Input
--   method: "GET", "PUT", "POST" etc
--   url: target uniform resource locator
--   resp_body_cb: response message body receive callback
--   req_hdrs: request headers to send, or nil if none
--   req_body_cb: request message body send callback, or nil if none
--   stay: should we refrain from following a server redirect message?
-- Returns
--   resp_hdrs: response header fields received, or nil if failed
--   resp_line: server response status line, or nil if failed
--   err: error message, or nil if successfull
-----------------------------------------------------------------------------
function http_requestindirect(method, url, resp_body_cb, req_hdrs, 
  req_body_cb, stay)
    local sock, err
    local resp_hdrs
    local resp_line, resp_code
    -- get url components
    local parsed = %split_url(url, {port = %PORT, path ="/"})
    -- methods are case sensitive
    method = strupper(method)
    -- fill default headers
    req_hdrs = %fill_hdrs(req_hdrs, parsed)
    -- try connection
    sock, err = connect(parsed.host, parsed.port)
    if not sock then return nil, nil, err end
    -- set connection timeout
    sock:timeout(%TIMEOUT)
    -- send request
    err = %send_request(sock, method, parsed.path, req_hdrs, req_body_cb)
    if err then return nil, nil, err end
    -- get server message
    resp_code, resp_line, err = %get_status(sock)
    if err then return nil, nil, err end
    -- deal with reply
    resp_hdrs, err = %get_hdrs(sock, {})
    if err then return nil, line, err end
    -- did we get a redirect? should we automatically retry?
    if not stay and (resp_code == 301 or resp_code == 302) and 
       (method == "GET" or method == "HEAD") then 
        sock:close()
        return http_requestindirect(method, resp_hdrs["location"], 
            resp_body_cb, req_hdrs, req_body_cb, stay)
    end 
    -- get response message body if status and method combination allow one
    if has_respbody(method, resp_code) then
        err = %try_getbody(sock, resp_hdrs, resp_body_cb)
        if err then return resp_hdrs, resp_line, err end
    end
    sock:close()
    return resp_hdrs, resp_line
end

-----------------------------------------------------------------------------
-- We need fast concatenation routines for direct requests
-----------------------------------------------------------------------------
dofile("buffer.lua")

-----------------------------------------------------------------------------
-- Sends a HTTP request and retrieves the server reply
-- Input
--   method: "GET", "PUT", "POST" etc
--   url: target uniform resource locator
--   req_hdrs: request headers to send, or nil if none
--   req_body: request message body as a string, or nil if none
--   stay: should we refrain from following a server redirect message?
-- Returns
--   resp_body: response message body, or nil if failed
--   resp_hdrs: response header fields received, or nil if failed
--   resp_line: server response status line, or nil if failed
--   err: error message, or nil if successfull
-----------------------------------------------------------------------------
function http_request(method, url, req_hdrs, req_body, stay)
    local resp_hdrs, resp_line, err
    local req_body_cb = function() 
        return %req_body, strlen(%req_body) 
    end
    local resp_body = { buf = buf_create() }
    local resp_body_cb = function(chunk, err)
        if not chunk then %resp_body.buf = nil end
        buf_addstring(%resp_body.buf, chunk)
        return 1
    end
    if not req_body then req_body_cb = nil end
    resp_hdrs, resp_line, err = http_requestindirect(method, url, resp_body_cb,
        req_hdrs, req_body_cb, stay)
    return buf_getresult(resp_body.buf), resp_hdrs, resp_line, err
end

-----------------------------------------------------------------------------
-- Retrieves a URL by the method "GET"
-- Input
--   url: target uniform resource locator
--   req_hdrs: request headers to send, or nil if none
--   stay: should we refrain from following a server redirect message?
-- Returns
--   resp_body: response message body, or nil if failed
--   resp_hdrs: response header fields received, or nil if failed
--   resp_line: server response status line, or nil if failed
--   err: error message, or nil if successfull
-----------------------------------------------------------------------------
function http_get(url, req_hdrs, stay)
    return http_request("GET", url, req_hdrs, stay)
end

-----------------------------------------------------------------------------
-- Retrieves a URL by the method "GET"
-- Input
--   url: target uniform resource locator
--   resp_body_cb: response message body receive callback
--   req_hdrs: request headers to send, or nil if none
--   stay: should we refrain from following a server redirect message?
-- Returns
--   resp_body: response message body, or nil if failed
--   resp_hdrs: response header fields received, or nil if failed
--   resp_line: server response status line, or nil if failed
--   err: error message, or nil if successfull
-----------------------------------------------------------------------------
function http_getindirect(url, resp_body_cb, req_hdrs, stay)
    return http_requestindirect("GET", url, resp_body_cb, req_hdrs, nil, stay)
end

-----------------------------------------------------------------------------
-- Retrieves a URL by the method "POST"
-- Input
--   method: "GET", "PUT", "POST" etc
--   url: target uniform resource locator
--   req_hdrs: request headers to send, or nil if none
--   req_body: request message body, or nil if none
--   stay: should we refrain from following a server redirect message?
-- Returns
--   resp_body: response message body, or nil if failed
--   resp_hdrs: response header fields received, or nil if failed
--   resp_line: server response status line, or nil if failed
--   err: error message, or nil if successfull
-----------------------------------------------------------------------------
function http_post(url, req_body, req_hdrs, stay)
    return http_request("POST", url, req_hdrs, req_body, stay)
end

-----------------------------------------------------------------------------
-- Retrieves a URL by the method "POST"
-- Input
--   url: target uniform resource locator
--   resp_body_cb: response message body receive callback
--   req_body_cb: request message body send callback
--   req_hdrs: request headers to send, or nil if none
--   stay: should we refrain from following a server redirect message?
-- Returns
--   resp_body: response message body, or nil if failed
--   resp_hdrs: response header fields received, or nil if failed
--   resp_line: server response status line, or nil if failed
--   err: error message, or nil if successfull
-----------------------------------------------------------------------------
function http_getindirect(url, resp_body_cb, req_body_cb, req_hdrs, stay)
    return http_requestindirect("GET", url, resp_body_cb, req_hdrs, 
      req_body_cb, stay)
end
