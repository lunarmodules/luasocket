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
local try_send = function(sock, line)
    local err = sock:send(line .. "\r\n")
print(line)
    if err then sock:close() end
    return err
end

-----------------------------------------------------------------------------
-- Gets command reply, (accepts multiple-line replies)
-- Input
--   control: control connection socket
-- Returns
--   answer: whole server reply, nil if error
--   code: reply status code or error message
-----------------------------------------------------------------------------
local get_answer = function(control)
    local code, lastcode, sep
    local line, err = control:receive()
    local answer = line
    if err then return nil, err end
print(line)
    _,_, code, sep = strfind(line, "^(%d%d%d)(.)")
    if not code or not sep then return nil, answer end
    if sep == "-" then -- answer is multiline
        repeat 
            line, err = control:receive()
            if err then return nil, err end
print(line)
            _,_, lastcode, sep = strfind(line, "^(%d%d%d)(.)")
            answer = answer .. "\n" .. line
        until code == lastcode and sep == " " -- answer ends with same code
    end
    return answer, tonumber(code)
end

-----------------------------------------------------------------------------
-- Checks if a message reply code is correct. Closes control connection 
-- if not.
-- Input
--   control: control connection socket
--   success: table with successfull reply status code
-- Returns
--   code: reply code or nil in case of error
--   answer: complete server answer or system error message
-----------------------------------------------------------------------------
local check_answer = function(control, success)
    local answer, code = %get_answer(control)
    if not answer then 
        control:close()
        return nil, code
    end
    if type(success) ~= "table" then success = {success} end
    for i = 1, getn(success) do
        if code == success[i] then
            return code, answer
        end
    end
    control:close()
    return nil, answer
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
local send_command = function(sock, command, param)
    local line
    if param then line = command .. " " .. param
    else line = command end
    return %try_send(sock, line)
end

-----------------------------------------------------------------------------
-- Sends initial client greeting
-- Input
--   sock: server socket
-- Returns
--   code: server code if ok, nil if error
--   answer: complete server reply
-----------------------------------------------------------------------------
local send_helo = function(sock)
    local err = %send_command(sock, "HELO", %DOMAIN)
    if err then return nil, err end
    return %check_answer(sock, 250)
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
--   answer: complete server reply or error message
-----------------------------------------------------------------------------
local send_quit = function(sock)
    local err = %send_command(sock, "QUIT")
    if err then return nil, err end
    local code, answer = %check_answer(sock, 221)
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
local send_mail = function(sock, sender)
    local param = format("FROM:<%s>", sender)
    local err = %send_command(sock, "MAIL", param)
    if err then return nil, err end
    return %check_answer(sock, 250)
end

-----------------------------------------------------------------------------
-- Sends message mime headers and body
-- Input
--   sock: server socket
--   mime: table containing all mime headers to be sent
--   body: message body
-- Returns
--   code: server status code, nil if error
--   answer: complete server reply or error message
-----------------------------------------------------------------------------
local send_data = function (sock, mime, body)
    local err = %send_command(sock, "DATA")
    if err then return nil, err end
    local code, answer = %check_answer(sock, 354)
    if not code then return nil, answer end
    -- avoid premature end in message body
    body = gsub(body or "", "\n%.", "\n%.%.")
    -- mark end of message body
    body = body .. "\r\n."
    err = %send_mime(sock, mime)
    if err then return nil, err end
    err = %try_send(sock, body)
    return %check_answer(sock, 250)
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
        if err then return nil, err end
        code, answer = %check_answer(sock, {250, 251})
        if not code then return code, answer end
    end
    return code, answer
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
    code, answer = %check_answer(sock, 220)
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
    if code then return nil end
    return answer
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
    if msg.bcc then %fill(msg.bcc, rcpt) end
    rcpt.n = nil
    return %smtp_mail(msg.from, rcpt, mime, msg.message, msg.mailserver)
end
