-- needs Alias from /home/c/diego/tec/luasocket/test to 
-- /luasocket-test
-- needs ScriptAlias from /home/c/diego/tec/luasocket/test/cgi
-- to /luasocket-test-cgi
-- needs AllowOverride AuthConfig on /home/c/diego/tec/luasocket/test/auth

dofile("noglobals.lua")

local similar = function(s1, s2)
	return string.lower(string.gsub(s1 or "", "%s", "")) == 
        string.lower(string.gsub(s2 or "", "%s", ""))
end

local fail = function(s)
	s = s or "failed!"
	print(s)
	os.exit()
end

local readfile = function(name)
	local f = io.open(name, "r")
	if not f then return nil end
	local s = f:read("*a")
	f:close()
	return s
end

local check = function (v, e)
	if v then print("ok")
	else %fail(e) end
end
	
local check_request = function(request, expect, ignore)
	local response = socket.http.request(request)
	for i,v in response do
		if not ignore[i] then
			if v ~= expect[i] then %fail(i .. " differs!") end
		end
	end
	for i,v in expect do
		if not ignore[i] then
			if v ~= response[i] then %fail(i .. " differs!") end
		end
	end
	print("ok")
end

local request, response, ignore, expect, index, prefix, cgiprefix

local t = socket._time()

host = host or "localhost"
prefix = prefix or "/luasocket"
cgiprefix = cgiprefix or "/luasocket/cgi"
index = readfile("test/index.html")

io.write("testing request uri correctness: ")
local forth = cgiprefix .. "/request-uri?" .. "this+is+the+query+string"
local back = socket.http.get("http://" .. host .. forth)
if similar(back, forth) then print("ok")
else fail("failed!") end

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
	stay = 1
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
		authorization = "Basic " .. socket.code.base64("luasocket:password")
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
request = {
	url = "http://" .. host .. cgiprefix .. "/cat",
	method = "POST",
	body = index
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

io.write("testing simple post function: ")
body = socket.http.post("http://" .. host .. cgiprefix .. "/cat", index)
check(body == index)

io.write("testing simple post function with table args: ")
body = socket.http.post {
	url = "http://" .. host .. cgiprefix .. "/cat",
	body = index
}
check(body == index)

io.write("testing HEAD method: ")
response = socket.http.request {
  method = "HEAD",
  url = "http://www.tecgraf.puc-rio.br/~diego/"
}
check(response and response.headers)

print("passed all tests")

print(string.format("done in %.2fs", socket._time() - t))
