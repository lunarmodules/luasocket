-----------------------------------------------------------------------------
-- LuaSocket automated test module
-- server.lua
-- This is the server module. It's completely controled by the client module
-- by the use of a control connection.
-----------------------------------------------------------------------------

-----------------------------------------------------------------------------
-- Read command definitions
-----------------------------------------------------------------------------
assert(dofile("testcmd.lua"))
test_debug_mode()

-----------------------------------------------------------------------------
-- Get host and port from command line
-----------------------------------------------------------------------------
HOST = "localhost"
PORT = 2020
if arg then
    HOST = arg[1] or HOST
    PORT = arg[2] or PORT
end

-----------------------------------------------------------------------------
-- Start control connection
-----------------------------------------------------------------------------
server, err = bind(HOST, PORT)
if not server then
	fail(err)
	exit(1)
end
print("server: waiting for control connection...")
control = server:accept()
print("server: control connection stablished!")

-----------------------------------------------------------------------------
-- Executes a command, detecting any possible failures
-- Input
--   cmd: command to be executed
--   par: command parameters, if needed
-----------------------------------------------------------------------------
function execute_command(cmd, par)
	if cmd == CONNECT then
		print("server: waiting for data connection...")
		data = server:accept()
		if not data then
			fail("server: unable to start data connection!")
		else
			print("server: data connection stablished!")
		end
	elseif cmd == CLOSE then
		print("server: closing connection with client...")
		if data then 
			data:close()
			data = nil
		end
	elseif cmd == ECHO_LINE then
		str, err = data:receive()
		if err then fail("server: " .. err) end
		err = data:send(str, "\n")
		if err then fail("server: " .. err) end
	elseif cmd == ECHO_BLOCK then
		str, err = data:receive(par)
		print(format("server: received %d bytes", strlen(str)))
		if err then fail("server: " .. err) end
		print(format("server: sending %d bytes", strlen(str)))
		err = data:send(str)
		if err then fail("server: " .. err) end
	elseif cmd == RECEIVE_BLOCK then
		str, err = data:receive(par)
		print(format("server: received %d bytes", strlen(str)))
	elseif cmd == SEND_BLOCK then
		print(format("server: sending %d bytes", strlen(str)))
		err = data:send(str)
	elseif cmd == ECHO_TIMEOUT then
		str, err = data:receive(par)
		if err then fail("server: " .. err) end
		err = data:send(str)
		if err then fail("server: " .. err) end
	elseif cmd == COMMAND then
		cmd, par = get_command()
		send_command(cmd, par)
	elseif cmd == EXIT then
		print("server: exiting...")
		exit(0)
	elseif cmd == SYNC then
		print("server: synchronizing...")
		send_command(SYNC)
	elseif cmd == SLEEP then
		print("server: sleeping for " .. par .. " seconds...")
		sleep(par)
		print("server: woke up!")
	end
end

-----------------------------------------------------------------------------
-- Loop forever, accepting and executing commands
-----------------------------------------------------------------------------
while 1 do
	cmd, par = get_command()
	if not cmd then fail("server: " .. par) end
	print_command(cmd, par)
	execute_command(cmd, par)
end
