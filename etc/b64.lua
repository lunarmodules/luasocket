local base64 = socket.mime.base64.encode()
local split = socket.mime.split()
local convert = socket.mime.chain(base64, split)
while 1 do
    local chunk = io.read(4096)
    io.write(convert(chunk))
    if not chunk then break end
end
