-----------------------------------------------------------------------------
-- LuaSocket automated test module
-- client.lua
-- This is the client module. It connects with the server module and executes
-- all tests.
-----------------------------------------------------------------------------

-----------------------------------------------------------------------------
-- Prints a header to separate the test phases
-- Input
--   test: test phase name
-----------------------------------------------------------------------------
function new_test(test)
	write("----------------------------------------------\n",
		test, "\n",
		"----------------------------------------------\n")
end

-----------------------------------------------------------------------------
-- Read command definitions and stablish control connection
-----------------------------------------------------------------------------
new_test("initializing...")
dofile("command.lua")
test_debug_mode()
while control == nil do
	print("client: trying control connection...")
	control, err = connect(HOST, PORT)
	if control then
		print("client: control connection stablished!") 
	else
		sleep(2)
	end
end

-----------------------------------------------------------------------------
-- Make sure server is ready for data transmission
-----------------------------------------------------------------------------
function sync()
	send_command(SYNC)
	get_command()
end

-----------------------------------------------------------------------------
-- Close and reopen data connection, to get rid of any unread blocks
-----------------------------------------------------------------------------
function reconnect()
	if data then 
		data:close() 
		send_command(CLOSE)
		data = nil
	end
	while data == nil do
		send_command(CONNECT)
		data = connect(HOST, PORT)
		if not data then 
			print("client: waiting for data connection.") 
			sleep(1)
		end
	end
	sync()
end

-----------------------------------------------------------------------------
-- Tests the command connection
-----------------------------------------------------------------------------
function test_command(cmd, par)
	local cmd_back, par_back
	reconnect()
	send_command(COMMAND)
	write("testing command ")
	print_command(cmd, par)
	send_command(cmd, par)
	cmd_back, par_back = get_command()
	if cmd_back ~= cmd or par_back ~= par then
		fail(cmd)
	else
		pass()
	end
end

-----------------------------------------------------------------------------
-- Tests ASCII line transmission
-- Input
--   len: length of line to be tested
-----------------------------------------------------------------------------
function test_asciiline(len)
	local str, str10, back, err
	reconnect()
	send_command(ECHO_LINE)
	str = strrep("x", mod(len, 10))
	str10 = strrep("aZb.c#dAe?", floor(len/10))
	str = str .. str10
	write("testing ", len, " byte(s) line\n")
	err = data:send(str, "\n")
	if err then fail(err) end
	back, err = data:receive()
	if err then fail(err) end
	if back == str then pass("lines match")
	else fail("lines don't match") end
end

-----------------------------------------------------------------------------
-- Tests closed connection detection
-----------------------------------------------------------------------------
function test_closed()
	local str = "This is our little test line"
	local len = strlen(str)
	local back, err, total
	reconnect()
	print("testing close while reading line")
	send_command(ECHO_BLOCK, len)
	data:send(str)
	send_command(CLOSE)
	-- try to get a line 
	back, err = data:receive()
	if not err then fail("shold have gotten 'closed'.")
	elseif err ~= "closed" then fail("got '"..err.."' instead of 'closed'.")
	elseif str ~= back then fail("didn't receive what i should 'closed'.")
	else pass("rightfull 'closed' received") end
	reconnect()
	print("testing close while reading block")
	send_command(ECHO_BLOCK, len)
	data:send(str)
	send_command(CLOSE)
	-- try to get a line 
	back, err = data:receive(2*len)
	if not err then fail("shold have gotten 'closed'.")
	elseif err ~= "closed" then fail("got '"..err.."' instead of 'closed'.")
	elseif str ~= back then fail("didn't receive what I should.")
	else pass("rightfull 'closed' received") end
end

-----------------------------------------------------------------------------
-- Tests binary line transmission
-- Input
--   len: length of line to be tested
-----------------------------------------------------------------------------
function test_rawline(len)
	local str, str10, back, err
	reconnect()
	send_command(ECHO_LINE)
	str = strrep(strchar(47), mod(len, 10))
	str10 = strrep(strchar(120,21,77,4,5,0,7,36,44,100), floor(len/10))
	str = str .. str10
	write("testing ", len, " byte(s) line\n")
	err = data:send(str, "\n")
	if err then fail(err) end
	back, err = data:receive()
	if err then fail(err) end
	if back == str then pass("lines match")
	else fail("lines don't match") end
end

-----------------------------------------------------------------------------
-- Tests block transmission
-- Input
--   len: length of block to be tested
-----------------------------------------------------------------------------
function test_block(len)
	local half = floor(len/2)
	local s1, s2, back, err
	reconnect()
	send_command(ECHO_BLOCK, len)
	write("testing ", len, " byte(s) block\n")
	s1 = strrep("x", half)
	err = data:send(s1)
	if err then fail(err) end
	sleep(1)
	s2 = strrep("y", len-half)
	err = data:send(s2)
	if err then fail(err) end
	back, err = data:receive(len)
	if err then fail(err) end
	if back == s1..s2 then pass("blocks match")
	else fail("blocks don't match") end
end

-----------------------------------------------------------------------------
-- Tests if return-timeout was respected 
--   delta: time elapsed during transfer
--   t: timeout value
--   err: error code returned by I/O operation
-----------------------------------------------------------------------------
function returntimed_out(delta, t, err)
	if err == "timeout" then
		if delta + 0.1 >= t then
			pass("got right timeout")
			return 1
		else
			fail("shouldn't have gotten timeout")
		end
	elseif delta > t then
		fail("should have gotten timeout")
	end
end

-----------------------------------------------------------------------------
-- Tests if return-timeout was respected 
--   delta: time elapsed during transfer
--   t: timeout value
--   err: error code returned by I/O operation
--   o: operation being executed
-----------------------------------------------------------------------------
function blockedtimed_out(t, s, err, o)
	if err == "timeout" then
		if s >= t then
			pass("got right forced timeout")
			return 1
		else
			pass("got natural cause timeout (may be wrong)")
			return 1
		end
	elseif s > t then
		if o == "send" then
			pass("must have been buffered (may be wrong)")
		else
			fail("should have gotten timeout")
		end
	end
end

-----------------------------------------------------------------------------
-- Tests blocked-timeout conformance
-- Input
--   len: length of block to be tested
--   t: timeout value
--   s: server sleep between transfers
-----------------------------------------------------------------------------
function test_blockedtimeout(len, t, s)
	local str, err, back, total
	reconnect()
	send_command(RECEIVE_BLOCK, len)
	send_command(SLEEP, s)
	send_command(RECEIVE_BLOCK, len)
	write("testing ", len, " bytes, ", t, 
		"s block timeout, ", s, "s sleep\n")
	data:timeout(t)
	str = strrep("a", 2*len)
	err, total = data:send(str)
	if blockedtimed_out(t, s, err, "send") then return end
	if err then fail(err) end
	send_command(SEND_BLOCK)
	send_command(SLEEP, s)
	send_command(SEND_BLOCK)
	back, err = data:receive(2*len)
	if blockedtimed_out(t, s, err, "receive") then return end
	if err then fail(err) end
	if back == str then pass("blocks match")
	else fail("blocks don't match") end
end

-----------------------------------------------------------------------------
-- Tests return-timeout conformance
-- Input
--   len: length of block to be tested
--   t: timeout value
--   s: server sleep between transfers
-----------------------------------------------------------------------------
function test_returntimeout(len, t, s)
	local str, err, back, delta, total
	reconnect()
	send_command(RECEIVE_BLOCK, len)
	send_command(SLEEP, s)
	send_command(RECEIVE_BLOCK, len)
	write("testing ", len, " bytes, ", t, 
		"s return timeout, ", s, "s sleep\n")
	data:timeout(t, "return")
	str = strrep("a", 2*len)
	err, total, delta = data:send(str)
	print("delta: " .. delta)
	if returntimed_out(delta, t, err) then return end
	if err then fail(err) end
	send_command(SEND_BLOCK)
	send_command(SLEEP, s)
	send_command(SEND_BLOCK)
	back, err, delta = data:receive(2*len)
	print("delta: " .. delta)
	if returntimed_out(delta, t, err) then return end
	if err then fail(err) end
	if back == str then pass("blocks match")
	else fail("blocks don't match") end
end

-----------------------------------------------------------------------------
-- Execute all tests
-----------------------------------------------------------------------------
new_test("control connection test")
test_command(EXIT)
test_command(CONNECT)
test_command(CLOSE)
test_command(ECHO_BLOCK, 12234)
test_command(SLEEP, 1111)
test_command(ECHO_LINE)

new_test("connection close test")
test_closed()

new_test("binary string test")
test_rawline(1)
test_rawline(17)
test_rawline(200)
test_rawline(3000)
test_rawline(8000)
test_rawline(40000)

new_test("blocking transfer test")
test_block(1)
test_block(17)
test_block(200)
test_block(3000)
test_block(80000)
test_block(800000)

new_test("non-blocking transfer test")
-- the value is not important, we only want 
-- to test non-blockin I/O anyways
data:timeout(200)
test_block(1)
test_block(17)
test_block(200)
test_block(3000)
test_block(80000)
test_block(800000)
test_block(8000000)

new_test("character string test")
test_asciiline(1)
test_asciiline(17)
test_asciiline(200)
test_asciiline(3000)
test_asciiline(8000)
test_asciiline(40000)

new_test("return timeout test")
test_returntimeout(80, .5, 1)
test_returntimeout(80, 1, 0.5)
test_returntimeout(8000, .5, 0)
test_returntimeout(80000, .5, 0)
test_returntimeout(800000, .5, 0)

new_test("blocked timeout test")
test_blockedtimeout(80, .5, 1)
test_blockedtimeout(80, 1, 1)
test_blockedtimeout(80, 1.5, 1)
test_blockedtimeout(800, 1, 0)
test_blockedtimeout(8000, 1, 0)
test_blockedtimeout(80000, 1, 0)
test_blockedtimeout(800000, 1, 0)

-----------------------------------------------------------------------------
-- Close connection and exit server. We are done.
-----------------------------------------------------------------------------
new_test("the library has passed all tests")
print("client: closing connection with server")
send_command(CLOSE)
send_command(EXIT)
control:close()
print("client: exiting...")
exit()
