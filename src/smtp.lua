-----------------------------------------------------------------------------
-- Simple SMTP support for the Lua language using the LuaSocket toolkit.
-- Author: Diego Nehab
-- Date: 26/12/2000
-- Conforming to: RFC 821
-----------------------------------------------------------------------------

-----------------------------------------------------------------------------
-- Program constants
-----------------------------------------------------------------------------
-- timeout in secconds before we give up waiting
local TIMEOUT = 180
-- port used for connection
local PORT = 25
-- domain used in HELO command. If we are under a CGI, try to get from
-- environment
local DOMAIN = getenv("SERVER_NAME")
if not DOMAIN then
    DOMAIN = "localhost"
end

-----------------------------------------------------------------------------
-- Tries to send DOS mode lines. Closes socket on error.
-- Input
--   sock: server socket
--   line: string to be sent
-- Returns
--   err: message in case of error, nil if successfull
-----------------------------------------------------------------------------
local puts = function(sock, line)
    local err = sock:send(line .. "\r\n")
	if err then sock:close() end
	return err
end

-----------------------------------------------------------------------------
-- Tries to receive DOS mode lines. Closes socket on error.
-- Input
--   sock: server socket
-- Returns
--   line: received string if successfull, nil in case of error
--   err: error message if any
-----------------------------------------------------------------------------
local gets = function(sock)
	local line, err = sock:receive("*l")
	if err then 
		sock:close() 
		return nil, err
	end
	return line
end

-----------------------------------------------------------------------------
-- Gets a reply from the server and close connection if it is wrong
-- Input
--   sock: server socket
--   accept: acceptable errorcodes
-- Returns
--   code: server reply code. nil if error
--   line: complete server reply message or error message
-----------------------------------------------------------------------------
local get_reply = function(sock, accept)
    local line, err = %gets(sock) 
    if line then
		if type(accept) ~= "table" then accept = {accept} end
        local _,_, code = strfind(line, "^(%d%d%d)")
		if not code then return nil, line end
		code = tonumber(code)
		for i = 1, getn(accept) do
			if code == accept[i] then return code, line end
		end
		sock:close()
		return nil, line
	end
    return nil, err
end

-----------------------------------------------------------------------------
-- Sends a command to the server
-- Input
--   sock: server socket
--   command: command to be sent
--   param: command parameters if any
-- Returns
--   err: error message if any
-----------------------------------------------------------------------------
local send_command = function(sock, command, param)
    local line
    if param then line = command .. " " .. param
    else line = command end
    return %puts(sock, line)
end

-----------------------------------------------------------------------------
-- Gets the initial server greeting
-- Input
--   sock: server socket
-- Returns
--   code: server status code, nil if error
--   answer: complete server reply
-----------------------------------------------------------------------------
local get_helo = function(sock)
    return %get_reply(sock, 220)
end

-----------------------------------------------------------------------------
-- Sends initial client greeting
-- Input
--   sock: server socket
-- Returns
--   code: server status code, nil if error
--   answer: complete server reply
-----------------------------------------------------------------------------
local send_helo = function(sock)
    local err = %send_command(sock, "HELO", %DOMAIN)
    if not err then
        return %get_reply(sock, 250)
	else return nil, err end
end

-----------------------------------------------------------------------------
-- Sends mime headers
-- Input
--   sock: server socket
--   mime: table with mime headers to be sent
-- Returns
--   err: error message if any
-----------------------------------------------------------------------------
local send_mime = function(sock, mime)
	local err
	mime = mime or {}
	-- send all headers
	for name,value in mime do
		err = sock:send(name .. ": " .. value .. "\r\n")
		if err then 
			sock:close()
			return err 
		end
	end
	-- end mime part
	err = sock:send("\r\n")
	if err then sock:close() end
	return err
end

-----------------------------------------------------------------------------
-- Sends connection termination command
-- Input
--   sock: server socket
-- Returns
--   code: server status code, nil if error
--   answer: complete server reply
-----------------------------------------------------------------------------
local send_quit = function(sock)
	local code, answer
    local err = %send_command(sock, "QUIT")
    if not err then
        code, answer = %get_reply(sock, 221)
		sock:close()
		return code, answer
    else return nil, err end
end

-----------------------------------------------------------------------------
-- Sends sender command
-- Input
--   sock: server socket
--   sender: e-mail of sender
-- Returns
--   code: server status code, nil if error
--   answer: complete server reply
-----------------------------------------------------------------------------
local send_mail = function(sock, sender)
    local param = format("FROM:<%s>", sender)
    local err = %send_command(sock, "MAIL", param)
    if not err then
        return %get_reply(sock, 250)
	else return nil, err end
end

-----------------------------------------------------------------------------
-- Sends message mime headers and body
-- Input
--   sock: server socket
--   mime: table containing all mime headers to be sent
--   body: message body
-- Returns
--   code: server status code, nil if error
--   answer: complete server reply
-----------------------------------------------------------------------------
local send_data = function (sock, mime, body)
	local err = %send_command(sock, "DATA")
    if not err then
		local code, answer = %get_reply(sock, 354)
		if not code then return nil, answer end
		-- avoid premature end in message body
    	body = gsub(body or "", "\n%.", "\n%.%.")
		-- mark end of message body
    	body = body .. "\r\n."
       	err = %send_mime(sock, mime)
		if err then return nil, err end
        err = %puts(sock, body)
        return %get_reply(sock, 250)
    else return nil, err end
end

-----------------------------------------------------------------------------
-- Sends recipient list command
-- Input
--   sock: server socket
--   rcpt: lua table with recipient list
-- Returns
--   code: server status code, nil if error
--   answer: complete server reply
-----------------------------------------------------------------------------
local send_rcpt = function(sock, rcpt)
    local err, code, answer
	if type(rcpt) ~= "table" then rcpt = {rcpt} end
    for i = 1, getn(rcpt) do
        err = %send_command(sock, "RCPT", format("TO:<%s>", rcpt[i]))
        if not err then
            code, answer = %get_reply(sock, {250, 251})
			if not code then return code, answer end
        else return nil, err end
    end
    return code, answer
end

-----------------------------------------------------------------------------
-- Sends verify recipient command
-- Input
--   sock: server socket
--   user: user to be verified
-- Returns
--   code: server status code, nil if error
--   answer: complete server reply
-----------------------------------------------------------------------------
local send_vrfy = function (sock, user)
    local err = %send_command(sock, "VRFY", format("<%s>", user))
    if not err then
        return %get_reply(sock, {250, 251})
	else return nil, err end
end

-----------------------------------------------------------------------------
-- Connection oriented mail functions
-----------------------------------------------------------------------------
function smtp_connect(server)
	local code, answer
    -- connect to server
    local sock, err = connect(server, %PORT)
    if not sock then return nil, err end
    sock:timeout(%TIMEOUT)
    -- initial server greeting
    code, answer = %get_helo(sock)
    if not code then return nil, answer end
    -- HELO
    code, answer = %send_helo(sock)
    if not code then return nil, answer end
	return sock
end

function smtp_send(sock, from, rcpt, mime, body)
	local code, answer
    -- MAIL
    code, answer = %send_mail(sock, from)
    if not code then return nil, answer end
    -- RCPT
    code, answer = %send_rcpt(sock, rcpt)
    if not code then return nil, answer end
    -- DATA
    return %send_data(sock, mime, body)
end

function smtp_close(sock)
    -- QUIT
    return %send_quit(sock)
end

-----------------------------------------------------------------------------
-- Main mail function
-- Input
--   from: message sender
--   rcpt: table containing message recipients
--   mime: table containing mime headers
--   body: message body
--   server: smtp server to be used
-- Returns
--   nil if successfull, error message in case of error
-----------------------------------------------------------------------------
function smtp_mail(from, rcpt, mime, body, server)
	local sock, err = smtp_connect(server)
	if not sock then return err end
	local code, answer = smtp_send(sock, from, rcpt, mime, body)
	if not code then return answer end
	code, answer = smtp_close(sock)
	if not code then return answer
	else return nil end
end

--===========================================================================
-- Compatibility functions
--===========================================================================
-----------------------------------------------------------------------------
-- Converts a comma separated list into a Lua table with one entry for each
-- list element.
-- Input
--   str: string containing the list to be converted
--   tab: table to be filled with entries
-- Returns
--   a table t, where t.n is the number of elements with an entry t[i] 
--   for each element
-----------------------------------------------------------------------------
local fill = function(str, tab)
	gsub(str, "([^%s,]+)", function (w) tinsert(%tab, w) end)
	return tab
end

-----------------------------------------------------------------------------
-- Client mail function, implementing CGILUA 3.2 interface
-----------------------------------------------------------------------------
function mail(msg)
  local rcpt = {}
  local mime = {}
  mime["Subject"] = msg.subject
  mime["To"] = msg.to
  mime["From"] = msg.from
  %fill(msg.to, rcpt)
  if msg.cc then 
    %fill(msg.cc, rcpt) 
    mime["Cc"] = msg.cc
  end
  if msg.bcc then
    %fill(msg.bcc, rcpt)
  end
  rcpt.n = nil
  return %smtp_mail(msg.from, rcpt, mime, msg.message, msg.mailserver)
end
