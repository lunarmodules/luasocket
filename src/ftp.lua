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

-- require other modules
require("ltn12")
require("url")

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
USER = "ftp"
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
    socket.try(self.tp:command("user", user or USER))
    local code, reply = socket.try(self.tp:check{"2..", 331})
    if code == 331 then
        socket.try(self.tp:command("pass", password or EMAIL))
        socket.try(self.tp:check("2.."))
    end
    return 1
end

function metat.__index:pasv()
    socket.try(self.tp:command("pasv"))
    local code, reply = socket.try(self.tp:check("2.."))
    local pattern = "(%d+)%D(%d+)%D(%d+)%D(%d+)%D(%d+)%D(%d+)"
    local a, b, c, d, p1, p2 = socket.skip(2, string.find(reply, pattern))
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
    socket.try(self.tp:command(sendt.command or "stor", sendt.argument))
    local code, reply = socket.try(self.tp:check{"2..", "1.."})
    if self.portt then data = socket.try(port(self.portt)) end
    local step = sendt.step or ltn12.pump.step
    local checkstep = function(src, snk)
        local readyt = socket.select(readt, nil, 0)
        if readyt[tp] then
            code, reply = self.tp:check("2..")
            if not code then 
                data:close()
                return nil, reply 
            end
        end
        local ret, err = step(src, snk)
        if err then data:close() end
        return ret, err
    end
    local sink = socket.sink("close-when-done", data)
    socket.try(ltn12.pump.all(sendt.source, sink, checkstep))
    if string.find(code, "1..") then socket.try(self.tp:check("2..")) end
    return 1
end

function metat.__index:receive(recvt)
    local data
    socket.try(self.pasvt or self.portt, "need port or pasv first")
    if self.pasvt then data = socket.try(pasv(self.pasvt)) end
    socket.try(self.tp:command(recvt.command or "retr", recvt.argument))
    local code = socket.try(self.tp:check{"1..", "2.."})
    if self.portt then data = socket.try(port(self.portt)) end
    local source = socket.source("until-closed", data)
    local step = recvt.step or ltn12.pump.step
    local checkstep = function(src, snk)
        local ret, err = step(src, snk)
        if err then data:close() end
        return ret, err
    end
    socket.try(ltn12.pump.all(source, recvt.sink, checkstep))
    if string.find(code, "1..") then socket.try(self.tp:check("2..")) end
    return 1
end

function metat.__index:cwd(dir)
    socket.try(self.tp:command("cwd", dir))
    socket.try(self.tp:check(250))
    return 1
end

function metat.__index:type(type)
    socket.try(self.tp:command("type", type))
    socket.try(self.tp:check(200))
    return 1
end

function metat.__index:greet()
    local code = socket.try(self.tp:check{"1..", "2.."})
    if string.find(code, "1..") then socket.try(self.tp:check("2..")) end
    return 1
end

function metat.__index:quit()
    socket.try(self.tp:command("quit"))
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
local function tput(putt)
    local ftp = socket.ftp.open(putt.host, putt.port)
    ftp:greet()
    ftp:login(putt.user, putt.password)
    if putt.type then ftp:type(putt.type) end
    ftp:pasv()
    ftp:send(putt)
    ftp:quit()
    return ftp:close()
end

local default = {
	path = "/",
	scheme = "ftp"
}

local function parse(url)
    local putt = socket.try(socket.url.parse(url, default))
    socket.try(putt.scheme == "ftp", "invalid scheme '" .. putt.scheme .. "'")
    socket.try(putt.host, "invalid host")
    local pat = "^type=(.)$"
    if putt.params then 
        putt.type = socket.skip(2, string.find(putt.params, pat))
        socket.try(putt.type == "a" or putt.type == "i")
    end
    -- skip first backslash in path
    putt.argument = string.sub(putt.path, 2)
    return putt
end

local function sput(url, body)
    local putt = parse(url) 
    putt.source = ltn12.source.string(body)
    return tput(putt)
end

put = socket.protect(function(putt, body)
    if type(putt) == "string" then return sput(putt, body)
    else return tput(putt) end
end)

local function tget(gett)
    local ftp = socket.ftp.open(gett.host, gett.port)
    ftp:greet()
    ftp:login(gett.user, gett.password)
    if gett.type then ftp:type(gett.type) end
    ftp:pasv()
    ftp:receive(gett)
    ftp:quit()
    return ftp:close()
end

local function sget(url, body)
    local gett = parse(url) 
    local t = {}
    gett.sink = ltn12.sink.table(t)
    tget(gett)
    return table.concat(t)
end

get = socket.protect(function(gett)
    if type(gett) == "string" then return sget(gett, body)
    else return tget(gett) end
end)

return ftp
