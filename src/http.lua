-----------------------------------------------------------------------------
-- Simple HTTP/1.1 support for the Lua language using the LuaSocket toolkit.
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
local USERAGENT = "LuaSocket/HTTP 1.0"

-----------------------------------------------------------------------------
-- Tries to get a line from the server or close socket if error
--   sock: socket connected to the server
-- Returns
--   line: line received or nil in case of error
--   err: error message if any
-----------------------------------------------------------------------------
local try_getline = function(sock)
	line, err = sock:receive()
	if err then
		sock:close()
		return nil, err
	end
	return line
end

-----------------------------------------------------------------------------
-- Tries to send a line to the server or close socket if error
--   sock: socket connected to the server
--   line: line to send
-- Returns
--   err: error message if any
-----------------------------------------------------------------------------
local try_sendline = function(sock, line)
	err = sock:send(line)
	if err then sock:close() end
	return err
end

-----------------------------------------------------------------------------
-- Retrieves status from http reply
-- Input
--   reply: http reply string
-- Returns
--   status: integer with status code
-----------------------------------------------------------------------------
local get_status = function(reply)
	local _,_, status = strfind(reply, " (%d%d%d) ")
	return tonumber(status)
end

-----------------------------------------------------------------------------
-- Receive server reply messages
-- Input
--   sock: server socket
-- Returns
--   status: server reply status code or nil if error
--   reply: full server reply
--   err: error message if any
-----------------------------------------------------------------------------
local get_reply = function(sock)
    local reply, err
    reply, err = %try_getline(sock)
    if not err then return %get_status(reply), reply
    else return nil, nil, err end
end

-----------------------------------------------------------------------------
-- Receive and parse mime headers
-- Input
--   sock: server socket
--     mime: a table that might already contain mime headers
-- Returns
--   mime: a table with all mime headers in the form
--        {name_1 = "value_1", name_2 = "value_2" ... name_n = "value_n"} 
--        all name_i are lowercase
--   nil and error message in case of error
-----------------------------------------------------------------------------
local get_mime = function(sock, mime)
    local line, err
    local name, value
	-- get first line
    line, err = %try_getline(sock)
	if err then return nil, err end
    -- headers go until a blank line is found
    while line ~= "" do
        -- get field-name and value
        _,_, name, value = strfind(line, "(.-):%s*(.*)")
        name = strlower(name)
        -- get next line (value might be folded)
        line, err = %try_getline(sock)
		if err then return nil, err end
        -- unfold any folded values
        while not err and line ~= "" and (strsub(line, 1, 1) == " ") do
            value = value .. line
            line, err = %try_getline(sock)
			if err then return nil, err end
        end
        -- save pair in table
        if mime[name] then
            -- join any multiple field
            mime[name] = mime[name] .. ", " .. value
        else
            -- new field
            mime[name] = value
        end
    end
    return mime
end

-----------------------------------------------------------------------------
-- Receives http body
-- Input
--   sock: server socket
--   mime: initial mime headers
-- Returns
--    body: a string containing the body of the document
--    nil and error message in case of error
-- Obs:
--    mime: headers might be modified by chunked transfer
-----------------------------------------------------------------------------
local get_body = function(sock, mime)
    local body, err
    if mime["transfer-encoding"] == "chunked" then
		local chunk_size, line
    	body = ""
        repeat 
            -- get chunk size, skip extention
            line, err = %try_getline(sock)
			if err then return nil, err end
            chunk_size = tonumber(gsub(line, ";.*", ""), 16)
			if not chunk_size then 
				sock:close()
				return nil, "invalid chunk size"
			end
        	-- get chunk
			line, err = sock:receive(chunk_size) 
			if err then 
				sock:close()
				return nil, err 
			end
            -- concatenate new chunk
            body = body .. line
            -- skip blank line
            _, err = %try_getline(sock)
			if err then return nil, err end
        until chunk_size <= 0
        -- store extra mime headers
        --_, err = %get_mime(sock, mime)
		--if err then return nil, err end
    elseif mime["content-length"] then
        body, err = sock:receive(tonumber(mime["content-length"]))
		if err then 
			sock:close()
			return nil, err 
		end
    else 
        -- get it all until connection closes!
        body, err = sock:receive("*a") 
		if err then 
			sock:close()
			return nil, err 
		end
    end
    -- return whole body
    return body
end

-----------------------------------------------------------------------------
-- Parses a url and returns its scheme, user, password, host, port 
-- and path components, according to RFC 1738, Uniform Resource Locators (URL),
-- of December 1994
-- Input
--   url: unique resource locator desired
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
-- Sends a GET message through socket
-- Input
--   socket: http connection socket
--   path: path requested
--   mime: mime headers to send in request
-- Returns
--   err: nil in case of success, error message otherwise
-----------------------------------------------------------------------------
local send_get = function(sock, path, mime)
	local err = %try_sendline(sock, "GET " .. path .. " HTTP/1.1\r\n")
	if err then return err end
	for i, v in mime do
    	err = %try_sendline(sock, i .. ": " .. v .. "\r\n")
		if err then return err end
	end
    err = %try_sendline(sock, "\r\n")
	return err
end

-----------------------------------------------------------------------------
-- Converts field names to lowercase
-- Input
--   headers: user header fields
--   parsed: parsed url components
-- Returns
--   mime: a table with the same headers, but with lowercase field names
-----------------------------------------------------------------------------
local fill_headers = function(headers, parsed)
	local mime = {}
	headers = headers or {}
	for i,v in headers do
		mime[strlower(i)] = v
	end
	mime["connection"] = "close"
	mime["host"] = parsed.host
	mime["user-agent"] = %USERAGENT
	if parsed.user and parsed.pass then -- Basic Authentication
		mime["authorization"] = "Basic ".. 
			base64(parsed.user .. ":" .. parsed.pass)
	end
	return mime
end

-----------------------------------------------------------------------------
-- We need base64 convertion routines for Basic Authentication Scheme
-----------------------------------------------------------------------------
dofile("base64.lua")

-----------------------------------------------------------------------------
-- Downloads and receives a http url, with its mime headers
-- Input
--   url: unique resource locator desired
--   headers: headers to send with request
--   tried: is this an authentication retry?
-- Returns
--   body: document body, if successfull
--   mime: headers received with document, if sucessfull
--   reply: server reply, if successfull
--   err: error message, if any
-----------------------------------------------------------------------------
function http_get(url, headers)
    local sock, err, mime, body, status, reply
    -- get url components
    local parsed = %split_url(url, {port = %PORT, path ="/"})
	-- fill default headers
	headers = %fill_headers(headers, parsed)
	-- try connection
    sock, err = connect(parsed.host, parsed.port)
    if not sock then return nil, nil, nil, err end
	-- set connection timeout
	sock:timeout(%TIMEOUT)
    -- send request
	err = %send_get(sock, parsed.path, headers)
	if err then return nil, nil, nil, err end
    -- get server message
    status, reply, err = %get_reply(sock)
	if err then return nil, nil, nil, err end
    -- get url accordingly
    if status == 200 then -- ok, go on and get it
        mime, err = %get_mime(sock, {})
		if err then return nil, nil, reply, err end
        body, err = %get_body(sock, mime)
		if err then return nil, mime, reply, err end
        sock:close()
    	return body, mime, reply
    elseif status == 301 then -- moved permanently, try again
        mime = %get_mime(sock, {})
        sock:close()
        if mime["location"] then return http_get(mime["location"], headers)
        else return nil, mime, reply end
	elseif status == 401 then 
        mime, err = %get_mime(sock, {})
		if err then return nil, nil, reply, err end
		return nil, mime, reply
	end
	return nil, nil, reply
end
