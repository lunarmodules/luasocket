dofile("../lua/http.lua")
HTTP.TIMEOUT = 10
dofile("../lua/code.lua")
dofile("../lua/url.lua")
dofile("../lua/concat.lua")

cache = {}

function readfile(path)
	path = Code.unescape(path)
	local file, error = openfile(path, "r")
	if file then 
        local body = read(file, "*a")
		closefile(file)
        return body
    else return nil, error end
end

function getstatus(url)
	local parsed = URL.parse_url(url, { scheme = "file" })
	if cache[url] then return cache[url].res end
	local res
    if parsed.scheme == "http" then
        local request = { url = url }
        local response = { body_cb = function(chunk, err) 
            return nil
        end }
		local blocksize = HTTP.BLOCKSIZE
		HTTP.BLOCKSIZE = 1
        response = HTTP.request_cb(request, response)
        HTTP.BLOCKSIZE = blocksize
        if response.code == 200 then res = nil
        else res = response.status or response.error end
    elseif parsed.scheme == "file" then
        local file, error = openfile(Code.unescape(parsed.path), "r")
        if file then
             closefile(file)
             res = nil
        else res = error end
    else res = format("unhandled scheme '%s'", parsed.scheme) end
    cache[url] = { res = res }
	return res
end

function retrieve(url)
	local parsed = URL.parse_url(url, { scheme = "file" })
    local base, body, error
    base = url
	if parsed.scheme == "http" then 
        local response = HTTP.request{url = url}
        if response.code ~= 200 then 
            error = response.status or response.error
        else
            base = response.headers.location or url
            body = response.body
        end
    elseif parsed.scheme == "file" then 
        body, error = readfile(parsed.path) 
    else error = format("unhandled scheme '%s'", parsed.scheme) end
    return base, body, error
end

function getlinks(body, base)
    -- get rid of comments
    body = gsub(body, "%<%!%-%-.-%-%-%>", "")
    local links = {}
    -- extract links
	gsub(body, '[Hh][Rr][Ee][Ff]%s*=%s*"([^"]*)"', function(href)
        tinsert(%links, URL.absolute_url(%base, href))
    end)
	gsub(body, "[Hh][Rr][Ee][Ff]%s*=%s*'([^']*)'", function(href)
        tinsert(%links, URL.absolute_url(%base, href))
    end)
	gsub(body, "[Hh][Rr][Ee][Ff]%s*=%s*(%a+)", function(href)
        tinsert(%links, URL.absolute_url(%base, href))
    end)
    return links
end

function checklinks(url)
	local base, body, error = retrieve(url)
    if not body then print(error) return end
    local links = getlinks(body, base)
    for i = 1, getn(links) do
		write(_STDERR, "\t", links[i], "\n")
		local err = getstatus(links[i])
		if err then write('\t', links[i], ": ", err, "\n") end
    end
end

arg = arg or {}
if getn(arg) < 1 then
	write("Usage:\n  luasocket -f check-links.lua {<url>}\n")
	exit()
end
for i = 1, getn(arg) do
	write("Checking ", arg[i], "\n")
	checklinks(URL.absolute_url("file:", arg[i]))
end
