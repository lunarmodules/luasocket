sink = ltn12.sink.file(io.open("lixo", "w"))
source = ltn12.source.file(io.open("luasocket", "r"))
ltn12.pump(source, sink)
