function mysetglobal (varname, oldvalue, newvalue)
    print("changing " .. varname)
     %rawset(%globals(), varname, newvalue)
end
function mygetglobal (varname, newvalue)
    print("checking " .. varname)
     return %rawget(%globals(), varname)
end
settagmethod(tag(nil), "setglobal", mysetglobal)
settagmethod(tag(nil), "getglobal", mygetglobal)

assert(dofile "../lua/code.lua")
assert(dofile "../lua/url.lua")

local check_protect = function(parsed, path)
	local built = URL.build_path(parsed)
	if built ~= path then
		print(built, path)
	    print("path composition failed.")
		exit()
	end
end

local check_invert = function(url)
	local parsed = URL.parse_url(url)
	parsed.path = URL.build_path(URL.parse_path(parsed.path))
	local rebuilt = URL.build_url(parsed)
	if rebuilt ~= url then
		print(url, rebuilt)
	    print("original and rebuilt are different")
		exit()
	end
end

local check_parse_path = function(path, expect)
	local parsed = URL.parse_path(path)
	for i = 1, max(getn(parsed), getn(expect)) do
		if parsed[i] ~= expect[i] then
			print(path)
		    write("segment: ", i, " = '", Code.hexa(tostring(parsed[i])),
				"' but expected '", Code.hexa(tostring(expect[i])), "'\n")
            exit()
		end
	end
	if expect.is_directory ~= parsed.is_directory then
		print(path)
	    print("is_directory mismatch")
		exit()
	end
	if expect.is_absolute ~= parsed.is_absolute then
		print(path)
	    print("is_absolute mismatch")
		exit()
	end
	local built = URL.build_path(expect)
	if built ~= path then
		print(built, path)
	    print("path composition failed.")
		exit()
	end
end

local check_absolute_url = function(base, relative, absolute)
	local res = URL.absolute_url(base, relative)
	if res ~= absolute then 
		write("absolute: In test for '", relative, "' expected '", 
            absolute, "' but got '", res, "'\n")
		exit()
	end
end

local check_parse_url = function(gaba)
	local url = gaba.url
	gaba.url = nil
	local parsed = URL.parse_url(url)
	for i, v in gaba do
		if v ~= parsed[i] then
			write("parse: In test for '", url, "' expected ", i, " = '", 
           	    v, "' but got '", tostring(parsed[i]), "'\n")
			for i,v in parsed do print(i,v) end
			exit()
		end
	end
	for i, v in parsed do
		if v ~= gaba[i] then
			write("parse: In test for '", url, "' expected ", i, " = '", 
           	    tostring(gaba[i]), "' but got '", v, "'\n")
			for i,v in parsed do print(i,v) end
			exit()
		end
	end
end

print("testing URL parsing")
check_parse_url{
	url = "scheme://userinfo@host:port/path;params?query#fragment",
	scheme = "scheme", 
	authority = "userinfo@host:port", 
	host = "host",
	port = "port",
	userinfo = "userinfo",
	user = "userinfo",
	path = "/path",
	params = "params",
	query = "query",
	fragment = "fragment"
}

check_parse_url{
	url = "scheme://user:password@host:port/path;params?query#fragment",
	scheme = "scheme", 
	authority = "user:password@host:port", 
	host = "host",
	port = "port",
	userinfo = "user:password",
	user = "user",
	password = "password",
	path = "/path",
	params = "params",
	query = "query",
	fragment = "fragment",
}

check_parse_url{
	url = "scheme://userinfo@host:port/path;params?query#",
	scheme = "scheme", 
	authority = "userinfo@host:port", 
	host = "host",
	port = "port",
	userinfo = "userinfo",
	user = "userinfo",
	path = "/path",
	params = "params",
	query = "query",
	fragment = ""
}

check_parse_url{
	url = "scheme://userinfo@host:port/path;params?#fragment",
	scheme = "scheme", 
	authority = "userinfo@host:port", 
	host = "host",
	port = "port",
	userinfo = "userinfo",
	user = "userinfo",
	path = "/path",
	params = "params",
	query = "",
	fragment = "fragment"
}

check_parse_url{
	url = "scheme://userinfo@host:port/path;params#fragment",
	scheme = "scheme", 
	authority = "userinfo@host:port", 
	host = "host",
	port = "port",
	userinfo = "userinfo",
	user = "userinfo",
	path = "/path",
	params = "params",
	fragment = "fragment"
}

check_parse_url{
	url = "scheme://userinfo@host:port/path;?query#fragment",
	scheme = "scheme", 
	authority = "userinfo@host:port", 
	host = "host",
	port = "port",
	userinfo = "userinfo",
	user = "userinfo",
	path = "/path",
	params = "",
	query = "query",
	fragment = "fragment"
}

check_parse_url{
	url = "scheme://userinfo@host:port/path?query#fragment",
	scheme = "scheme", 
	authority = "userinfo@host:port", 
	host = "host",
	port = "port",
	userinfo = "userinfo",
	user = "userinfo",
	path = "/path",
	query = "query",
	fragment = "fragment"
}

check_parse_url{
	url = "scheme://userinfo@host:port/;params?query#fragment",
	scheme = "scheme", 
	authority = "userinfo@host:port", 
	host = "host",
	port = "port",
	userinfo = "userinfo",
	user = "userinfo",
	path = "/",
	params = "params",
	query = "query",
	fragment = "fragment"
}

check_parse_url{
	url = "scheme://userinfo@host:port",
	scheme = "scheme", 
	authority = "userinfo@host:port", 
	host = "host",
	port = "port",
	userinfo = "userinfo",
	user = "userinfo",
}

check_parse_url{
	url = "//userinfo@host:port/path;params?query#fragment",
	authority = "userinfo@host:port", 
	host = "host",
	port = "port",
	userinfo = "userinfo",
	user = "userinfo",
	path = "/path",
	params = "params",
	query = "query",
	fragment = "fragment"
}

check_parse_url{
	url = "//userinfo@host:port/path",
	authority = "userinfo@host:port", 
	host = "host",
	port = "port",
	userinfo = "userinfo",
	user = "userinfo",
	path = "/path",
}

check_parse_url{
	url = "//userinfo@host/path",
	authority = "userinfo@host", 
	host = "host",
	userinfo = "userinfo",
	user = "userinfo",
	path = "/path",
}

check_parse_url{
	url = "//user:password@host/path",
	authority = "user:password@host", 
	host = "host",
	userinfo = "user:password",
	password = "password",
	user = "user",
	path = "/path",
}

check_parse_url{
	url = "//user:@host/path",
	authority = "user:@host", 
	host = "host",
	userinfo = "user:",
	password = "",
	user = "user",
	path = "/path",
}

check_parse_url{
	url = "//user@host:port/path",
	authority = "user@host:port", 
	host = "host",
	userinfo = "user",
	user = "user",
	port = "port",
	path = "/path",
}

check_parse_url{
	url = "//host:port/path",
	authority = "host:port", 
	port = "port",
	host = "host",
	path = "/path",
}

check_parse_url{
	url = "//host/path",
	authority = "host", 
	host = "host",
	path = "/path",
}

check_parse_url{
	url = "//host",
	authority = "host", 
	host = "host",
}

check_parse_url{
	url = "/path",
	path = "/path",
}

check_parse_url{
	url = "path",
	path = "path",
}

-- standard RFC tests
print("testing absolute resolution")
check_absolute_url("http://a/b/c/d;p?q#f", "g:h", "g:h")
check_absolute_url("http://a/b/c/d;p?q#f", "g", "http://a/b/c/g")
check_absolute_url("http://a/b/c/d;p?q#f", "./g", "http://a/b/c/g")
check_absolute_url("http://a/b/c/d;p?q#f", "g/", "http://a/b/c/g/")
check_absolute_url("http://a/b/c/d;p?q#f", "/g", "http://a/g")
check_absolute_url("http://a/b/c/d;p?q#f", "//g", "http://g")
check_absolute_url("http://a/b/c/d;p?q#f", "?y", "http://a/b/c/d;p?y")
check_absolute_url("http://a/b/c/d;p?q#f", "g?y", "http://a/b/c/g?y")
check_absolute_url("http://a/b/c/d;p?q#f", "g?y/./x", "http://a/b/c/g?y/./x")
check_absolute_url("http://a/b/c/d;p?q#f", "#s", "http://a/b/c/d;p?q#s")
check_absolute_url("http://a/b/c/d;p?q#f", "g#s", "http://a/b/c/g#s")
check_absolute_url("http://a/b/c/d;p?q#f", "g#s/./x", "http://a/b/c/g#s/./x")
check_absolute_url("http://a/b/c/d;p?q#f", "g?y#s", "http://a/b/c/g?y#s")
check_absolute_url("http://a/b/c/d;p?q#f", ";x", "http://a/b/c/d;x")
check_absolute_url("http://a/b/c/d;p?q#f", "g;x", "http://a/b/c/g;x")
check_absolute_url("http://a/b/c/d;p?q#f", "g;x?y#s", "http://a/b/c/g;x?y#s")
check_absolute_url("http://a/b/c/d;p?q#f", ".", "http://a/b/c/")
check_absolute_url("http://a/b/c/d;p?q#f", "./", "http://a/b/c/")
check_absolute_url("http://a/b/c/d;p?q#f", "..", "http://a/b/")
check_absolute_url("http://a/b/c/d;p?q#f", "../", "http://a/b/")
check_absolute_url("http://a/b/c/d;p?q#f", "../g", "http://a/b/g")
check_absolute_url("http://a/b/c/d;p?q#f", "../..", "http://a/")
check_absolute_url("http://a/b/c/d;p?q#f", "../../", "http://a/")
check_absolute_url("http://a/b/c/d;p?q#f", "../../g", "http://a/g")
check_absolute_url("http://a/b/c/d;p?q#f", "", "http://a/b/c/d;p?q#f")
check_absolute_url("http://a/b/c/d;p?q#f", "/./g", "http://a/./g")
check_absolute_url("http://a/b/c/d;p?q#f", "/../g", "http://a/../g")
check_absolute_url("http://a/b/c/d;p?q#f", "g.", "http://a/b/c/g.")
check_absolute_url("http://a/b/c/d;p?q#f", ".g", "http://a/b/c/.g")
check_absolute_url("http://a/b/c/d;p?q#f", "g..", "http://a/b/c/g..")
check_absolute_url("http://a/b/c/d;p?q#f", "..g", "http://a/b/c/..g")
check_absolute_url("http://a/b/c/d;p?q#f", "./../g", "http://a/b/g")
check_absolute_url("http://a/b/c/d;p?q#f", "./g/.", "http://a/b/c/g/")
check_absolute_url("http://a/b/c/d;p?q#f", "g/./h", "http://a/b/c/g/h")
check_absolute_url("http://a/b/c/d;p?q#f", "g/../h", "http://a/b/c/h")

-- extra tests
check_absolute_url("//a/b/c/d;p?q#f", "d/e/f", "//a/b/c/d/e/f")
check_absolute_url("/a/b/c/d;p?q#f", "d/e/f", "/a/b/c/d/e/f")
check_absolute_url("a/b/c/d", "d/e/f", "a/b/c/d/e/f")
check_absolute_url("a/b/c/d/../", "d/e/f", "a/b/c/d/e/f")
check_absolute_url("http://velox.telemar.com.br", "/dashboard/index.html", 
   "http://velox.telemar.com.br/dashboard/index.html")

print("testing path parsing and composition")
check_parse_path("/eu/tu/ele", { "eu", "tu", "ele"; is_absolute = 1 })
check_parse_path("/eu/", { "eu"; is_absolute = 1, is_directory = 1 })
check_parse_path("eu/tu/ele/nos/vos/eles/", 
	{ "eu", "tu", "ele", "nos", "vos", "eles"; is_directory = 1})
check_parse_path("/", { is_absolute = 1, is_directory = 1})
check_parse_path("", { })
check_parse_path("eu%01/%02tu/e%03l%04e/nos/vos%05/e%12les/", 
	{ "eu\1", "\2tu", "e\3l\4e", "nos", "vos\5", "e\18les"; is_directory = 1})
check_parse_path("eu/tu", { "eu", "tu" })

print("testing path protection")
check_protect({ "eu", "-_.!~*'():@&=+$,", "tu" }, "eu/-_.!~*'():@&=+$,/tu")
check_protect({ "eu ", "~diego" }, "eu%20/~diego")
check_protect({ "/eu>", "<diego?" }, "%2feu%3e/%3cdiego%3f")
check_protect({ "\\eu]", "[diego`" }, "%5ceu%5d/%5bdiego%60")
check_protect({ "{eu}", "|diego\127" }, "%7beu%7d/%7cdiego%7f")

print("testing inversion")
check_invert("http:")
check_invert("a/b/c/d.html")
check_invert("//net_loc")
check_invert("http:a/b/d/c.html")
check_invert("//net_loc/a/b/d/c.html")
check_invert("http://net_loc/a/b/d/c.html")
check_invert("//who:isit@net_loc")
check_invert("http://he:man@boo.bar/a/b/c/i.html;type=moo?this=that#mark")
check_invert("/b/c/d#fragment")
check_invert("/b/c/d;param#fragment")
check_invert("/b/c/d;param?query#fragment")
check_invert("/b/c/d?query")
check_invert("/b/c/d;param?query")

print("the library passed all tests")
