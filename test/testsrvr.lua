socket = require("socket");
host = host or "localhost";
port = port or "8080";
server = assert(socket.bind(host, port));
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
