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
local USERAGENT = "LuaSocket 1.2 HTTP 1.1"

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
--   headers: a table that might already contain headers
-- Returns
--   headers: a table with all headers fields in the form
--        {name_1 = "value_1", name_2 = "value_2" ... name_n = "value_n"} 
--        all name_i are lowercase
--   nil and error message in case of error
-----------------------------------------------------------------------------
local get_headers = function(sock, headers)
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
        if headers[name] then headers[name] = headers[name] .. ", " .. value
        else headers[name] = value end
    end
    return headers
end

-----------------------------------------------------------------------------
-- Receives a chunked message body
-- Input
--   sock: socket connected to the server
-- Returns
--   body: a string containing the body of the message
--   nil and error message in case of error
-----------------------------------------------------------------------------
local try_getchunked = function(sock)
    local chunk_size, line, err
    local body = ""
    repeat 
        -- get chunk size, skip extention
        line, err = %try_get(sock)
        if err then return nil, err end
        chunk_size = tonumber(gsub(line, ";.*", ""), 16)
        if not chunk_size then 
            sock:close()
            return nil, "invalid chunk size"
        end
        -- get chunk
        line, err = %try_get(sock, chunk_size) 
        if err then return nil, err end
        -- concatenate new chunk
        body = body .. line
        -- skip blank line
        _, err = %try_get(sock)
        if err then return nil, err end
    until chunk_size <= 0
	return body
end

-----------------------------------------------------------------------------
-- Receives http body
-- Input
--   sock: socket connected to the server
--   headers: response header fields
-- Returns
--    body: a string containing the body of the document
--    nil and error message in case of error
-- Obs:
--    headers: headers might be modified by chunked transfer
-----------------------------------------------------------------------------
local get_body = function(sock, headers)
    local body, err
    if headers["transfer-encoding"] == "chunked" then
		body, err = %try_getchunked(sock)
		if err then return nil, err end
        -- store extra entity headers
        --_, err = %get_headers(sock, headers)
        --if err then return nil, err end
    elseif headers["content-length"] then
        body, err = %try_get(sock, tonumber(headers["content-length"]))
        if err then return nil, err end
    else 
        -- get it all until connection closes!
        body, err = %try_get(sock, "*a") 
        if err then return nil, err end
    end
    -- return whole body
    return body
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
-- Tries to send request body, using chunked transfer-encoding
-- Apache, for instance, accepts only 8kb of body in a post to a CGI script
-- if we use only the content-length header field...
-- Input
--   sock: socket connected to the server
--   body: body to be sent in request
-- Returns
--   err: nil in case of success, error message otherwise
-----------------------------------------------------------------------------
local try_sendchunked = function(sock, body)
    local wanted = strlen(body)
    local first = 1
    local chunk_size
    local err
    while wanted > 0 do
        chunk_size = min(wanted, 1024)
        err = %try_send(sock, format("%x\r\n", chunk_size))
        if err then return err end
        err = %try_send(sock, strsub(body, first, first + chunk_size - 1))
        if err then return err end
        err = %try_send(sock, "\r\n")
        if err then return err end
        wanted = wanted - chunk_size
        first = first + chunk_size
    end
    err = %try_send(sock, "0\r\n")
    return err
end

-----------------------------------------------------------------------------
-- Sends a http request message through socket
-- Input
--   sock: socket connected to the server
--   method: request method to  be used
--   path: url path
--   headers: request headers to be sent
--   body: request message body, if any
-- Returns
--   err: nil in case of success, error message otherwise
-----------------------------------------------------------------------------
local send_request = function(sock, method, path, headers, body)
    local err = %try_send(sock, method .. " " .. path .. " HTTP/1.1\r\n")
    if err then return err end
    for i, v in headers do
        err = %try_send(sock, i .. ": " .. v .. "\r\n")
        if err then return err end
    end
    err = %try_send(sock, "\r\n")
    --if not err and body then err = %try_sendchunked(sock, body) end
    if not err and body then err = %try_send(sock, body) end
    return err
end

-----------------------------------------------------------------------------
-- Determines if we should read a message body from the server response
-- Input
--   method: method used in request
--   code: server response status code
-- Returns
--   1 if a message body should be processed, nil otherwise
-----------------------------------------------------------------------------
function has_responsebody(method, code)
    if method == "HEAD" then return nil end
    if code == 204 or code == 304 then return nil end
    if code >= 100 and code < 200 then return nil end
    return 1
end

-----------------------------------------------------------------------------
-- Converts field names to lowercase and add message body size specification
-- Input
--   headers: request header fields
--   parsed: parsed url components
--   body: request message body, if any
-- Returns
--   lower: a table with the same headers, but with lowercase field names
-----------------------------------------------------------------------------
local fill_headers = function(headers, parsed, body)
    local lower = {}
    headers = headers or {}
    for i,v in headers do
        lower[strlower(i)] = v
    end
    --if body then lower["transfer-encoding"] = "chunked" end
    if body then lower["content-length"] = tostring(strlen(body)) end
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
-- We need base64 convertion routines for Basic Authentication Scheme
-----------------------------------------------------------------------------
dofile("base64.lua")

-----------------------------------------------------------------------------
-- Sends a HTTP request and retrieves the server reply
-- Input
--   method: "GET", "PUT", "POST" etc
--   url: target uniform resource locator
--   headers: request headers to send
--   body: request message body
-- Returns
--   resp_body: response message body, if successfull
--   resp_hdrs: response header fields received, if sucessfull
--   line: server response status line, if successfull
--   err: error message if any
-----------------------------------------------------------------------------
function http_request(method, url, headers, body)
    local sock, err
    local resp_hdrs, response_body
    local line, code
    -- get url components
    local parsed = %split_url(url, {port = %PORT, path ="/"})
    -- methods are case sensitive
    method = strupper(method)
    -- fill default headers
    headers = %fill_headers(headers, parsed, body)
    -- try connection
    sock, err = connect(parsed.host, parsed.port)
    if not sock then return nil, nil, nil, err end
    -- set connection timeout
    sock:timeout(%TIMEOUT)
    -- send request
    err = %send_request(sock, method, parsed.path, headers, body)
    if err then return nil, nil, nil, err end
    -- get server message
    code, line, err = %get_status(sock)
    if err then return nil, nil, nil, err end
    -- deal with reply
    resp_hdrs, err = %get_headers(sock, {})
    if err then return nil, nil, line, err end
    -- get body if status and method allow one
    if has_responsebody(method, code) then
        resp_body, err = %get_body(sock, resp_hdrs)
        if err then return nil, resp_hdrs, line, err end
    end
    sock:close()
    -- should we automatically retry?
    if (code == 301 or code == 302) then
        if (method == "GET" or method == "HEAD") and resp_hdrs["location"] then 
            return http_request(method, resp_hdrs["location"], headers, body)
        else return nil, resp_hdrs, line end
    end
    return resp_body, resp_hdrs, line
end

-----------------------------------------------------------------------------
-- Retrieves a URL by the method "GET"
-- Input
--   url: target uniform resource locator
--   headers: request headers to send
-- Returns
--   body: response message body, if successfull
--   headers: response header fields, if sucessfull
--   line: response status line, if successfull
--   err: error message, if any
-----------------------------------------------------------------------------
function http_get(url, headers)
    return http_request("GET", url, headers)
end

-----------------------------------------------------------------------------
-- Retrieves a URL by the method "GET"
-- Input
--   url: target uniform resource locator
--   body: request message body
--   headers: request headers to send
-- Returns
--   body: response message body, if successfull
--   headers: response header fields, if sucessfull
--   line: response status line, if successfull
--   err: error message, if any
-----------------------------------------------------------------------------
function http_post(url, body, headers)
    return http_request("POST", url, headers, body)
end
