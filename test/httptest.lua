-- needs Alias from /home/c/diego/tec/luasocket/test to 
-- "/luasocket-test" and "/luasocket-test/"
-- needs ScriptAlias from /home/c/diego/tec/luasocket/test/cgi
-- to "/luasocket-test-cgi" and "/luasocket-test-cgi/"
-- needs "AllowOverride AuthConfig" on /home/c/diego/tec/luasocket/test/auth
dofile("noglobals.lua")

local host, proxyh, proxyp, request, response
local ignore, expect, index, prefix, cgiprefix

local t = socket.time()

host = host or "diego.princeton.edu"
proxyh = proxyh or "localhost"
proxyp = proxyp or 3128
prefix = prefix or "/luasocket-test"
cgiprefix = cgiprefix or "/luasocket-test-cgi"

local readfile = function(name)
	local f = io.open(name, "r")
	if not f then return nil end
	local s = f:read("*a")
	f:close()
	return s
end

index = readfile("test/index.html")

local similar = function(s1, s2)
	return string.lower(string.gsub(s1 or "", "%s", "")) == 
        string.lower(string.gsub(s2 or "", "%s", ""))
end

local fail = function(s)
	s = s or "failed!"
	print(s)
	os.exit()
end

local check = function (v, e)
	if v then print("ok")
	else fail(e) end
end
	
local check_request = function(request, expect, ignore)
	local response = socket.http.request(request)
	for i,v in response do
		if not ignore[i] then
			if v ~= expect[i] then 
                if string.len(v) < 80 then print(v) end
                fail(i .. " differs!") 
            end
		end
	end
	for i,v in expect do
		if not ignore[i] then
			if v ~= response[i] then 
                if string.len(v) < 80 then print(v) end
                fail(i .. " differs!") 
            end
		end
	end
	print("ok")
end

io.write("testing request uri correctness: ")
local forth = cgiprefix .. "/request-uri?" .. "this+is+the+query+string"
local back, h, c, e = socket.http.get("http://" .. host .. forth)
back = socket.url.parse(back)
if similar(back.query, "this+is+the+query+string") then print("ok")
else fail() end

io.write("testing query string correctness: ")
forth = "this+is+the+query+string"
back = socket.http.get("http://" .. host .. cgiprefix .. "/query-string?" .. forth)
if similar(back, forth) then print("ok")
else fail("failed!") end

io.write("testing document retrieval: ")
request = {
	url = "http://" .. host .. prefix .. "/index.html"
}
expect = {
	body = index,
	code = 200
}
ignore = {
	status = 1,
	headers = 1
}
check_request(request, expect, ignore)

io.write("testing redirect loop: ")
request = {
    url = "http://" .. host .. cgiprefix .. "/redirect-loop"
}
expect = {
    code = 302
}
ignore = {
	status = 1,
	headers = 1,
	body = 1
}
check_request(request, expect, ignore)

io.write("testing post method: ")
-- wanted to test chunked post, but apache doesn't support it...
request = {
	url = "http://" .. host .. cgiprefix .. "/cat",
	method = "POST",
	body = index,
    -- remove content-length header to send chunked body
    headers = { ["content-length"] = string.len(index) }
}
expect = {
	body = index,
	code = 200
}
ignore = {
	status = 1,
	headers = 1
}
check_request(request, expect, ignore)

io.write("testing proxy with post method: ")
request = {
	url = "http://" .. host .. cgiprefix .. "/cat",
	method = "POST",
	body = index,
    headers = { ["content-length"] = string.len(index) },
    port = proxyp,
    host = proxyh
}
expect = {
	body = index,
	code = 200
}
ignore = {
	status = 1,
	headers = 1
}
check_request(request, expect, ignore)

io.write("testing simple post function: ")
back = socket.http.post("http://" .. host .. cgiprefix .. "/cat", index)
check(back == index)

io.write("testing simple post function with table args: ")
back = socket.http.post {
	url = "http://" .. host .. cgiprefix .. "/cat",
	body = index
}
check(back == index)

io.write("testing http redirection: ")
request = {
	url = "http://" .. host .. prefix
}
expect = {
	body = index,
	code = 200
}
ignore = {
	status = 1,
	headers = 1
}
check_request(request, expect, ignore)

io.write("testing proxy with redirection: ")
request = {
	url = "http://" .. host .. prefix,
    host = proxyh,
    port = proxyp
}
expect = {
	body = index,
	code = 200
}
ignore = {
	status = 1,
	headers = 1
}
check_request(request, expect, ignore)


io.write("testing automatic auth failure: ")
request = {
    url = "http://really:wrong@" .. host .. prefix .. "/auth/index.html"
}
expect = {
    code = 401
}
ignore = {
    body = 1,
	status = 1,
	headers = 1
}
check_request(request, expect, ignore)

io.write("testing http redirection failure: ")
request = {
	url = "http://" .. host .. prefix,
	redirect = false
}
expect = {
    code = 301
}
ignore = {
    body = 1,
	status = 1,
	headers = 1
}
check_request(request, expect, ignore)
    
io.write("testing host not found: ")
request = {
	url = "http://wronghost/does/not/exist"
}
local c, e = socket.connect("wronghost", 80)
expect = {
	error = e
}
ignore = {}
check_request(request, expect, ignore)

io.write("testing invalid url: ")
request = {
	url = host .. prefix
}
local c, e = socket.connect("", 80)
expect = {
	error = e
}
ignore = {}
check_request(request, expect, ignore)

io.write("testing document not found: ")
request = {
	url = "http://" .. host .. "/wrongdocument.html"
}
expect = {
	code = 404
}
ignore = {
    body = 1,
	status = 1,
	headers = 1
}
check_request(request, expect, ignore)

io.write("testing auth failure: ")
request = {
	url = "http://" .. host .. prefix .. "/auth/index.html"
}
expect = {
	code = 401
}
ignore = {
    body = 1,
	status = 1,
	headers = 1
}
check_request(request, expect, ignore)

io.write("testing manual basic auth: ")
request = {
	url = "http://" .. host .. prefix .. "/auth/index.html",
	headers = {
		authorization = "Basic " .. (socket.code.b64("luasocket:password"))
	}
}
expect = {
	code = 200,
	body = index
}
ignore = {
	status = 1,
	headers = 1
}
check_request(request, expect, ignore)

io.write("testing automatic basic auth: ")
request = {
	url = "http://luasocket:password@" .. host .. prefix .. "/auth/index.html"
}
expect = {
	code = 200,
	body = index
}
ignore = {
	status = 1,
	headers = 1
}
check_request(request, expect, ignore)

io.write("testing auth info overriding: ")
request = {
	url = "http://really:wrong@" .. host .. prefix .. "/auth/index.html",
	user = "luasocket",
	password = "password"
}
expect = {
	code = 200,
	body = index
}
ignore = {
	status = 1,
	headers = 1
}
check_request(request, expect, ignore)

io.write("testing cgi output retrieval (probably chunked...): ")
request = {
    url = "http://" .. host .. cgiprefix .. "/cat-index-html"
}
expect = {
	body = index,
	code = 200
}
ignore = {
	status = 1,
	headers = 1
}
check_request(request, expect, ignore)

io.write("testing wrong scheme: ")
request = {
	url = "wrong://" .. host .. cgiprefix .. "/cat",
	method = "GET"
}
expect = {
	error = "unknown scheme 'wrong'"
}
ignore = {
}
check_request(request, expect, ignore)

local body
io.write("testing simple get function: ")
body = socket.http.get("http://" .. host .. prefix .. "/index.html")
check(body == index)

io.write("testing simple get function with table args: ")
body = socket.http.get {
	url = "http://really:wrong@" .. host .. prefix .. "/auth/index.html",
	user = "luasocket",
	password = "password"
}
check(body == index)

io.write("testing HEAD method: ")
socket.http.TIMEOUT = 1
response = socket.http.request {
  method = "HEAD",
  url = "http://www.cs.princeton.edu/~diego/"
}
check(response and response.headers)

print("passed all tests")

print(string.format("done in %.2fs", socket.time() - t))
