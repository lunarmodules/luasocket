-- load http
assert(dofile("../lua/http.lua"))
assert(dofile("../lua/base64.lua"))
assert(dofile("auxiliar.lua"))

-- needs Alias from /home/i/diego/public/html/luasocket/test to 
-- /luasocket-test
-- needs ScriptAlias from /home/i/diego/public/html/luasocket/test/cgi-bin
-- to /luasocket-cgi-bin/

function join(s, e)
  return tostring(s) .. ":" .. tostring(e)
end

function status(s)
	local code
	_,_, code = strfind(s, "(%d%d%d)")
	return tonumber(code)
end

pdir = pdir or "/home/i/diego/public/html/luasocket/test/"
host = host or "localhost"

print("testing document retrieval")
url = "http://" .. host .. "/luasocket-test/index.html"
f, m, s, e = http_get(url)
assert(f and m and s and not e, join(s, e))
assert(compare(pdir .. "index.html", f), "documents differ")

print("testing HTTP redirection")
url = "http://" .. host .. "/luasocket-test"
f, m, s, e = http_get(url)
assert(f and m and s and not e, join(s, e))
assert(compare(pdir .. "index.html", f), "documents differ")

print("testing cgi output retrieval (probably chunked...)")
url = "http://" .. host .. "/luasocket-cgi-bin/cat-index-html"
f, m, s, e = http_get(url)
assert(f and m and s and not e, join(s, e))
assert(compare(pdir .. "index.html", f), "documents differ")

print("testing post method")
url = "http://" .. host .. "/luasocket-cgi-bin/cat"
rf = strrep("!@#$!@#%", 80000)
f, m, s, e = http_post(url, rf)
assert(f and m and s and not e)
assert(rf == f, "files differ")

print("testing automatic auth failure")
url = "http://really:wrong@" .. host .. "/luasocket-test/auth/index.html"
f, m, s, e = http_get(url)
assert(f and m and s and not e and status(s) == 401)

write("testing host not found: ")
url = "http://wronghost/luasocket-test/index.html"
f, m, s, e = http_get(url)
assert(not f and not m and not s and e)
print(e)

write("testing auth failure: ")
url = "http://" .. host .. "/luasocket-test/auth/index.html"
f, m, s, e = http_get(url)
assert(f and m and s and not e and status(s) == 401)
print(s)

write("testing document not found: ")
url = "http://" .. host .. "/luasocket-test/wrongdocument.html"
f, m, s, e = http_get(url)
assert(f and m and s and not e and status(s) == 404)
print(s)

print("testing manual auth")
url = "http://" .. host .. "/luasocket-test/auth/index.html"
h = {authorization = "Basic " .. base64("luasocket:password")}
f, m, s, e = http_get(url, h)
assert(f and m and s and not e, join(s, e))
assert(compare(pdir .. "auth/index.html", f), "documents differ")

print("testing automatic auth")
url = "http://luasocket:password@" .. host .. "/luasocket-test/auth/index.html"
f, m, s, e = http_get(url)
assert(f and m and s and not e, join(s, e))
assert(compare(pdir .. "auth/index.html", f), "documents differ")

print("passed all tests")
