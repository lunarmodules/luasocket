require("socket");
os.remove("/tmp/luasocket")
socket = require("socket.unix");
host = "luasocket";
server = socket.unix()
print(server:bind(host))
print(server:listen(5))
ack = "\n";
while 1 do
    print("server: waiting for client connection...");
    control = assert(server:accept());
    while 1 do 
        command = assert(control:receive());
        assert(control:send(ack));
        (loadstring(command))();
    end
end
