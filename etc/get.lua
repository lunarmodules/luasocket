-----------------------------------------------------------------------------
-- Little program to download files from URLs
-- LuaSocket sample files
-- Author: Diego Nehab
-- RCS ID: $Id$
-----------------------------------------------------------------------------
socket = require("socket")
http = require("http")
ftp = require("ftp")
url = require("url")

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
	if l == "s" then return string.format("%5.0f%s", s, l)
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
local remaining_s = "%s received, %s/s throughput, %2.0f%% done, %s remaining"
local elapsed_s =   "%s received, %s/s throughput, %s elapsed                "
function gauge(got, delta, size)
	local rate = got / delta
	if size and size >= 1 then
		return string.format(remaining_s, nicesize(got),  nicesize(rate), 
			100*got/size, nicetime((size-got)/rate))
	else 
		return string.format(elapsed_s, nicesize(got), 
			nicesize(rate), nicetime(delta))
	end
end

-- creates a new instance of a receive_cb that saves to disk
-- kind of copied from luasocket's manual callback examples
function stats(size)
    local start = socket.time()
    local got = 0
    return function(chunk)
        -- elapsed time since start
        local delta = socket.time() - start 
        if chunk then 
            -- total bytes received
            got = got + string.len(chunk)    
            -- not enough time for estimate
            if delta > 0.1 then 
                io.stderr:write("\r", gauge(got, delta, size)) 
                io.stderr:flush()
            end
        else 
            -- close up
            io.stderr:write("\r", gauge(got, delta), "\n") 
        end
        return chunk
    end
end

-- determines the size of a http file
function gethttpsize(u)
	local respt = http.request {method = "HEAD", url = u}
	if respt.code == 200 then
		return tonumber(respt.headers["content-length"])
	end
end

-- downloads a file using the http protocol
function getbyhttp(u, file)
    local save = ltn12.sink.file(file or io.stdout)
    -- only print feedback if output is not stdout
    if file then save = ltn12.sink.chain(stats(gethttpsize(u)), save) end
    local respt = http.request {url = u, sink = save }
	if respt.code ~= 200 then print(respt.status or respt.error) end
end

-- downloads a file using the ftp protocol
function getbyftp(u, file)
    local save = ltn12.sink.file(file or io.stdout)
    -- only print feedback if output is not stdout
    -- and we don't know how big the file is
    if file then save = ltn12.sink.chain(stats(), save) end
    local gett = url.parse(u)
    gett.sink = save
    gett.type = "i"
    local ret, err = ftp.get(gett) 
	if err then print(err) end
end

-- determines the scheme 
function getscheme(u)
	-- this is an heuristic to solve a common invalid url poblem
	if not string.find(u, "//") then u = "//" .. u end
	local parsed = url.parse(u, {scheme = "http"})
	return parsed.scheme
end

-- gets a file either by http or ftp, saving as <name>
function get(u, name)
    local fout = name and io.open(name, "wb")
	local scheme = getscheme(u)
	if scheme == "ftp" then getbyftp(u, fout)
	elseif scheme == "http" then getbyhttp(u, fout)
	else print("unknown scheme" .. scheme) end
end

-- main program
arg = arg or {}
if table.getn(arg) < 1 then 
	io.write("Usage:\n  lua get.lua <remote-url> [<local-file>]\n")
	os.exit(1)
else get(arg[1], arg[2]) end
