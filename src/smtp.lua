-- make sure LuaSocket is loaded
if not LUASOCKET_LIBNAME then error('module requires LuaSocket') end
-- get LuaSocket namespace
local socket = _G[LUASOCKET_LIBNAME] 
if not socket then error('module requires LuaSocket') end
-- create smtp namespace inside LuaSocket namespace
local smtp = {}
socket.smtp = smtp
-- make all module globals fall into smtp namespace
setmetatable(smtp, { __index = _G })
setfenv(1, smtp)

-- default port
PORT = 25 
-- domain used in HELO command and default sendmail 
-- If we are under a CGI, try to get from environment
DOMAIN = os.getenv("SERVER_NAME") or "localhost"
-- default server used to send e-mails
SERVER = "localhost"

-- tries to get a pattern from the server and closes socket on error
local function try_receiving(connection, pattern)
    local data, message = connection:receive(pattern)
    if not data then connection:close() end
    print(data)
    return data, message
end

-- tries to send data to server and closes socket on error
local function try_sending(connection, data)
    local sent, message = connection:send(data)
    if not sent then connection:close() end
    io.write(data)
    return sent, message
end

-- gets server reply
local function get_reply(connection)
    local code, current, separator, _
    local line, message = try_receiving(connection)
    local reply = line
    if message then return nil, message end
    _, _, code, separator = string.find(line, "^(%d%d%d)(.?)")
    if not code then return nil, "invalid server reply" end
    if separator == "-" then -- reply is multiline
        repeat
            line, message = try_receiving(connection)
            if message then return nil, message end
            _,_, current, separator = string.find(line, "^(%d%d%d)(.)")
            if not current or not separator then 
                return nil, "invalid server reply" 
            end
            reply = reply .. "\n" .. line
        -- reply ends with same code
        until code == current and separator == " " 
    end
    return code, reply
end

-- metatable for server connection object
local metatable = { __index = {} }

-- switch handler for execute function
local switch = {}

-- execute the "check" instruction
function switch.check(connection, instruction)
    local code, reply = get_reply(connection)
    if not code then return nil, reply end
    if type(instruction.check) == "function" then
        return instruction.check(code, reply)
    else
        if string.find(code, instruction.check) then return code, reply
        else return nil, reply end
    end
end

-- stub for invalid instructions 
function switch.invalid(connection, instruction)
    return nil, "invalid instruction"
end

-- execute the "command" instruction
function switch.command(connection, instruction)
    local line
    if instruction.argument then
        line = instruction.command .. " " .. instruction.argument .. "\r\n"
    else line = instruction.command .. "\r\n" end
    return try_sending(connection, line)
end

function switch.raw(connection, instruction)
    if type(instruction.raw) == "function" then
        local f = instruction.raw
        while true do 
            local chunk, new_f = f()
            if not chunk then return nil, new_f end
            if chunk == "" then return true end
            f = new_f or f
            local code, message = try_sending(connection, chunk)
            if not code then return nil, message end
        end
    else return try_sending(connection, instruction.raw) end
end

-- finds out what instruction are we dealing with
local function instruction_type(instruction) 
    if type(instruction) ~= "table" then return "invalid" end
    if instruction.command then return "command" end
    if instruction.check then return "check" end
    if instruction.raw then return "raw" end
    return "invalid"
end

-- execute a list of instructions
function metatable.__index:execute(instructions)
    if type(instructions) ~= "table" then error("instruction expected", 1) end
    if not instructions[1] then instructions = { instructions } end
    local code, message
    for _, instruction in ipairs(instructions) do
        local type = instruction_type(instruction)
        code, message = switch[type](self.connection, instruction)
        if not code then break end
    end
    return code, message
end

-- closes the underlying connection
function metatable.__index:close()
    self.connection:close()
end

-- connect with server and return a smtp connection object
function connect(host)
    local connection, message = socket.connect(host, PORT)
    if not connection then return nil, message end
    return setmetatable({ connection = connection }, metatable)
end

-- simple test drive 

--[[
c, m = connect("localhost")
assert(c, m)
assert(c:execute {check = "2.." })
assert(c:execute {{command = "EHLO", argument = "localhost"}, {check = "2.."}})
assert(c:execute {command = "MAIL", argument = "FROM:<diego@princeton.edu>"})
assert(c:execute {check = "2.."})
assert(c:execute {command = "RCPT", argument = "TO:<diego@cs.princeton.edu>"})
assert(c:execute {check = function (code) return code == "250" end})
assert(c:execute {{command = "DATA"}, {check = "3.."}})
assert(c:execute {{raw = "This is the message\r\n.\r\n"}, {check = "2.."}})
assert(c:execute {{command = "QUIT"}, {check = "2.."}})
c:close()
]]

return smtp
