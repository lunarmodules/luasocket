marker = {['-u'] = '\10', ['-d'] = '\13\10'}
arg = arg or {'-u'}
marker = marker[arg[1]] or marker['-u']
local convert = socket.mime.canonic(marker)
while 1 do
    local chunk = io.read(4096)
    io.write(convert(chunk))
    if not chunk then break end
end
