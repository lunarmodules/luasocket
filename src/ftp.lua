-----------------------------------------------------------------------------
-- FTP support for the Lua language
-- LuaSocket toolkit.
-- Author: Diego Nehab
-- Conforming to: RFC 959, LTN7
-- RCS ID: $Id$
-----------------------------------------------------------------------------

local Public, Private = {}, {}
local socket = _G[LUASOCKET_LIBNAME] -- get LuaSocket namespace
socket.ftp = Public  -- create ftp sub namespace

-----------------------------------------------------------------------------
-- Program constants
-----------------------------------------------------------------------------
-- timeout in seconds before the program gives up on a connection
Public.TIMEOUT = 60
-- default port for ftp service
Public.PORT = 21
-- this is the default anonymous password. used when no password is
-- provided in url. should be changed to your e-mail.
Public.EMAIL = "anonymous@anonymous.org"
-- block size used in transfers
Public.BLOCKSIZE = 8192

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
-- Tries to send DOS mode lines. Closes socket on error.
-- Input
--   sock: server socket
--   line: string to be sent
-- Returns
--   err: message in case of error, nil if successfull
-----------------------------------------------------------------------------
function Private.try_sendline(sock, line)
    return Private.try_send(sock, line .. "\r\n")
end

-----------------------------------------------------------------------------
-- Gets ip and port for data connection from PASV answer
-- Input
--   pasv: PASV command answer
-- Returns
--   ip: string containing ip for data connection
--   port: port for data connection
-----------------------------------------------------------------------------
function Private.get_pasv(pasv)
	local a, b, c, d, p1, p2, _
	local ip, port
	_,_, a, b, c, d, p1, p2 =
		string.find(pasv, "(%d*),(%d*),(%d*),(%d*),(%d*),(%d*)")
	if not (a and b and c and d and p1 and p2) then return nil, nil end
	ip = string.format("%d.%d.%d.%d", a, b, c, d)
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
function Private.send_command(control, cmd, arg)
	local line
	if arg then line = cmd .. " " .. arg
	else line = cmd end
	return Private.try_sendline(control, line)
end

-----------------------------------------------------------------------------
-- Gets FTP command answer, unfolding if neccessary
-- Input
--   control: control connection socket
-- Returns
--   answer: whole server reply, nil if error
--   code: answer status code or error message
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
-- Checks if a message return is correct. Closes control connection if not.
-- Input
--   control: control connection socket
--   success: table with successfull reply status code
-- Returns
--   code: reply code or nil in case of error
--   answer: server complete answer or system error message
-----------------------------------------------------------------------------
function Private.check_answer(control, success)
	local answer, code = Private.get_answer(control)
	if not answer then return nil, code end
	if type(success) ~= "table" then success = {success} end
	for _, s in ipairs(success) do
		if code == s then
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
function Private.command(control, cmd, arg, success)
	local err = Private.send_command(control, cmd, arg)
	if err then return nil, err end
	return Private.check_answer(control, success)
end

-----------------------------------------------------------------------------
-- Check server greeting
-- Input
--   control: control connection with server
-- Returns
--   code: nil if error
--   answer: server answer or error message
-----------------------------------------------------------------------------
function Private.greet(control)
	local code, answer = Private.check_answer(control, {120, 220})
	if code == 120 then -- please try again, somewhat busy now...
		return Private.check_answer(control, {220})
	end
	return code, answer
end

-----------------------------------------------------------------------------
-- Log in on server
-- Input
--   control: control connection with server
--   user: user name
--   password: user password if any
-- Returns
--   code: nil if error
--   answer: server answer or error message
-----------------------------------------------------------------------------
function Private.login(control, user, password)
	local code, answer = Private.command(control, "user", user, {230, 331})
	if code == 331 and password then -- need pass and we have pass
		return Private.command(control, "pass", password, {230, 202})
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
function Private.cwd(control, path)
	if path then return Private.command(control, "cwd", path, {250}) 
	else return 250, nil end
end

-----------------------------------------------------------------------------
-- Change to target directory
-- Input
--   control: socket for control connection with server
-- Returns
--   server: server socket bound to local address, nil if error
--   answer: error message if any
-----------------------------------------------------------------------------
function Private.port(control)
	local code, answer
	local server, ctl_ip
	ctl_ip, answer = control:getsockname()
	server, answer = socket.bind(ctl_ip, 0)
	server:settimeout(Public.TIMEOUT)
	local ip, p, ph, pl
	ip, p = server:getsockname()
	pl = math.mod(p, 256)
	ph = (p - pl)/256
    local arg = string.gsub(string.format("%s,%d,%d", ip, ph, pl), "%.", ",")
	code, answer = Private.command(control, "port", arg, {200})
	if not code then 
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
function Private.logout(control)
	local code, answer = Private.command(control, "quit", nil, {221})
	if code then control:close() end
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
function Private.receive_indirect(data, callback)
	local chunk, err, res
	while not err do
		chunk, err = Private.try_receive(data, Public.BLOCKSIZE)
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
--   name: file name 
--   is_directory: is file a directory name?
--   content_cb: callback to receive file contents
-- Returns
--   err: error message in case of error, nil otherwise
-----------------------------------------------------------------------------
function Private.retrieve(control, server, name, is_directory, content_cb)
	local code, answer
	local data
	-- ask server for file or directory listing accordingly
	if is_directory then 
		code, answer = Private.cwd(control, name) 
		if not code then return answer end
		code, answer = Private.command(control, "nlst", nil, {150, 125})
	else 
		code, answer = Private.command(control, "retr", name, {150, 125}) 
	end
	if not code then return nil, answer end
	data, answer = server:accept()
	server:close()
	if not data then 
		control:close()
		return answer 
	end
	answer = Private.receive_indirect(data, content_cb)
	if answer then 
		control:close()
		return answer
	end
	data:close()
	-- make sure file transfered ok
	return Private.check_answer(control, {226, 250})
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
    local total, sent, err
    total = 0
    while 1 do
        if type(chunk) ~= "string" or type(size) ~= "number" then
            data:close()
            if not chunk and type(size) == "string" then return size
            else return "invalid callback return" end
        end
        sent, err = data:send(chunk)
        if err then
            data:close()
            return err
        end
        total = total + sent
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
function Private.store(control, server, file, send_cb)
	local data, err
	local code, answer = Private.command(control, "stor", file, {150, 125})
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
	err = Private.send_indirect(data, send_cb, send_cb())
	if err then 
		control:close()
		return nil, err
	end
	-- close connection to inform that file transmission is complete
	data:close()
	-- check if file was received correctly
	return Private.check_answer(control, {226, 250})
end

-----------------------------------------------------------------------------
-- Change transfer type
-- Input
--   control: control connection with server
--   params: "type=i" for binary or "type=a" for ascii
-- Returns
--   err: error message if any
-----------------------------------------------------------------------------
function Private.change_type(control, params)
	local type, _
	_, _, type = string.find(params or "", "type=(.)")
	if type == "a" or type == "i" then 
		local code, err = Private.command(control, "type", type, {200})
		if not code then return err end
	end
end

-----------------------------------------------------------------------------
-- Starts a control connection, checks the greeting and log on
-- Input
--   parsed: parsed URL components
-- Returns
--   control: control connection with server, or nil if error
--   err: error message if any
-----------------------------------------------------------------------------
function Private.open(parsed)
	-- start control connection
	local control, err = socket.connect(parsed.host, parsed.port)
	if not control then return nil, err end
	-- make sure we don't block forever
	control:settimeout(Public.TIMEOUT)
	-- check greeting
	local code, answer = Private.greet(control)
	if not code then return nil, answer end
	-- try to log in
	code, err = Private.login(control, parsed.user, parsed.password)
	if not code then return nil, err
	else return control end
end

-----------------------------------------------------------------------------
-- Closes the connection with the server
-- Input
--   control: control connection with server
-----------------------------------------------------------------------------
function Private.close(control)
	-- disconnect
	Private.logout(control)
end

-----------------------------------------------------------------------------
-- Changes to the directory pointed to by URL
-- Input
--   control: control connection with server
--   segment: parsed URL path segments
-- Returns
--   err: error message if any
-----------------------------------------------------------------------------
function Private.change_dir(control, segment)
    local n = table.getn(segment)
	for i = 1, n-1 do
		local code, answer = Private.cwd(control, segment[i])
		if not code then return answer end
	end
end

-----------------------------------------------------------------------------
-- Stores a file in current directory
-- Input
--   control: control connection with server
--   request: a table with the fields:
--     content_cb: send callback to send file contents
--   segment: parsed URL path segments
-- Returns
--   err: error message if any
-----------------------------------------------------------------------------
function Private.upload(control, request, segment)
	local code, name, content_cb
	-- get remote file name
	name = segment[table.getn(segment)]
	if not name then 
		control:close()
		return "Invalid file path" 
	end
	content_cb = request.content_cb
	-- setup passive connection
	local server, answer = Private.port(control)
	if not server then return answer end
	-- ask server to receive file
	code, answer = Private.store(control, server, name, content_cb)
	if not code then return answer end
end

-----------------------------------------------------------------------------
-- Download a file from current directory
-- Input
--   control: control connection with server
--   request: a table with the fields:
--     content_cb: receive callback to receive file contents
--   segment: parsed URL path segments
-- Returns
--   err: error message if any
-----------------------------------------------------------------------------
function Private.download(control, request, segment)
	local code, name, is_directory, content_cb
	is_directory = segment.is_directory
	content_cb = request.content_cb
	-- get remote file name
	name = segment[table.getn(segment)]
	if not name and not is_directory then 
		control:close()
		return "Invalid file path" 
	end
	-- setup passive connection
	local server, answer = Private.port(control)
	if not server then return answer end
	-- ask server to send file or directory listing
	code, answer = Private.retrieve(control, server, name, 
		is_directory, content_cb)
	if not code then return answer end
end

-----------------------------------------------------------------------------
-- Parses the FTP URL setting default values
-- Input
--   request: a table with the fields:
--     url: the target URL
--     type: "i" for "image" mode, "a" for "ascii" mode or "d" for directory
--     user: account user name
--     password: account password
-- Returns
--   parsed: a table with parsed components
-----------------------------------------------------------------------------
function Private.parse_url(request)
	local parsed = socket.url.parse(request.url, {
		host = "",
		user = "anonymous", 
		port = 21, 
		path = "/",
		password = Public.EMAIL,
		scheme = "ftp"
	})
	-- explicit login information overrides that given by URL
	parsed.user = request.user or parsed.user
	parsed.password = request.password or parsed.password
	-- explicit representation type overrides that given by URL
	if request.type then parsed.params = "type=" .. request.type end
	return parsed
end

-----------------------------------------------------------------------------
-- Parses the FTP URL path setting default values
-- Input
--   parsed: a table with the parsed URL components
-- Returns
--   dirs: a table with parsed directory components
-----------------------------------------------------------------------------
function Private.parse_path(parsed_url)
	local segment = socket.url.parse_path(parsed_url.path)
	segment.is_directory = segment.is_directory or 
        (parsed_url.params == "type=d")
	return segment
end

-----------------------------------------------------------------------------
-- Builds a request table from a URL or request table
-- Input
--   url_or_request: target url or request table (a table with the fields:
--     url: the target URL
--     type: "i" for "image" mode, "a" for "ascii" mode or "d" for directory
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
-- Downloads a file from a FTP server
-- Input
--   request: a table with the fields:
--     url: the target URL
--     type: "i" for "image" mode, "a" for "ascii" mode or "d" for directory
--     user: account user name
--     password: account password
--     content_cb: receive callback to receive file contents
-- Returns
--   err: error message if any
-----------------------------------------------------------------------------
function Public.get_cb(request)
	local parsed = Private.parse_url(request)
	if parsed.scheme ~= "ftp" then 
		return string.format("unknown scheme '%s'", parsed.scheme)
	end
	local control, err = Private.open(parsed)
	if not control then return err end
	local segment = Private.parse_path(parsed)
	return Private.change_dir(control, segment) or
		Private.change_type(control, parsed.params) or
		Private.download(control, request, segment) or 
		Private.close(control)
end

-----------------------------------------------------------------------------
-- Uploads a file to a FTP server
-- Input
--   request: a table with the fields:
--     url: the target URL
--     type: "i" for "image" mode, "a" for "ascii" mode or "d" for directory
--     user: account user name
--     password: account password
--     content_cb: send callback to send file contents
-- Returns
--   err: error message if any
-----------------------------------------------------------------------------
function Public.put_cb(request)
	local parsed = Private.parse_url(request)
	if parsed.scheme ~= "ftp" then 
		return string.format("unknown scheme '%s'", parsed.scheme)
	end
	local control, err = Private.open(parsed)
	if not control then return err end
	local segment = Private.parse_path(parsed)
	err = Private.change_dir(control, segment) or
		Private.change_type(control, parsed.params) or
		Private.upload(control, request, segment) or 
		Private.close(control)
	if err then return nil, err
	else return 1 end
end

-----------------------------------------------------------------------------
-- Uploads a file to a FTP server
-- Input
--   url_or_request: target url or request table (a table with the fields:
--     url: the target URL
--     type: "i" for "image" mode, "a" for "ascii" mode or "d" for directory
--     user: account user name
--     password: account password)
--     content: file contents
--   content: file contents
-- Returns
--   err: error message if any
-----------------------------------------------------------------------------
function Public.put(url_or_request, content)
	local request = Private.build_request(url_or_request)
	request.content = request.content or content
	request.content_cb = socket.callback.send_string(request.content)
	return Public.put_cb(request)
end

-----------------------------------------------------------------------------
-- Retrieve a file from a ftp server
-- Input
--   url_or_request: target url or request table (a table with the fields:
--     url: the target URL
--     type: "i" for "image" mode, "a" for "ascii" mode or "d" for directory
--     user: account user name
--     password: account password)
-- Returns
--   data: file contents as a string
--   err: error message in case of error, nil otherwise
-----------------------------------------------------------------------------
function Public.get(url_or_request)
	local concat = socket.concat.create()
	local request = Private.build_request(url_or_request)
	request.content_cb = socket.callback.receive_concat(concat)
	local err = Public.get_cb(request)
	return concat:getresult(), err
end
