-----------------------------------------------------------------------------
-- Simple FTP support for the Lua language using the LuaSocket toolkit.
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
	if not a or not b or not c or not d or not p1 or not p2 then
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
--   file: filename
--   path: table with directories to reach filename
--   isdir: is it a directory or a file
-----------------------------------------------------------------------------
local split_path  = function(file)
	local path = {}
	local isdir
	file = file or "/"
	-- directory ends with a '/'
	_,_, isdir = strfind(file, "([/])$")
	gsub(file, "([^/]+)", function (dir) tinsert(%path, dir) end)
	if not isdir then file = tremove(path)
	else file = nil end
	return file, path, isdir
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
--   path: array with directories in order
-- Returns
--   code: nil if error
--   answer: server answer or error message
-----------------------------------------------------------------------------
local cwd = function(control, path)
	local code, answer = 250, "Home directory used"
	for i = 1, getn(path) do
		code, answer = %try_command(control, "cwd", path[i], {250})
		if not code then return nil, answer end
	end
	return code, answer
end

-----------------------------------------------------------------------------
-- Start data connection with server
-- Input
--   control: control connection with server
-- Returns
--   data: socket for data connection with server, nil if error
--   answer: server answer or error message
-----------------------------------------------------------------------------
local start_dataconnection = function(control)
	-- ask for passive data connection
	local code, answer = %try_command(control, "pasv", nil, {227})
	if not code then return nil, answer end
	-- get data connection parameters from server reply
	local host, port = %get_pasv(answer)
	if not host or not port then return nil, answer end
	-- start data connection with given parameters
	local data, err = connect(host, port)
	if not data then return nil, err end
	data:timeout(%TIMEOUT)
	return data
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
-- Retrieves file or directory listing
-- Input
--   control: control connection with server
--   data: data connection with server
--   file: file name under current directory
--   isdir: is file a directory name?
-- Returns
--   file: string with file contents, nil if error
--   answer: server answer or error message
-----------------------------------------------------------------------------
local retrieve_file = function(control, data, file, isdir)
	-- ask server for file or directory listing accordingly
	if isdir then code, answer = %try_command(control, "nlst", file, {150, 125})
	else code, answer = %try_command(control, "retr", file, {150, 125}) end
	if not code then 
		control:close()
		data:close()
		return nil, answer 
	end
	-- download whole file
	file, err = data:receive("*a")
	data:close()
	if err then 
		control:close()
		return nil, err
	end
	-- make sure file transfered ok
	code, answer = %check_answer(control, {226, 250})
	if not code then return nil, answer 
	else return file, answer end
end

-----------------------------------------------------------------------------
-- Stores a file
-- Input
--   control: control connection with server
--   data: data connection with server
--   file: file name under current directory
--   bytes: file contents in string 
-- Returns
--   file: string with file contents, nil if error
--   answer: server answer or error message
-----------------------------------------------------------------------------
local store_file = function (control, data, file, bytes)
	local code, answer = %try_command(control, "stor", file, {150, 125})
	if not code then 
		data:close()
		return nil, answer 
	end
	-- send whole file and close connection to mark file end
	answer = data:send(bytes)
	data:close()
	if answer then 
		control:close()
		return nil, answer
	end
	-- check if file was received right
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
--   type: "binary" or "ascii"
-- Returns
--   file: downloaded file or nil in case of error
--   err: error message if any
-----------------------------------------------------------------------------
function ftp_get(url, type)
	local control, data, err
	local answer, code, server, file, path
	parsed = %split_url(url, {user = "anonymous", port = 21, pass = %EMAIL})
	-- start control connection
	control, err = connect(parsed.host, parsed.port)
	if not control then return nil, err end
	control:timeout(%TIMEOUT)
	-- get and check greeting
	code, answer = %check_greeting(control)
	if not code then return nil, answer end
	-- try to log in
	code, answer = %login(control, parsed.user, parsed.pass)
	if not code then return nil, answer end
	-- go to directory
	file, path, isdir = %split_path(parsed.path)
	code, answer = %cwd(control, path)
	if not code then return nil, answer end
	-- change to binary type?
	code, answer = %change_type(control, type)
	if not code then return nil, answer end
	-- start data connection
	data, answer = %start_dataconnection(control)
	if not data then return nil, answer end
	-- ask server to send file or directory listing
	file, answer = %retrieve_file(control, data, file, isdir)
	if not file then return nil, answer end
	-- disconnect
	%logout(control)
	-- return whatever file we received plus a possible error
	return file, answer
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
	local control, data
	local answer, code, server, file, path
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
	file, path, isdir = %split_path(parsed.path)
	code, answer = %cwd(control, path)
	if not code then return answer end
	-- change to binary type?
	code, answer = %change_type(control, type)
	if not code then return answer end
	-- start data connection
	data, answer = %start_dataconnection(control)
	if not data then return answer end
	-- ask server to send file or directory listing
	code, answer = %store_file(control, data, file, bytes)
	if not code then return answer end
	-- disconnect
	%logout(control)
	-- return whatever file we received plus a possible error
	return nil
end
