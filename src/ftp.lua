-----------------------------------------------------------------------------
-- FTP support for the Lua language
-- LuaSocket toolkit.
-- Author: Diego Nehab
-- RCS ID: $Id$
-----------------------------------------------------------------------------

-----------------------------------------------------------------------------
-- Load required modules
-----------------------------------------------------------------------------
local socket = require("socket")
local ltn12 = require("ltn12")
local url = require("url")
local tp = require("tp")

-----------------------------------------------------------------------------
-- Setup namespace
-----------------------------------------------------------------------------
_LOADED["ftp"] = getfenv(1)

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
PASSWORD = "anonymous@anonymous.org"

-----------------------------------------------------------------------------
-- Low level FTP API
-----------------------------------------------------------------------------
local metat = { __index = {} }

function open(server, port)
    local tp = socket.try(tp.connect(server, port or PORT, TIMEOUT))
    return setmetatable({tp = tp}, metat)
end

local function port(portt)
    return portt.server:accept()
end

local function pasv(pasvt)
    local data = socket.try(socket.tcp())
    socket.try(data:settimeout(TIMEOUT))
    socket.try(data:connect(pasvt.ip, pasvt.port))
    return data
end

function metat.__index:login(user, password)
    socket.try(self.tp:command("user", user or USER))
    local code, reply = socket.try(self.tp:check{"2..", 331})
    if code == 331 then
        socket.try(self.tp:command("pass", password or PASSWORD))
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
    local argument = sendt.argument or string.gsub(sendt.path, "^/", "")
    if argument == "" then argument = nil end
    local command =  sendt.command or "stor"
    socket.try(self.tp:command(command, argument))
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
    local argument = recvt.argument or string.gsub(recvt.path, "^/", "")
    if argument == "" then argument = nil end
    local command =  recvt.command or "retr"
    socket.try(self.tp:command(command, argument))
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
    local con = ftp.open(putt.host, putt.port)
    con:greet()
    con:login(putt.user, putt.password)
    if putt.type then con:type(putt.type) end
    con:pasv()
    con:send(putt)
    con:quit()
    return con:close()
end

local default = {
	path = "/",
	scheme = "ftp"
}

local function parse(u)
    local t = socket.try(url.parse(u, default))
    socket.try(t.scheme == "ftp", "invalid scheme '" .. t.scheme .. "'")
    socket.try(t.host, "invalid host")
    local pat = "^type=(.)$"
    if t.params then 
        t.type = socket.skip(2, string.find(t.params, pat))
        socket.try(t.type == "a" or t.type == "i",
            "invalid type '" .. t.type .. "'")
    end
    return t
end

local function sput(u, body)
    local putt = parse(u) 
    putt.source = ltn12.source.string(body)
    return tput(putt)
end

put = socket.protect(function(putt, body)
    if type(putt) == "string" then return sput(putt, body)
    else return tput(putt) end
end)

local function tget(gett)
    local con = ftp.open(gett.host, gett.port)
    con:greet()
    con:login(gett.user, gett.password)
    if gett.type then con:type(gett.type) end
    con:pasv()
    con:receive(gett)
    con:quit()
    return con:close()
end

local function sget(u)
    local gett = parse(u) 
    local t = {}
    gett.sink = ltn12.sink.table(t)
    tget(gett)
    return table.concat(t)
end

get = socket.protect(function(gett)
    if type(gett) == "string" then return sget(gett)
    else return tget(gett) end
end)
