host = host or "localhost"
port = port or "8080"

server, error = socket.bind(host, port)
if not server then print("server: " .. tostring(error)) os.exit() end
while 1 do
    print("server: waiting for client connection...");
    control = server:accept()
    while 1 do 
        command, error = control:receive()
        if error then
            control:close()
            print("server: closing connection...")
            break
        end
        sent, error = control:send("\n")
        if error then
            control:close()
            print("server: closing connection...")
            break
        end
        print(command);
        (loadstring(command))()
    end
end
