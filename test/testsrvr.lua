HOST = HOST or "localhost"
PORT = PORT or "8080"

server, error = socket.bind(HOST, PORT)
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
        error = control:send("\n")
        if error then
            control:close()
            print("server: closing connection...")
            break
        end
        (loadstring(command))()
    end
end
