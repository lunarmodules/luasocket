-----------------------------------------------------------------------------
-- Little program that checks links in HTML files
-- LuaSocket sample files
-- Author: Diego Nehab
-- RCS ID: $Id$
-----------------------------------------------------------------------------
local http = require("http")
local url = require("url")
http.TIMEOUT = 10

cache = {}

function readfile(path)
	path = url.unescape(path)
	local file, error = io.open(path, "r")
	if file then 
        local body = file:read("*a")
		file:close()
        return body
    else return nil, error end
end

function getstatus(u)
	local parsed = url.parse(u, {scheme = "file"})
	if cache[u] then return cache[u] end
	local res
    if parsed.scheme == "http" then
        local request = {url = u, method = "HEAD"}
        local response = http.request(request)
        if response.code == 200 then res = nil
        else res = response.status or response.error end
    elseif parsed.scheme == "file" then
        local file, error = io.open(url.unescape(parsed.path), "r")
        if file then
             file:close()
             res = nil
        else res = error end
    else res = string.format("unhandled scheme '%s'", parsed.scheme) end
    cache[u] = res
	return res
end

function retrieve(u)
	local parsed = url.parse(u, { scheme = "file" })
    local body, headers, code, error
    local base = u
	if parsed.scheme == "http" then 
        body, headers, code, error = http.get(u)
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
        table.insert(links, url.absolute(base, href))
    end)
	body = string.gsub(body, "[Hh][Rr][Ee][Ff]%s*=%s*'([^']*)'", function(href)
        table.insert(links, url.absolute(base, href))
    end)
	string.gsub(body, "[Hh][Rr][Ee][Ff]%s*=%s*(.-)>", function(href)
        table.insert(links, url.absolute(base, href))
    end)
    return links
end

function checklinks(u)
	local base, body, error = retrieve(u)
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
	checklinks(url.absolute("file:", a))
end
