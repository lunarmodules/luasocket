-----------------------------------------------------------------------------
-- Little program that checks links in HTML files
-- LuaSocket sample files
-- Author: Diego Nehab
-- RCS ID: $Id$
-----------------------------------------------------------------------------
socket.http.TIMEOUT = 10

cache = {}

function readfile(path)
	path = socket.code.unescape(path)
	local file, error = openfile(path, "r")
	if file then 
        local body = read(file, "*a")
		closefile(file)
        return body
    else return nil, error end
end

function getstatus(url)
	local parsed = socket.url.parse(url, { scheme = "file" })
	if cache[url] then return cache[url] end
	local res
    if parsed.scheme == "http" then
        local request = { url = url }
        local response = { body_cb = function(chunk, err) 
            return nil
        end }
		local blocksize = socket.http.BLOCKSIZE
		socket.http.BLOCKSIZE = 1
        response = socket.http.request_cb(request, response)
        socket.http.BLOCKSIZE = blocksize
        if response.code == 200 then res = nil
        else res = response.status or response.error end
    elseif parsed.scheme == "file" then
        local file, error = openfile(Code.unescape(parsed.path), "r")
        if file then
             closefile(file)
             res = nil
        else res = error end
    else res = string.format("unhandled scheme '%s'", parsed.scheme) end
    cache[url] = res
	return res
end

function retrieve(url)
	local parsed = socket.url.parse(url, { scheme = "file" })
    local base, body, error
    base = url
	if parsed.scheme == "http" then 
        local response = socket.http.request{url = url}
        if response.code ~= 200 then 
            error = response.status or response.error
        else
            base = response.headers.location or url
            body = response.body
        end
    elseif parsed.scheme == "file" then 
        body, error = readfile(parsed.path) 
    else error = string.format("unhandled scheme '%s'", parsed.scheme) end
    return base, body, error
end

function getlinks(body, base)
    -- get rid of comments
    body = string.gsub(body, "%<%!%-%-.-%-%-%>", "")
    local links = {}
    -- extract links
	string.gsub(body, '[Hh][Rr][Ee][Ff]%s*=%s*"([^"]*)"', function(href)
        table.insert(links, socket.url.absolute(base, href))
    end)
	string.gsub(body, "[Hh][Rr][Ee][Ff]%s*=%s*'([^']*)'", function(href)
        table.insert(links, socket.url.absolute(base, href))
    end)
	string.gsub(body, "[Hh][Rr][Ee][Ff]%s*=%s*(%a+)", function(href)
        table.insert(links, socket.url.absolute(base, href))
    end)
    return links
end

function checklinks(url)
	local base, body, error = retrieve(url)
    if not body then print(error) return end
    local links = getlinks(body, base)
    for _, l in ipairs(links) do
		io.stderr:write("\t", l, "\n")
		local err = getstatus(l)
		if err then io.stderr:write('\t', l, ": ", err, "\n") end
    end
end

arg = arg or {}
if table.getn(arg) < 1 then
	print("Usage:\n  luasocket check-links.lua {<url>}")
	exit()
end
for _, a in ipairs(arg) do
	print("Checking ", a)
	checklinks(socket.url.absolute("file:", a))
end
