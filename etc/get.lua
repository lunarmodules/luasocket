-----------------------------------------------------------------------------
-- Little program to download files from URLs
-- LuaSocket sample files
-- Author: Diego Nehab
-- RCS ID: $Id$
-----------------------------------------------------------------------------
-- formats a number of seconds into human readable form
function nicetime(s)
	local l = "s"
	if s > 60 then
		s = s / 60
		l = "m"
		if s > 60 then
			s = s / 60
			l = "h"
			if s > 24 then
				s = s / 24
				l = "d" -- hmmm
			end
		end
	end
	if l == "s" then return string.format("%2.0f%s", s, l)
	else return string.format("%5.2f%s", s, l) end
end

-- formats a number of bytes into human readable form
function nicesize(b)
	local l = "B"
	if b > 1024 then
		b = b / 1024
		l = "KB"
		if b > 1024 then
			b = b / 1024
			l = "MB"
			if b > 1024 then
				b = b / 1024
				l = "GB" -- hmmm
			end
		end
	end
	return string.format("%7.2f%2s", b, l)
end

-- returns a string with the current state of the download
function gauge(got, dt, size)
	local rate = got / dt
	if size and size >= 1 then
		return string.format("%s received, %s/s throughput, " ..
			"%.0f%% done, %s remaining", 
            nicesize(got),  
			nicesize(rate), 
			100*got/size, 
			nicetime((size-got)/rate))
	else 
		return string.format("%s received, %s/s throughput, %s elapsed", 
			nicesize(got), 
			nicesize(rate),
			nicetime(dt))
	end
end

-- creates a new instance of a receive_cb that saves to disk
-- kind of copied from luasocket's manual callback examples
function receive2disk(file, size)
	local aux = {
        start = socket.time(),
        got = 0,
        file = io.open(file, "wb"),
		size = size
    }
    local receive_cb = function(chunk, err)
        local dt = socket.time() - aux.start  -- elapsed time since start
        if not chunk or chunk == "" then
			io.write("\n")
            aux.file:close()
            return
        end
        aux.file:write(chunk)
        aux.got = aux.got + string.len(chunk)  -- total bytes received
        if dt < 0.1 then return 1 end          -- not enough time for estimate
		io.write("\r", gauge(aux.got, dt, aux.size))
        return 1
    end
	return receive_cb
end

-- downloads a file using the ftp protocol
function getbyftp(url, file)
    local err = socket.ftp.get_cb {
        url = url,
        content_cb = receive2disk(file),
        type = "i"
    }
	print()
	if err then print(err) end
end

-- downloads a file using the http protocol
function getbyhttp(url, file, size)
    local response = socket.http.request_cb(
        {url = url},
		{body_cb = receive2disk(file, size)} 
    )
	print()
	if response.code ~= 200 then print(response.status or response.error) end
end

-- determines the size of a http file
function gethttpsize(url)
	local response = socket.http.request {
		method = "HEAD",
 		url = url
	}
	if response.code == 200 then
		return tonumber(response.headers["content-length"])
	end
end

-- determines the scheme and the file name of a given url
function getschemeandname(url, name)
	-- this is an heuristic to solve a common invalid url poblem
	if not string.find(url, "//") then url = "//" .. url end
	local parsed = socket.url.parse(url, {scheme = "http"})
	if name then return parsed.scheme, name end
	local segment = socket.url.parse_path(parsed.path)
	name = segment[table.getn(segment)]
	if segment.is_directory then name = nil end
	return parsed.scheme, name
end

-- gets a file either by http or ftp, saving as <name>
function get(url, name)
	local scheme
    scheme, name = getschemeandname(url, name)
	if not name then print("unknown file name")
	elseif scheme == "ftp" then getbyftp(url, name)
	elseif scheme == "http" then getbyhttp(url, name, gethttpsize(url)) 
	else print("unknown scheme" .. scheme) end
end

-- main program
arg = arg or {}
if table.getn(arg) < 1 then 
	io.write("Usage:\n  luasocket get.lua <remote-url> [<local-file>]\n")
	os.exit(1)
else get(arg[1], arg[2]) end
