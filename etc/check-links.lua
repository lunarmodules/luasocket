-----------------------------------------------------------------------------
-- Little program that checks links in HTML files
-- LuaSocket sample files
-- Author: Diego Nehab
-- RCS ID: $Id$
-----------------------------------------------------------------------------

require"luasocket"
require"http"

socket.http.TIMEOUT = 10

cache = {}

function readfile(path)
	path = socket.url.unescape(path)
	local file, error = io.open(path, "r")
	if file then 
        local body = file:read("*a")
		file:close()
        return body
    else return nil, error end
end

function getstatus(url)
	local parsed = socket.url.parse(url, { scheme = "file" })
	if cache[url] then return cache[url] end
	local res
    if parsed.scheme == "http" then
        local request = { url = url, method = "HEAD" }
        local response = socket.http.request(request)
        if response.code == 200 then res = nil
        else res = response.status or response.error end
    elseif parsed.scheme == "file" then
        local file, error = io.open(socket.url.unescape(parsed.path), "r")
        if file then
             file:close()
             res = nil
        else res = error end
    else res = string.format("unhandled scheme '%s'", parsed.scheme) end
    cache[url] = res
	return res
end

function retrieve(url)
	local parsed = socket.url.parse(url, { scheme = "file" })
    local body, headers, code, error
    local base = url
	if parsed.scheme == "http" then 
        body, headers, code, error = socket.http.get(url)
        if code == 200 then 
            base = base or headers.location
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
	body = string.gsub(body, '[Hh][Rr][Ee][Ff]%s*=%s*"([^"]*)"', function(href)
        table.insert(links, socket.url.absolute(base, href))
    end)
	body = string.gsub(body, "[Hh][Rr][Ee][Ff]%s*=%s*'([^']*)'", function(href)
        table.insert(links, socket.url.absolute(base, href))
    end)
	string.gsub(body, "[Hh][Rr][Ee][Ff]%s*=%s*(.-)>", function(href)
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
