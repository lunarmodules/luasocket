-----------------------------------------------------------------------------
-- FTP support for the Lua language
-- LuaSocket toolkit.
-- Author: Diego Nehab
-- Conforming to: RFC 959, LTN7
-- RCS ID: $Id$
-----------------------------------------------------------------------------
-- make sure LuaSocket is loaded
if not LUASOCKET_LIBNAME then error('module requires LuaSocket') end
-- get LuaSocket namespace
local socket = _G[LUASOCKET_LIBNAME] 
if not socket then error('module requires LuaSocket') end
-- create namespace inside LuaSocket namespace
socket.ftp  = socket.ftp or {}
-- make all module globals fall into namespace
setmetatable(socket.ftp, { __index = _G })
setfenv(1, socket.ftp)

-----------------------------------------------------------------------------
-- Program constants
-----------------------------------------------------------------------------
-- timeout in seconds before the program gives up on a connection
TIMEOUT = 60
-- default port for ftp service
PORT = 21
-- this is the default anonymous password. used when no password is
-- provided in url. should be changed to your e-mail.
EMAIL = "anonymous@anonymous.org"
-- block size used in transfers
BLOCKSIZE = 2048

-----------------------------------------------------------------------------
-- Gets ip and port for data connection from PASV answer
-- Input
--   pasv: PASV command answer
-- Returns
--   ip: string containing ip for data connection
--   port: port for data connection
-----------------------------------------------------------------------------
local function get_pasv(pasv)
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
-- Check server greeting
-- Input
--   control: control connection with server
-- Returns
--   code: nil if error
--   answer: server answer or error message
-----------------------------------------------------------------------------
local function greet(control)
	local code, answer = check_answer(control, {120, 220})
	if code == 120 then -- please try again, somewhat busy now...
		return check_answer(control, {220})
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
local function login(control, user, password)
	local code, answer = command(control, "user", user, {230, 331})
	if code == 331 and password then -- need pass and we have pass
		return command(control, "pass", password, {230, 202})
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
local function cwd(control, path)
end

-----------------------------------------------------------------------------
-- Change to target directory
-- Input
--   control: socket for control connection with server
-- Returns
--   server: server socket bound to local address, nil if error
--   answer: error message if any
-----------------------------------------------------------------------------
local function port(control)
	local code, answer
	local server, ctl_ip
	ctl_ip, answer = control:getsockname()
	server, answer = socket.bind(ctl_ip, 0)
	server:settimeout(TIMEOUT)
	local ip, p, ph, pl
	ip, p = server:getsockname()
	pl = math.mod(p, 256)
	ph = (p - pl)/256
    local arg = string.gsub(string.format("%s,%d,%d", ip, ph, pl), "%.", ",")
	code, answer = command(control, "port", arg, {200})
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
local function logout(control)
	local code, answer = command(control, "quit", nil, {221})
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
local function receive_indirect(data, callback)
	local chunk, err, res
	while not err do
		chunk, err = try_receive(data, BLOCKSIZE)
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
local function retrieve(control, server, name, is_directory, content_cb)
	local code, answer
	local data
	-- ask server for file or directory listing accordingly
	if is_directory then 
		code, answer = cwd(control, name) 
		if not code then return answer end
		code, answer = command(control, "nlst", nil, {150, 125})
	else 
		code, answer = command(control, "retr", name, {150, 125}) 
	end
	if not code then return nil, answer end
	data, answer = server:accept()
	server:close()
	if not data then 
		control:close()
		return answer 
	end
	answer = receive_indirect(data, content_cb)
	if answer then 
		control:close()
		return answer
	end
	data:close()
	-- make sure file transfered ok
	return check_answer(control, {226, 250})
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
local function store(control, server, file, send_cb)
	local data, err
	local code, answer = command(control, "stor", file, {150, 125})
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
	err = send_indirect(data, send_cb, send_cb())
	if err then 
		control:close()
		return nil, err
	end
	-- close connection to inform that file transmission is complete
	data:close()
	-- check if file was received correctly
	return check_answer(control, {226, 250})
end

-----------------------------------------------------------------------------
-- Change transfer type
-- Input
--   control: control connection with server
--   params: "type=i" for binary or "type=a" for ascii
-- Returns
--   err: error message if any
-----------------------------------------------------------------------------
local function change_type(control, params)
	local type, _
	_, _, type = string.find(params or "", "type=(.)")
	if type == "a" or type == "i" then 
		local code, err = command(control, "type", type, {200})
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
local function open(parsed)
	local control, err = socket.tp.connect(parsed.host, parsed.port)
	if not control then return nil, err end
    local code, reply
    -- greet
    code, reply = control:check({120, 220})
    if code == 120 then -- busy, try again
        code, reply = control:check(220) 
    end
    -- authenticate
	code, reply = control:command("user", user)
	code, reply = control:check({230, 331})
	if code == 331 and password then -- need pass and we have pass
		control:command("pass", password)
        code, reply = control:check({230, 202})
    end
    -- change directory
	local segment = parse_path(parsed)
	for i, v in ipairs(segment) do
	    code, reply = control:command("cwd")
        code, reply = control:check(250) 
	end
    -- change type
	local type = string.sub(params or "", 7, 7) 
	if type == "a" or type == "i" then 
		code, reply = control:command("type", type)
        code, reply = control:check(200)
	end
end

	return change_dir(control, segment) or
		change_type(control, parsed.params) or
		download(control, request, segment) or 
		close(control)
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
local function upload(control, request, segment)
	local code, name, content_cb
	-- get remote file name
	name = segment[table.getn(segment)]
	if not name then 
		control:close()
		return "Invalid file path" 
	end
	content_cb = request.content_cb
	-- setup passive connection
	local server, answer = port(control)
	if not server then return answer end
	-- ask server to receive file
	code, answer = store(control, server, name, content_cb)
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
local function download(control, request, segment)
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
	local server, answer = port(control)
	if not server then return answer end
	-- ask server to send file or directory listing
	code, answer = retrieve(control, server, name, 
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
local function parse_url(request)
	local parsed = socket.url.parse(request.url, {
		user = "anonymous", 
		port = 21, 
		path = "/",
		password = EMAIL,
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
local function parse_path(parsed_url)
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
local function build_request(data)
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
function get_cb(request)
	local parsed = parse_url(request)
	if parsed.scheme ~= "ftp" then 
		return string.format("unknown scheme '%s'", parsed.scheme)
	end
	local control, err = open(parsed)
	if not control then return err end
	local segment = parse_path(parsed)
	return change_dir(control, segment) or
		change_type(control, parsed.params) or
		download(control, request, segment) or 
		close(control)
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
function put_cb(request)
	local parsed = parse_url(request)
	if parsed.scheme ~= "ftp" then 
		return string.format("unknown scheme '%s'", parsed.scheme)
	end
	local control, err = open(parsed)
	if not control then return err end
	local segment = parse_path(parsed)
	err = change_dir(control, segment) or
		change_type(control, parsed.params) or
		upload(control, request, segment) or 
		close(control)
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
function put(url_or_request, content)
	local request = build_request(url_or_request)
	request.content = request.content or content
	request.content_cb = socket.callback.send_string(request.content)
	return put_cb(request)
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
function get(url_or_request)
	local concat = socket.concat.create()
	local request = build_request(url_or_request)
	request.content_cb = socket.callback.receive_concat(concat)
	local err = get_cb(request)
	return concat:getresult(), err
end

return socket.ftp
