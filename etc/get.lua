assert(dofile("../lua/buffer.lua"))
assert(dofile("../lua/ftp.lua"))
assert(dofile("../lua/base64.lua"))
assert(dofile("../lua/http.lua"))

-- format a number of bytes per second into a human readable form
function strbps(b)
	local l = "B/s"
	if b > 1024 then
		b = b / 1024
		l = "KB/s"
		if b > 1024 then
			b = b / 1024
			l = "MB/s"
			if b > 1024 then
				b = b / 1024
				l = "GB/s" -- hmmm
			end
		end
	end
	return format("%.2f%s     ", b, l)
end

-- creates a new instance of a receive_cb that saves to disk
-- kind of copied from luasocket's manual callback examples
function receive2disk(file)
	local aux = {
        start = _time(),
        got = 0,
        file = openfile(file, "wb")
    }
    local receive_cb = function(chunk, err)
        local dt = _time() - %aux.start          -- elapsed time since start
        if not chunk or chunk == "" then
			write("\n")
            closefile(%aux.file)
            return
        end
        write(%aux.file, chunk)
        %aux.got = %aux.got + strlen(chunk)      -- total bytes received
        if dt < 0.1 then return 1 end            -- not enough time for estimate
        local rate = %aux.got / dt               -- get download rate
        write("\r" .. strbps(rate))      -- print estimate
        return 1
    end
	return receive_cb
end

-- stolen from http implementation
function split_url(url, default)
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

-- stolen from http implementation
function get_statuscode(line)
    local _,_, code = strfind(line, " (%d%d%d) ")
    return tonumber(code)
end

function getbyftp(url, file)
    local err = ftp_getindirect(url, receive2disk(file), "b")
	if err then print(err) else print("done.") end
end

function getbyhttp(url, file)
    local hdrs, line, err = http_getindirect(url, receive2disk(file))
	if line and get_statuscode(line) == 200 then print("done.")
	elseif line then print(line) else print(err) end
end

function get(url, file)
	local parsed = split_url(url)
	if parsed.scheme == "ftp" then getbyftp(url, file)
	else getbyhttp(url, file) end
end

arg = arg or {}
if getn(arg) < 2 then 
	write("Usage:\n  luasocket -f get.lua <remote-url> <local-file>\n")
	exit(1)
else get(arg[1], arg[2]) end
