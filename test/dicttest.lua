local dict = require"socket.dict"

for i,v in dict.get("dict://localhost/d:banana") do print(v) end
