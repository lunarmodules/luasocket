marker = {['-u'] = '\10', ['-d'] = '\13\10'}
arg = arg or {'-u'}
marker = marker[arg[1]] or marker['-u']
local convert = socket.mime.normalize(marker)
while 1 do
    local chunk = io.read(1)
    io.write(convert(chunk))
    if not chunk then break end
end
