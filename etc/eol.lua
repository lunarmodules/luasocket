require"mime.lua"
require"ltn12.lua"

local marker = '\n'
if arg and arg[1] == '-d' then marker = '\r\n' end
local filter = mime.normalize(marker)
local source = ltn12.source.chain(ltn12.source.file(io.stdin), filter)
local sink = ltn12.sink.file(io.stdout)
ltn12.pump.all(source, sink)
