-----------------------------------------------------------------------------
-- Simple FTP support for the Lua language using the LuaSocket 1.3b toolkit.
-- Author: Diego Nehab
-- Date: 26/12/2000
-- Conforming to: RFC 959
-----------------------------------------------------------------------------

-----------------------------------------------------------------------------
-- Program constants
-----------------------------------------------------------------------------
-- timeout in seconds before the program gives up on a connection
local TIMEOUT = 60
-- default port for ftp service
local PORT = 21
-- this is the default anonymous password. used when no password is
-- provided in url. should be changed for your e-mail.
local EMAIL = "anonymous@anonymous.org"
-- block size used in transfers
local BLOCKSIZE = 4096

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
-- Gets ip and port for data connection from PASV answer
-- Input
--   pasv: PASV command answer
-- Returns
--   ip: string containing ip for data connection
--   port: port for data connection
-----------------------------------------------------------------------------
local get_pasv = function(pasv)
	local a,b,c,d,p1,p2
	local ip, port
	_,_, a, b, c, d, p1, p2 =
		strfind(pasv, "(%d*),(%d*),(%d*),(%d*),(%d*),(%d*)")
	if not (a and b and c and d and p1 and p2) then
		return nil, nil
	end
	ip = format("%d.%d.%d.%d", a, b, c, d)
	port = tonumber(p1)*256 + tonumber(p2)
	return ip, port
end

-----------------------------------------------------------------------------
-- Sends a FTP command through socket
-- Input
--   control: control connection socket
--   cmd: command
--   arg: command argument if any
-- Returns
--   error message in case of error, nil otherwise
-----------------------------------------------------------------------------
local send_command = function(control, cmd, arg)
	local line, err
	if arg then line = cmd .. " " .. arg .. "\r\n" 
	else line = cmd .. "\r\n" end
	err = control:send(line)
	return err
end

-----------------------------------------------------------------------------
-- Gets FTP command answer, unfolding if neccessary
-- Input
--   control: control connection socket
-- Returns
--   answer: whole server reply, nil if error
--   code: answer status code or error message
-----------------------------------------------------------------------------
local get_answer = function(control)
	local code, lastcode, sep
	local line, err = control:receive()
	local answer = line
	if err then return nil, err end
	_,_, code, sep = strfind(line, "^(%d%d%d)(.)")
	if not code or not sep then return nil, answer end
	if sep == "-" then -- answer is multiline
		repeat 
			line, err = control:receive()
			if err then return nil, err end
			_,_, lastcode, sep = strfind(line, "^(%d%d%d)(.)")
			answer = answer .. "\n" .. line
		until code == lastcode and sep == " " -- answer ends with same code
	end
	return answer, tonumber(code)
end

-----------------------------------------------------------------------------
-- Checks if a message return is correct. Closes control connection if not.
-- Input
--   control: control connection socket
--   success: table with successfull reply status code
-- Returns
--   code: reply code or nil in case of error
--   answer: server complete answer or system error message
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
-- Trys a command on control socked, in case of error, the control connection 
-- is closed.
-- Input
--   control: control connection socket
--   cmd: command
--   arg: command argument or nil if no argument
--   success: table with successfull reply status code
-- Returns
--   code: reply code or nil in case of error
--   answer: server complete answer or system error message
-----------------------------------------------------------------------------
local try_command = function(control, cmd, arg, success)
	local err = %send_command(control, cmd, arg)
	if err then 
		control:close()
		return nil, err
	end
	local code, answer = %check_answer(control, success)
	if not code then return nil, answer end
	return code, answer
end

-----------------------------------------------------------------------------
-- Creates a table with all directories in path
-- Input
--   file: abolute path to file
-- Returns
--   a table with the following fields
--     name: filename
--     path: directory to file
--     isdir: is it a directory?
-----------------------------------------------------------------------------
local split_path  = function(file)
    local parsed = {}
    file = gsub(file, "(/)$", function(i) %parsed.isdir = i end)
    if not parsed.isdir then
        file = gsub(file, "([^/]+)$", function(n) %parsed.name = n end)
    end
    file = gsub(file, "/$", "")
    file = gsub(file, "^/", "")
    if file == "" then file = nil end
    parsed.path = file
    if parsed.path or parsed.name or parsed.isdir then return parsed end
end

-----------------------------------------------------------------------------
-- Check server greeting
-- Input
--   control: control connection with server
-- Returns
--   code: nil if error
--   answer: server answer or error message
-----------------------------------------------------------------------------
local check_greeting = function(control)
	local code, answer = %check_answer(control, {120, 220})
	if not code then return nil, answer end
	if code == 120 then -- please try again, somewhat busy now...
		code, answer = %check_answer(control, {220})
	end
	return code, answer
end

-----------------------------------------------------------------------------
-- Log in on server
-- Input
--   control: control connection with server
--   user: user name
--   pass: user password if any
-- Returns
--   code: nil if error
--   answer: server answer or error message
-----------------------------------------------------------------------------
local login = function(control, user, pass)
	local code, answer = %try_command(control, "user", parsed.user, {230, 331})
	if not code then return nil, answer end
	if code == 331 and parsed.pass then -- need pass and we have pass
		code, answer = %try_command(control, "pass", parsed.pass, {230, 202})
	end
	return code, answer
end

-----------------------------------------------------------------------------
-- Change to target directory
-- Input
--   control: socket for control connection with server
--   path: directory to change to
-- Returns
--   code: nil if error
--   answer: server answer or error message
-----------------------------------------------------------------------------
local cwd = function(control, path)
	local code, answer = 250, "Home directory used"
	if path then
		code, answer = %try_command(control, "cwd", path, {250})
	end
	return code, answer
end

-----------------------------------------------------------------------------
-- Change to target directory
-- Input
--   control: socket for control connection with server
-- Returns
--   server: server socket bound to local address, nil if error
--   answer: error message if any
-----------------------------------------------------------------------------
local port = function(control)
	local code, answer
	local server, ctl_ip
	ctl_ip, answer = control:getsockname()
	server, answer = bind(ctl_ip, 0)
	server:timeout(%TIMEOUT)
	local ip, p, ph, pl
	ip, p = server:getsockname()
	pl = mod(p, 256)
	ph = (p - pl)/256
    local arg = gsub(format("%s,%d,%d", ip, ph, pl), "%.", ",")
	code, answer = %try_command(control, "port", arg, {200})
	if not code then 
		control:close()
		server:close()
		return nil, answer
	else return server end
end

-----------------------------------------------------------------------------
-- Closes control connection with server
-- Input
--   control: control connection with server
-- Returns
--   code: nil if error
--   answer: server answer or error message
-----------------------------------------------------------------------------
local logout = function(control)
	local code, answer = %try_command(control, "quit", nil, {221})
	if not code then return nil, answer end
	control:close()
	return code, answer
end

-----------------------------------------------------------------------------
-- Receives data and send it to a callback
-- Input
--   data: data connection
--   callback: callback to return file contents
-- Returns
--   nil if successfull, or an error message in case of error
-----------------------------------------------------------------------------
local receive_indirect = function(data, callback)
	local chunk, err, res
	while not err do
		chunk, err = data:receive(%BLOCKSIZE)
		if err == "closed" then err = "done" end
		res = callback(chunk, err)
		if not res then break end
	end
end

-----------------------------------------------------------------------------
-- Retrieves file or directory listing
-- Input
--   control: control connection with server
--   server: server socket bound to local address
--   file: file name under current directory
--   isdir: is file a directory name?
--   callback: callback to receive file contents
-- Returns
--   err: error message in case of error, nil otherwise
-----------------------------------------------------------------------------
local retrieve = function(control, server, file, isdir, callback)
	local code, answer
	local data
	-- ask server for file or directory listing accordingly
	if isdir then code, answer = %try_command(control, "nlst", file, {150, 125})
	else code, answer = %try_command(control, "retr", file, {150, 125}) end
	data, answer = server:accept()
	server:close()
	if not data then 
		control:close()
		return answer 
	end
	answer = %receive_indirect(data, callback)
	if answer then 
		control:close()
		return answer
	end
	data:close()
	-- make sure file transfered ok
	code, answer = %check_answer(control, {226, 250})
	if not code then return answer end
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
-- Stores a file
-- Input
--   control: control connection with server
--   server: server socket bound to local address
--   file: file name under current directory
--   send_cb: callback to produce the file contents
-- Returns
--   code: return code, nil if error
--   answer: server answer or error message
-----------------------------------------------------------------------------
local store = function(control, server, file, send_cb)
	local data
	local code, answer = %try_command(control, "stor", file, {150, 125})
	if not code then 
		control:close()
		return nil, answer 
	end
	-- start data connection
	data, answer = server:accept()
	server:close()
	if not data then 
		control:close()
		return nil, answer 
	end
	-- send whole file 
	err = %try_sendindirect(data, send_cb, send_cb())
	if err then 
		control:close()
		return nil, err
	end
	-- close connection to inform that file transmission is complete
	data:close()
	-- check if file was received correctly
	return %check_answer(control, {226, 250})
end

-----------------------------------------------------------------------------
-- Change transfer type
-- Input
--   control: control connection with server
--   type: new transfer type
-- Returns
--   code: nil if error
--   answer: server answer or error message
-----------------------------------------------------------------------------
local change_type = function(control, type)
	if type == "b" then type = "i" else type = "a" end
	return %try_command(control, "type", type, {200})
end

-----------------------------------------------------------------------------
-- Retrieve a file from a ftp server
-- Input
--   url: file location
--   receive_cb: callback to receive file contents
--   type: "binary" or "ascii"
-- Returns
--   err: error message if any
-----------------------------------------------------------------------------
function ftp_getindirect(url, receive_cb, type)
	local control, server, data, err
	local answer, code, server, pfile, file
	parsed = %split_url(url, {user = "anonymous", port = 21, pass = %EMAIL})
	-- start control connection
	control, err = connect(parsed.host, parsed.port)
	if not control then return err end
	control:timeout(%TIMEOUT)
	-- get and check greeting
	code, answer = %check_greeting(control)
	if not code then return answer end
	-- try to log in
	code, answer = %login(control, parsed.user, parsed.pass)
	if not code then return answer end
	-- go to directory
	pfile = %split_path(parsed.path)
	if not pfile then return "invalid path" end
	code, answer = %cwd(control, pfile.path)
	if not code then return answer end
	-- change to binary type?
	code, answer = %change_type(control, type)
	if not code then return answer end
	-- setup passive connection
	server, answer = %port(control)
	if not server then return answer end
	-- ask server to send file or directory listing
	err = %retrieve(control, server, pfile.name, pfile.isdir, receive_cb)
	if err then return err end
	-- disconnect
	%logout(control)
end

-----------------------------------------------------------------------------
-- Uploads a file to a FTP server
-- Input
--   url: file location
--   send_cb: callback to produce the file contents
--   type: "binary" or "ascii"
-- Returns
--   err: error message if any
-----------------------------------------------------------------------------
function ftp_putindirect(url, send_cb, type)
	local control, data
	local answer, code, server, file, pfile
	parsed = %split_url(url, {user = "anonymous", port = 21, pass = %EMAIL})
	-- start control connection
	control, answer = connect(parsed.host, parsed.port)
	if not control then return answer end
	control:timeout(%TIMEOUT)
	-- get and check greeting
	code, answer = %check_greeting(control)
	if not code then return answer end
	-- try to log in
	code, answer = %login(control, parsed.user, parsed.pass)
	if not code then return answer end
	-- go to directory
	pfile = %split_path(parsed.path)
	if not pfile or pfile.isdir then return "invalid path" end
	code, answer = %cwd(control, pfile.path)
	if not code then return answer end
	-- change to binary type?
	code, answer = %change_type(control, type)
	if not code then return answer end
	-- setup passive connection
	server, answer = %port(control)
	if not server then return answer end
	-- ask server to send file
	code, answer = %store(control, server, pfile.name, send_cb)
	if not code then return answer end
	-- disconnect
	%logout(control)
	-- no errors
	return nil
end

-----------------------------------------------------------------------------
-- Uploads a file to a FTP server
-- Input
--   url: file location
--   bytes: file contents
--   type: "binary" or "ascii"
-- Returns
--   err: error message if any
-----------------------------------------------------------------------------
function ftp_put(url, bytes, type)
	local send_cb = function()
		return %bytes, strlen(%bytes)
	end
	return ftp_putindirect(url, send_cb, type)
end

-----------------------------------------------------------------------------
-- We need fast concatenation routines for direct requests
-----------------------------------------------------------------------------
dofile("buffer.lua")

-----------------------------------------------------------------------------
-- Retrieve a file from a ftp server
-- Input
--   url: file location
--   type: "binary" or "ascii"
-- Returns
--   data: file contents as a string
--   err: error message in case of error, nil otherwise
-----------------------------------------------------------------------------
function ftp_get(url, type)
	local bytes = { buf = buf_create() }
	local receive_cb = function(chunk, err)
		if not chunk then %bytes.buf = nil end
		buf_addstring(%bytes.buf, chunk)
		return 1
	end
	err = ftp_getindirect(url, receive_cb, type)
	return buf_getresult(bytes.buf), err
end
