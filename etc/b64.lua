local source = ltn12.source.file(io.stdin)
local sink = ltn12.sink.file(io.stdout)
local convert
if arg and arg[1] == '-d' then
    convert = mime.decode("base64")
else
    local base64 = mime.encode("base64")
    local wrap = mime.wrap()
    convert = ltn12.filter.chain(base64, wrap)
end
source = ltn12.source.chain(source, convert)
repeat until not ltn12.pump(source, sink)
