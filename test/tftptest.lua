-- load tftpclng.lua
assert(dofile("../examples/tftpclnt.lua"))

-- needs tftp server running on localhost, with root pointing to
-- /home/i/diego/public/html/luasocket/test

function readfile(file)
	local f = openfile("file", "rb")
	local a 
	if f then 
		a = read(f, "*a")
		closefile(f)
	end
	return a
end

host = host or "localhost"
print("downloading")
err = tftp_get(host, 69, "index.html", "index.got")
assert(not err, err)
original = readfile("index.index")
retrieved = readfile("index.got")
remove("index.got")
assert(original == retrieved, "files differ!")
print("passed")
