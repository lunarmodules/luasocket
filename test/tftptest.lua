-- load tftpclnt.lua
dofile("tftp.lua")

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
retrieved, err = socket.tftp.get("tftp://" .. host .."/index.html")
assert(not err, err)
original = readfile("test/index.html")
assert(original == retrieved, "files differ!")
print("passed")
