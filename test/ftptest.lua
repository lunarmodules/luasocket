assert(dofile("../lua/ftp.lua"))
assert(dofile("auxiliar.lua"))

pdir = "/home/i/diego/public/html/luasocket/test/"
ldir = "/home/luasocket/"
adir = "/home/ftp/test/"

-- needs an accound luasocket:password
-- and a copy of /home/i/diego/public/html/luasocket/test in ~ftp/test

print("testing authenticated upload")
bf = readfile(pdir .. "index.html")
e = ftp_put("ftp://luasocket:password@localhost/index.html", bf, "b")
assert(not e, e)
assert(compare(ldir .. "index.html", bf), "files differ")
remove(ldir .. "index.html")

print("testing authenticated download")
f, e = ftp_get("ftp://luasocket:password@localhost/test/index.html", "b")
assert(f, e)
assert(compare(pdir .. "index.html", f), "files differ")

print("testing anonymous download")
f, e = ftp_get("ftp://localhost/test/index.html", "b")
assert(f, e)
assert(compare(adir .. "index.html", f), "files differ")

print("testing directory listing")
f, e = ftp_get("ftp://localhost/test/")
assert(f, e)
assert(f == "index.html\r\n", "files differ")

print("passed all tests")
