-----------------------------------------------------------------------------
-- TFTP support for the Lua language
-- LuaSocket toolkit.
-- Author: Diego Nehab
-- Conforming to: RFC 783, LTN7
-- RCS ID: $Id$
-----------------------------------------------------------------------------

local Public, Private = {}, {}
local socket = _G[LUASOCKET_LIBNAME] -- get LuaSocket namespace
socket.tftp = Public  -- create tftp sub namespace

-----------------------------------------------------------------------------
-- Program constants
-----------------------------------------------------------------------------
local char = string.char
local byte = string.byte

Public.PORT = 69
Private.OP_RRQ = 1
Private.OP_WRQ = 2
Private.OP_DATA = 3
Private.OP_ACK = 4
Private.OP_ERROR = 5
Private.OP_INV = {"RRQ", "WRQ", "DATA", "ACK", "ERROR"}

-----------------------------------------------------------------------------
-- Packet creation functions
-----------------------------------------------------------------------------
function Private.RRQ(source, mode)
	return char(0, Private.OP_RRQ) .. source .. char(0) .. mode .. char(0)
end

function Private.WRQ(source, mode)
	return char(0, Private.OP_RRQ) .. source .. char(0) .. mode .. char(0)
end

function Private.ACK(block)
	local low, high
	low = math.mod(block, 256)
	high = (block - low)/256
	return char(0, Private.OP_ACK, high, low) 
end

function Private.get_OP(dgram)
    local op = byte(dgram, 1)*256 + byte(dgram, 2)
    return op
end

-----------------------------------------------------------------------------
-- Packet analysis functions
-----------------------------------------------------------------------------
function Private.split_DATA(dgram)
	local block = byte(dgram, 3)*256 + byte(dgram, 4)
	local data = string.sub(dgram, 5)
	return block, data
end

function Private.get_ERROR(dgram)
	local code = byte(dgram, 3)*256 + byte(dgram, 4)
	local msg
	_,_, msg = string.find(dgram, "(.*)\000", 5)
	return string.format("error code %d: %s", code, msg)
end

-----------------------------------------------------------------------------
-- Downloads and returns a file pointed to by url
-----------------------------------------------------------------------------
function Public.get(url)
    local parsed = socket.url.parse(url, {
        host = "",
        port = Public.PORT,
        path ="/",
        scheme = "tftp"
    })
    if parsed.scheme ~= "tftp" then
        return nil, string.format("unknown scheme '%s'", parsed.scheme)
    end
    local retries, dgram, sent, datahost, dataport, code
    local cat = socket.concat.create()
    local last = 0
	local udp, err = socket.udp()
	if not udp then return nil, err end
    -- convert from name to ip if needed
	parsed.host = socket.toip(parsed.host)
	udp:timeout(1)
    -- first packet gives data host/port to be used for data transfers
    retries = 0
	repeat 
		sent, err = udp:sendto(Private.RRQ(parsed.path, "octet"), 
            parsed.host, parsed.port)
		if err then return nil, err end
		dgram, datahost, dataport = udp:receivefrom()
        retries = retries + 1
	until dgram or datahost ~= "timeout" or retries > 5
	if not dgram then return nil, datahost end
    -- associate socket with data host/port
	udp:setpeername(datahost, dataport)
    -- process all data packets
	while 1 do
        -- decode packet
		code = Private.get_OP(dgram)
		if code == Private.OP_ERROR then 
            return nil, Private.get_ERROR(dgram) 
        end
		if code ~= Private.OP_DATA then 
            return nil, "unhandled opcode " .. code 
        end
        -- get data packet parts
		local block, data = Private.split_DATA(dgram)
        -- if not repeated, write
        if block == last+1 then
		    cat:addstring(data)
            last = block
        end
        -- last packet brings less than 512 bytes of data
		if string.len(data) < 512 then 
            sent, err = udp:send(Private.ACK(block)) 
            return cat:getresult()
        end
        -- get the next packet
        retries = 0
		repeat 
			sent, err = udp:send(Private.ACK(last))
			if err then return err end
			dgram, err = udp:receive()
            retries = retries + 1
		until dgram or err ~= "timeout" or retries > 5
		if not dgram then return err end
	end
end
