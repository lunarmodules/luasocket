local dict = require"socket.dict"

for i,v in dict.get("dict://localhost/d:teste") do print(v) end
