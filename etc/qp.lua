local convert
arg = arg or {}
local mode = arg and arg[1] or "-et"
if mode == "-et" then
    local canonic = socket.mime.canonic()
    local qp = socket.mime.encode("quoted-printable")
    local wrap = socket.mime.wrap("quoted-printable")
    convert = socket.mime.chain(canonic, qp, wrap)
elseif mode == "-eb" then
    local qp = socket.mime.encode("quoted-printable", "binary")
    local wrap = socket.mime.wrap("quoted-printable")
    convert = socket.mime.chain(qp, wrap)
else convert = socket.mime.decode("quoted-printable") end
while 1 do
    local chunk = io.read(4096)
    io.write(convert(chunk))
    if not chunk then break end
end
