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

assert(dofile("../lua/ftp.lua"))
assert(dofile("../lua/url.lua"))
assert(dofile("../lua/concat.lua"))
assert(dofile("../lua/code.lua"))

local similar = function(s1, s2)
    return strlower(gsub(s1, "%s", "")) == strlower(gsub(s2, "%s", ""))
end

local capture = function(cmd)
	readfrom("| " .. cmd)
	local s = read("*a")
	readfrom()
	return s
end

local readfile = function(name)
    local f = readfrom(name)
    if not f then return nil end
    local s = read("*a")
    readfrom()
    return s
end

local check = function(v, e, o)
	e = e or "failed!"
	o = o or "ok"
	if v then print(o)
	else print(e) exit() end
end

-- needs an account luasocket:password
-- and some directories and files in ~ftp

local index, err, saved, back, expected

local t = _time()

index = readfile("index.html")

write("testing file upload: ")
remove("/home/ftp/dir1/index.up.html")
err = FTP.put("ftp://localhost/dir1/index.up.html;type=i", index)
saved = readfile("/home/ftp/dir1/index.up.html")
check(not err and saved == index, err)

write("testing file download: ")
back, err = FTP.get("ftp://localhost/dir1/index.up.html;type=i")
check(not err and back == index, err)

write("testing no directory changes: ")
back, err = FTP.get("ftp://localhost/index.html;type=i")
check(not err and back == index, err)

write("testing multiple directory changes: ")
back, err = FTP.get("ftp://localhost/dir1/dir2/dir3/dir4/dir5/dir6/index.html;type=i")
check(not err and back == index, err)

write("testing authenticated upload: ")
remove("/home/luasocket/index.up.html")
err = FTP.put("ftp://luasocket:password@localhost/index.up.html;type=i", index)
saved = readfile("/home/luasocket/index.up.html")
check(not err and saved == index, err)

write("testing authenticated download: ")
back, err = FTP.get("ftp://luasocket:password@localhost/index.up.html;type=i")
check(not err and back == index, err)

write("testing weird-character translation: ")
back, err = FTP.get("ftp://luasocket:password@localhost/%2fhome/ftp/dir1/index.html;type=i")
check(not err and back == index, err)

write("testing parameter overriding: ")
back, err = FTP.get {
	url = "//stupid:mistake@localhost/dir1/index.html",
	user = "luasocket",
	password = "password",
	type = "i"
}
check(not err and back == index, err)

write("testing invalid url: ")
back, err = FTP.get("localhost/dir1/index.html;type=i")
local c, e = connect("", 21)
check(not back and err == e, err)

write("testing directory listing: ")
expected = capture("ls -F /home/ftp/dir1 | grep -v /")
back, err = FTP.get("ftp://localhost/dir1;type=d")
check(similar(back, expected))

write("testing home directory listing: ")
expected = capture("ls -F /home/ftp | grep -v /")
back, err = FTP.get("ftp://localhost/")
check(back and similar(back, expected), nil, err)

write("testing upload denial: ")
err = FTP.put("ftp://localhost/index.up.html;type=a", index)
check(err, err)

write("testing authentication failure: ")
err = FTP.put("ftp://luasocket:wrong@localhost/index.html;type=a", index)
check(err, err)

write("testing wrong file: ")
back, err = FTP.get("ftp://localhost/index.wrong.html;type=a")
check(err, err)

print("passed all tests")
print(format("done in %.2fs", _time() - t))
