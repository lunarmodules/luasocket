-- needs Alias from /home/c/diego/tec/luasocket/test to 
-- /luasocket-test
-- needs ScriptAlias from /home/c/diego/tec/luasocket/test/cgi
-- to /luasocket-test-cgi
-- needs AllowOverride AuthConfig on /home/c/diego/tec/luasocket/test/auth

dofile("noglobals.lua")

local similar = function(s1, s2)
	return strlower(gsub(s1 or "", "%s", "")) == 
        strlower(gsub(s2 or "", "%s", ""))
end

local fail = function(s)
	s = s or "failed!"
	print(s)
	exit()
end

local readfile = function(name)
	local f = readfrom(name)
	if not f then return nil end
	local s = read("*a")
	readfrom()
	return s
end

local check = function (v, e)
	if v then print("ok")
	else %fail(e) end
end
	
local check_request = function(request, expect, ignore)
	local response = HTTP.request(request)
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

dofile("../src/modules/http.lua")

local request, response, ignore, expect, index, prefix, cgiprefix

local t = _time()

HOST = HOST or "localhost"
prefix = prefix or "/luasocket-test"
cgiprefix = cgiprefix or "/luasocket-test-cgi"
index = readfile("index.html")

write("testing request uri correctness: ")
local forth = cgiprefix .. "/request-uri?" .. "this+is+the+query+string"
local back = HTTP.get("http://" .. HOST .. forth)
if similar(back, forth) then print("ok")
else fail("failed!") end

write("testing query string correctness: ")
forth = "this+is+the+query+string"
back = HTTP.get("http://" .. HOST .. cgiprefix .. "/query-string?" .. forth)
if similar(back, forth) then print("ok")
else fail("failed!") end

write("testing document retrieval: ")
request = {
	url = "http://" .. HOST .. prefix .. "/index.html"
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

write("testing HTTP redirection: ")
request = {
	url = "http://" .. HOST .. prefix
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


write("testing automatic auth failure: ")
request = {
    url = "http://really:wrong@" .. HOST .. prefix .. "/auth/index.html"
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

write("testing HTTP redirection failure: ")
request = {
	url = "http://" .. HOST .. prefix,
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
    
write("testing host not found: ")
request = {
	url = "http://wronghost/does/not/exist"
}
local c, e = connect("wronghost", 80)
expect = {
	error = e
}
ignore = {}
check_request(request, expect, ignore)

write("testing invalid url: ")
request = {
	url = HOST .. prefix
}
local c, e = connect("", 80)
expect = {
	error = e
}
ignore = {}
check_request(request, expect, ignore)

write("testing document not found: ")
request = {
	url = "http://" .. HOST .. "/wrongdocument.html"
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

write("testing auth failure: ")
request = {
	url = "http://" .. HOST .. prefix .. "/auth/index.html"
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

write("testing manual basic auth: ")
request = {
	url = "http://" .. HOST .. prefix .. "/auth/index.html",
	headers = {
		authorization = "Basic " .. Code.base64("luasocket:password")
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

write("testing automatic basic auth: ")
request = {
	url = "http://luasocket:password@" .. HOST .. prefix .. "/auth/index.html"
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

write("testing auth info overriding: ")
request = {
	url = "http://really:wrong@" .. HOST .. prefix .. "/auth/index.html",
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

write("testing cgi output retrieval (probably chunked...): ")
request = {
    url = "http://" .. HOST .. cgiprefix .. "/cat-index-html"
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

write("testing redirect loop: ")
request = {
    url = "http://" .. HOST .. cgiprefix .. "/redirect-loop"
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

write("testing post method: ")
request = {
	url = "http://" .. HOST .. cgiprefix .. "/cat",
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

write("testing wrong scheme: ")
request = {
	url = "wrong://" .. HOST .. cgiprefix .. "/cat",
	method = "GET"
}
expect = {
	error = "unknown scheme 'wrong'"
}
ignore = {
}
check_request(request, expect, ignore)

local body
write("testing simple get function: ")
body = HTTP.get("http://" .. HOST .. prefix .. "/index.html")
check(body == index)

write("testing simple get function with table args: ")
body = HTTP.get {
	url = "http://really:wrong@" .. HOST .. prefix .. "/auth/index.html",
	user = "luasocket",
	password = "password"
}
check(body == index)

write("testing simple post function: ")
body = HTTP.post("http://" .. HOST .. cgiprefix .. "/cat", index)
check(body == index)

write("testing simple post function with table args: ")
body = HTTP.post {
	url = "http://" .. HOST .. cgiprefix .. "/cat",
	body = index
}
check(body == index)

write("testing HEAD method: ")
response = HTTP.request {
  method = "HEAD",
  url = "http://www.tecgraf.puc-rio.br/~diego/"
}
check(response and response.headers)

print("passed all tests")

print(format("done in %.2fs", _time() - t))
