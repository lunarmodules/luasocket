-----------------------------------------------------------------------------
-- SMTP support for the Lua language.
-- LuaSocket 1.5 toolkit
-- Author: Diego Nehab
-- Conforming to: RFC 821, LTN7
-- RCS ID: $Id$
-----------------------------------------------------------------------------

local Public, Private = {}, {}
local socket = _G[LUASOCKET_LIBNAME] -- get LuaSocket namespace
socket.smtp = Public  -- create smtp sub namespace

-----------------------------------------------------------------------------
-- Program constants
-----------------------------------------------------------------------------
-- timeout in secconds before we give up waiting
Public.TIMEOUT = 180
-- port used for connection
Public.PORT = 25
-- domain used in HELO command and default sendmail 
-- If we are under a CGI, try to get from environment
Public.DOMAIN = os.getenv("SERVER_NAME") or "localhost"
-- default server used to send e-mails
Public.SERVER = "localhost"

-----------------------------------------------------------------------------
-- Tries to get a pattern from the server and closes socket on error
--   sock: socket connected to the server
--   pattern: pattern to receive
-- Returns
--   received pattern on success
--   nil followed by error message on error
-----------------------------------------------------------------------------
function Private.try_receive(sock, pattern)
    local data, err = sock:receive(pattern)
    if not data then sock:close() end
    return data, err
end

-----------------------------------------------------------------------------
-- Tries to send data to the server and closes socket on error
--   sock: socket connected to the server
--   data: data to send
-- Returns
--   err: error message if any, nil if successfull
-----------------------------------------------------------------------------
function Private.try_send(sock, data)
    local sent, err = sock:send(data)
    if not sent then sock:close() end
    return err
end

-----------------------------------------------------------------------------
-- Sends a command to the server (closes sock on error)
-- Input
--   sock: server socket
--   command: command to be sent
--   param: command parameters if any
-- Returns
--   err: error message if any
-----------------------------------------------------------------------------
function Private.send_command(sock, command, param)
    local line
    if param then line = command .. " " .. param .. "\r\n"
    else line = command .. "\r\n" end
    return Private.try_send(sock, line)
end

-----------------------------------------------------------------------------
-- Gets command reply, (accepts multiple-line replies)
-- Input
--   control: control openion socket
-- Returns
--   answer: whole server reply, nil if error
--   code: reply status code or error message
-----------------------------------------------------------------------------
function Private.get_answer(control)
    local code, lastcode, sep, _
    local line, err = Private.try_receive(control)
    local answer = line
    if err then return nil, err end
    _,_, code, sep = string.find(line, "^(%d%d%d)(.)")
    if not code or not sep then return nil, answer end
    if sep == "-" then -- answer is multiline
        repeat 
            line, err = Private.try_receive(control)
            if err then return nil, err end
            _,_, lastcode, sep = string.find(line, "^(%d%d%d)(.)")
            answer = answer .. "\n" .. line
        until code == lastcode and sep == " " -- answer ends with same code
    end
    return answer, tonumber(code)
end

-----------------------------------------------------------------------------
-- Checks if a message reply code is correct. Closes control openion 
-- if not.
-- Input
--   control: control openion socket
--   success: table with successfull reply status code
-- Returns
--   code: reply code or nil in case of error
--   answer: complete server answer or system error message
-----------------------------------------------------------------------------
function Private.check_answer(control, success)
    local answer, code = Private.get_answer(control)
    if not answer then return nil, code end
    if type(success) ~= "table" then success = {success} end
    for i = 1, table.getn(success) do
        if code == success[i] then
            return code, answer
        end
    end
    control:close()
    return nil, answer
end

-----------------------------------------------------------------------------
-- Sends initial client greeting
-- Input
--   sock: server socket
-- Returns
--   code: server code if ok, nil if error
--   answer: complete server reply
-----------------------------------------------------------------------------
function Private.send_helo(sock)
    local err = Private.send_command(sock, "HELO", Public.DOMAIN)
    if err then return nil, err end
    return Private.check_answer(sock, 250)
end

-----------------------------------------------------------------------------
-- Sends openion termination command
-- Input
--   sock: server socket
-- Returns
--   code: server status code, nil if error
--   answer: complete server reply or error message
-----------------------------------------------------------------------------
function Private.send_quit(sock)
    local err = Private.send_command(sock, "QUIT")
    if err then return nil, err end
    local code, answer = Private.check_answer(sock, 221)
    sock:close()
    return code, answer
end

-----------------------------------------------------------------------------
-- Sends sender command
-- Input
--   sock: server socket
--   sender: e-mail of sender
-- Returns
--   code: server status code, nil if error
--   answer: complete server reply or error message
-----------------------------------------------------------------------------
function Private.send_mail(sock, sender)
    local param = string.format("FROM:<%s>", sender or "")
    local err = Private.send_command(sock, "MAIL", param)
    if err then return nil, err end
    return Private.check_answer(sock, 250)
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
    -- send request headers 
    for i, v in headers or {} do
        err = Private.try_send(sock, i .. ": " .. v .. "\r\n")
        if err then return err end
    end
    -- mark end of request headers
    return Private.try_send(sock, "\r\n")
end

-----------------------------------------------------------------------------
-- Sends message mime headers and body
-- Input
--   sock: server socket
--   headers: table containing all mime headers to be sent
--   body: message body
-- Returns
--   code: server status code, nil if error
--   answer: complete server reply or error message
-----------------------------------------------------------------------------
function Private.send_data(sock, headers, body)
    local err = Private.send_command(sock, "DATA")
    if err then return nil, err end
    local code, answer = Private.check_answer(sock, 354)
    if not code then return nil, answer end
    -- avoid premature end in message body
    body = string.gsub(body or "", "\n%.", "\n%.%.")
    -- mark end of message body
    body = body .. "\r\n.\r\n"
    err = Private.send_headers(sock, headers)
    if err then return nil, err end
    err = Private.try_send(sock, body)
    return Private.check_answer(sock, 250)
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
function Private.send_rcpt(sock, rcpt)
    local err
	local code, answer = nil, "No recipient specified"
    if type(rcpt) ~= "table" then rcpt = {rcpt} end
    for i = 1, table.getn(rcpt) do
        err = Private.send_command(sock, "RCPT", 
            string.format("TO:<%s>", rcpt[i]))
        if err then return nil, err end
        code, answer = Private.check_answer(sock, {250, 251})
        if not code then return code, answer end
    end
    return code, answer
end

-----------------------------------------------------------------------------
-- Starts the connection and greets server
-- Input
--   parsed: parsed URL components
-- Returns
--   sock: socket connected to server
--   err: error message if any
-----------------------------------------------------------------------------
function Private.open(server)
    local code, answer
	-- default server
	server = server or Public.SERVER
	-- connect to server and make sure we won't hang
    local sock, err = socket.connect(server, Public.PORT)
    if not sock then return nil, err end
    sock:timeout(Public.TIMEOUT)
    -- initial server greeting
    code, answer = Private.check_answer(sock, 220)
    if not code then return nil, answer end
    -- HELO
    code, answer = Private.send_helo(sock)
    if not code then return nil, answer end
    return sock
end

-----------------------------------------------------------------------------
-- Sends a message using an opened server
-- Input
--   sock: socket connected to server 
--   message: a table with the following fields:
--     from: message sender's e-mail
--     rcpt: message recipient's e-mail
--     headers: message mime headers
--     body: messge body
-- Returns
--   code: server status code, nil if error
--   answer: complete server reply
-----------------------------------------------------------------------------
function Private.send(sock, message)
    local code, answer
    -- MAIL
    code, answer = Private.send_mail(sock, message.from)
    if not code then return nil, answer end
    -- RCPT
    code, answer = Private.send_rcpt(sock, message.rcpt)
    if not code then return nil, answer end
    -- DATA
    return Private.send_data(sock, message.headers, message.body)
end

-----------------------------------------------------------------------------
-- Closes connection with server
-- Input
--   sock: socket connected to server 
-- Returns
--   code: server status code, nil if error
--   answer: complete server reply
-----------------------------------------------------------------------------
function Private.close(sock)
    -- QUIT
    return Private.send_quit(sock)
end

-----------------------------------------------------------------------------
-- Main mail function
-- Input
--   message: a table with the following fields:
--     from: message sender
--     rcpt: table containing message recipients
--     headers: table containing mime headers
--     body: message body
--     server: smtp server to be used
-- Returns
--   nil if successfull, error message in case of error
-----------------------------------------------------------------------------
function Public.mail(message)
    local sock, err = Private.open(message.server)
    if not sock then return err end
    local code, answer = Private.send(sock, message)
    if not code then return answer end
    code, answer = Private.close(sock)
    if code then return nil end
    return answer
end
