-- load tftpclng.lua
assert(dofile("../examples/tftpclnt.lua"))
assert(dofile("auxiliar.lua"))

-- needs tftp server running on localhost, with root pointing to
-- /home/i/diego/public/html/luasocket/test

host = host or "localhost"
print("downloading")
err = tftp_get(host, 69, "test/index.html")
assert(not err, err)
original = readfile("/home/i/diego/public/html/luasocket/test/index.html")
retrieved = readfile("index.html")
remove("index.html")
assert(original == retrieved, "files differ!")
print("passed")
