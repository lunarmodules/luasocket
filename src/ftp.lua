-----------------------------------------------------------------------------
-- FTP support for the Lua language
-- LuaSocket toolkit.
-- Author: Diego Nehab
-- Conforming to: RFC 959, LTN7
-- RCS ID: $Id$
-----------------------------------------------------------------------------
-- make sure LuaSocket is loaded
if not LUASOCKET_LIBNAME then error('module requires LuaSocket') end
-- get LuaSocket namespace
local socket = _G[LUASOCKET_LIBNAME] 
if not socket then error('module requires LuaSocket') end
-- create namespace inside LuaSocket namespace
socket.ftp  = socket.ftp or {}
-- make all module globals fall into namespace
setmetatable(socket.ftp, { __index = _G })
setfenv(1, socket.ftp)

-----------------------------------------------------------------------------
-- Program constants
-----------------------------------------------------------------------------
-- timeout in seconds before the program gives up on a connection
TIMEOUT = 60
-- default port for ftp service
PORT = 21
-- this is the default anonymous password. used when no password is
-- provided in url. should be changed to your e-mail.
EMAIL = "anonymous@anonymous.org"
-- block size used in transfers
BLOCKSIZE = 2048

-----------------------------------------------------------------------------
-- Low level FTP API
-----------------------------------------------------------------------------
local metat = { __index = {} }

function open(server, port)
    local tp = socket.try(socket.tp.connect(server, port or PORT))
    return setmetatable({tp = tp}, metat)
end

local function port(portt)
    return portt.server:accept()
end

local function pasv(pasvt)
    return socket.connect(pasvt.ip, pasvt.port)
end

function metat.__index:login(user, password)
    socket.try(self.tp:command("USER", user))
    local code, reply = socket.try(self.tp:check{"2..", 331})
    if code == 331 then
        socket.try(password, reply)
        socket.try(self.tp:command("PASS", password))
        socket.try(self.tp:check("2.."))
    end
    return 1
end

function metat.__index:pasv()
    socket.try(self.tp:command("PASV"))
    local code, reply = socket.try(self.tp:check("2.."))
    local _, _, a, b, c, d, p1, p2 = 
        string.find(reply, "(%d+)%D(%d+)%D(%d+)%D(%d+)%D(%d+)%D(%d+)")
    socket.try(a and b and c and d and p1 and p2, reply)
    self.pasvt = { 
        ip = string.format("%d.%d.%d.%d", a, b, c, d), 
        port = p1*256 + p2
    }
    if self.portt then 
        self.portt.server:close()
        self.portt = nil
    end
    return self.pasvt.ip, self.pasvt.port 
end

function metat.__index:port(ip, port)
    self.pasvt = nil
    local server
    if not ip then 
        ip, port = socket.try(self.tp:getcontrol():getsockname())
        server = socket.try(socket.bind(ip, 0))
        ip, port = socket.try(server:getsockname())
        socket.try(server:settimeout(TIMEOUT))
    end
    local pl = math.mod(port, 256)
    local ph = (port - pl)/256
    local arg = string.gsub(string.format("%s,%d,%d", ip, ph, pl), "%.", ",")
    socket.try(self.tp:command("port", arg))
    socket.try(self.tp:check("2.."))
    self.portt = server and {ip = ip, port = port, server = server}
    return 1
end

function metat.__index:send(sendt)
    local data
    socket.try(self.pasvt or self.portt, "need port or pasv first")
    if self.pasvt then data = socket.try(pasv(self.pasvt)) end
    socket.try(self.tp:command(sendt.command, sendt.argument))
    if self.portt then data = socket.try(port(self.portt)) end
    local step = sendt.step or ltn12.pump.step
    local code, reply
    local checkstep = function(src, snk)
        local readyt = socket.select(readt, nil, 0)
        if readyt[tp] then
            code, reply = self.tp:check{"2..", "1.."}
            if not code then 
                data:close()
                return nil, reply 
            end
        end
        local ret, err = step(src, snk)
        if err then data:close() end
        return ret, err
    end
    local sink = socket.sink("close-when-empty", data)
    socket.try(ltn12.pump.all(sendt.source, sink, checkstep))
    if not code then code = socket.try(self.tp:check{"1..", "2.."}) end
    if string.find(code, "1..") then socket.try(self.tp:check("2..")) end
    return 1
end

function metat.__index:receive(recvt)
    local data
    socket.try(self.pasvt or self.portt, "need port or pasv first")
    if self.pasvt then data = socket.try(pasv(self.pasvt)) end
    socket.try(self.tp:command(recvt.command, recvt.argument))
    if self.portt then data = socket.try(port(self.portt)) end
    local source = socket.source("until-closed", data)
    local step = recvt.step or ltn12.pump.step
    local checkstep = function(src, snk)
        local ret, err = step(src, snk)
        if err then data:close() end
        return ret, err
    end
    socket.try(ltn12.pump.all(source, recvt.sink, checkstep))
    local code = socket.try(self.tp:check{"1..", "2.."})
    if string.find(code, "1..") then socket.try(self.tp:check("2..")) end
    return 1
end

function metat.__index:cwd(dir)
    socket.try(self.tp:command("CWD", dir))
    socket.try(self.tp:check(250))
    return 1
end

function metat.__index:type(type)
    socket.try(self.tp:command("TYPE", type))
    socket.try(self.tp:check(200))
    return 1
end

function metat.__index:greet()
    local code = socket.try(self.tp:check{"1..", "2.."})
    if string.find(code, "1..") then socket.try(self.tp:check("2..")) end
    return 1
end

function metat.__index:quit()
    socket.try(self.tp:command("QUIT"))
    socket.try(self.tp:check("2.."))
    return 1
end

function metat.__index:close()
    socket.try(self.tp:close())
    return 1
end

-----------------------------------------------------------------------------
-- High level FTP API
-----------------------------------------------------------------------------

function put(putt)
end

function get(gett)
end

return ftp
