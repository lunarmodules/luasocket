local convert
if arg and arg[1] == '-d' then
    convert = socket.mime.decode("base64")
else
    local base64 = socket.mime.encode("base64")
    local wrap = socket.mime.wrap()
    convert = socket.mime.chain(base64, wrap)
end
while 1 do
    local chunk = io.read(4096)
    io.write(convert(chunk))
    if not chunk then break end
end
