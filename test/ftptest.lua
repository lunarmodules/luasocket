local similar = function(s1, s2)
    return 
    string.lower(string.gsub(s1, "%s", "")) == 
    string.lower(string.gsub(s2, "%s", ""))
end

local readfile = function(name)
	local f = io.open(name, "r")
	if not f then return nil end
	local s = f:read("*a")
	f:close()
	return s
end

local capture = function(cmd)
	local f = io.popen(cmd)
	if not f then return nil end
	local s = f:read("*a")
	f:close()
	return s
end

local check = function(v, e, o)
	e = e or "failed!"
	o = o or "ok"
	if v then print(o)
	else print(e) os.exit() end
end

-- needs an account luasocket:password
-- and some directories and files in ~ftp

local index, err, saved, back, expected

local t = socket.time()

index = readfile("test/index.html")

io.write("testing wrong scheme: ")
back, err = socket.ftp.get("wrong://banana.com/lixo")
check(not back and err == "unknown scheme 'wrong'", err)

io.write("testing invalid url: ")
back, err = socket.ftp.get("localhost/dir1/index.html;type=i")
local c, e = socket.connect("", 21)
check(not back and err == e, err)

io.write("testing anonymous file upload: ")
os.remove("/var/ftp/pub/index.up.html")
err = socket.ftp.put("ftp://localhost/pub/index.up.html;type=i", index)
saved = readfile("/var/ftp/pub/index.up.html")
check(not err and saved == index, err)

io.write("testing anonymous file download: ")
back, err = socket.ftp.get("ftp://localhost/pub/index.up.html;type=i")
check(not err and back == index, err)

io.write("testing no directory changes: ")
back, err = socket.ftp.get("ftp://localhost/index.html;type=i")
check(not err and back == index, err)

io.write("testing multiple directory changes: ")
back, err = socket.ftp.get("ftp://localhost/pub/dir1/dir2/dir3/dir4/dir5/index.html;type=i")
check(not err and back == index, err)

io.write("testing authenticated upload: ")
os.remove("/home/luasocket/index.up.html")
err = socket.ftp.put("ftp://luasocket:password@localhost/index.up.html;type=i", index)
saved = readfile("/home/luasocket/index.up.html")
check(not err and saved == index, err)

io.write("testing authenticated download: ")
back, err = socket.ftp.get("ftp://luasocket:password@localhost/index.up.html;type=i")
check(not err and back == index, err)

io.write("testing weird-character translation: ")
back, err = socket.ftp.get("ftp://luasocket:password@localhost/%2fvar/ftp/pub/index.html;type=i")
check(not err and back == index, err)

io.write("testing parameter overriding: ")
back, err = socket.ftp.get {
	url = "//stupid:mistake@localhost/index.html",
	user = "luasocket",
	password = "password",
	type = "i"
}
check(not err and back == index, err)

io.write("testing home directory listing: ")
expected = capture("ls -F /var/ftp | grep -v /")
back, err = socket.ftp.get("ftp://localhost/")
check(back and similar(back, expected), nil, err)

io.write("testing directory listing: ")
expected = capture("ls -F /var/ftp/pub | grep -v /")
back, err = socket.ftp.get("ftp://localhost/pub;type=d")
check(similar(back, expected))

io.write("testing upload denial: ")
err = socket.ftp.put("ftp://localhost/index.up.html;type=a", index)
check(err, err)

io.write("testing authentication failure: ")
err = socket.ftp.put("ftp://luasocket:wrong@localhost/index.html;type=a", index)
print(err)
check(err, err)

io.write("testing wrong file: ")
back, err = socket.ftp.get("ftp://localhost/index.wrong.html;type=a")
check(err, err)

print("passed all tests")
print(string.format("done in %.2fs", socket.time() - t))
