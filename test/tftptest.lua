-- load tftpclnt.lua
dofile("tftpclnt.lua")

-- needs tftp server running on localhost, with root pointing to
-- a directory with index.html in it

function readfile(file)
    local f = io.open(file, "r")
    if not f then return nil end
    local a = f:read("*a")
    f:close()
    return a
end

host = host or "localhost"
print("downloading")
err = tftp_get(host, 69, "index.html", "index.got")
assert(not err, err)
original = readfile("test/index.html")
retrieved = readfile("index.got")
os.remove("index.got")
assert(original == retrieved, "files differ!")
print("passed")
