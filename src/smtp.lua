-----------------------------------------------------------------------------
-- SMTP client support for the Lua language.
-- LuaSocket toolkit.
-- Author: Diego Nehab
-- Conforming to RFC 2821
-- RCS ID: $Id$
-----------------------------------------------------------------------------
-- make sure LuaSocket is loaded
require("socket")
-- get LuaSocket namespace
local socket = _G[LUASOCKET_LIBNAME] 

require("ltn12")
require("tp")

-- create smtp namespace inside LuaSocket namespace
local smtp = socket.smtp or {}
socket.smtp = smtp
-- make all module globals fall into smtp namespace
setmetatable(smtp, { __index = _G })
setfenv(1, smtp)


-- default server used to send e-mails
SERVER = "localhost"
-- default port
PORT = 25 
-- domain used in HELO command and default sendmail 
-- If we are under a CGI, try to get from environment
DOMAIN = os.getenv("SERVER_NAME") or "localhost"
-- default time zone (means we don't know)
ZONE = "-0000"

-- high level stuffing filter
function stuff()
    return ltn12.filter.cycle(dot, 2)
end

---------------------------------------------------------------------------
-- Low level SMTP API
-----------------------------------------------------------------------------
local metat = { __index = {} }

function metat.__index:greet(domain)
    socket.try(self.tp:check("2.."))
    socket.try(self.tp:command("EHLO", domain or DOMAIN))
    return socket.try(self.tp:check("2.."))
end 

function metat.__index:mail(from)
    socket.try(self.tp:command("MAIL", "FROM:" .. from))
    return socket.try(self.tp:check("2.."))
end 

function metat.__index:rcpt(to)
    socket.try(self.tp:command("RCPT", "TO:" .. to))
    return socket.try(self.tp:check("2.."))
end

function metat.__index:data(src, step)
    socket.try(self.tp:command("DATA"))
    socket.try(self.tp:check("3.."))
    socket.try(self.tp:source(src, step))
    socket.try(self.tp:send("\r\n.\r\n"))
    return socket.try(self.tp:check("2.."))
end

function metat.__index:quit()
    socket.try(self.tp:command("QUIT"))
    return socket.try(self.tp:check("2.."))
end

function metat.__index:close()
    return socket.try(self.tp:close())
end

-- send message or throw an exception
function metat.__index:send(mailt) 
    self:mail(mailt.from)
    if type(mailt.rcpt) == "table" then
        for i,v in ipairs(mailt.rcpt) do
            self:rcpt(v)
        end
    else
        self:rcpt(mailt.rcpt)
    end
    self:data(ltn12.source.chain(mailt.source, stuff()), mailt.step)
end

function open(server, port)
    print(server or SERVER, port or PORT)
    local tp, error = socket.tp.connect(server or SERVER, port or PORT)
    if not tp then return nil, error end
    return setmetatable({tp = tp}, metat)
end

---------------------------------------------------------------------------
-- Multipart message source
-----------------------------------------------------------------------------
-- returns a hopefully unique mime boundary
local seqno = 0
local function newboundary()
    seqno = seqno + 1
    return string.format('%s%05d==%05u', os.date('%d%m%Y%H%M%S'),
        math.random(0, 99999), seqno)
end

-- send_message forward declaration
local send_message

-- yield multipart message body from a multipart message table
local function send_multipart(mesgt)
    local bd = newboundary()
    -- define boundary and finish headers
    coroutine.yield('content-type: multipart/mixed; boundary="' .. 
        bd .. '"\r\n\r\n')
    -- send preamble
    if mesgt.body.preamble then coroutine.yield(mesgt.body.preamble) end
    -- send each part separated by a boundary
    for i, m in ipairs(mesgt.body) do
        coroutine.yield("\r\n--" .. bd .. "\r\n")
        send_message(m)
    end
    -- send last boundary 
    coroutine.yield("\r\n--" .. bd .. "--\r\n\r\n")
    -- send epilogue
    if mesgt.body.epilogue then coroutine.yield(mesgt.body.epilogue) end
end

-- yield message body from a source
local function send_source(mesgt)
    -- set content-type if user didn't override
    if not mesgt.headers or not mesgt.headers["content-type"] then
        coroutine.yield('content-type: text/plain; charset="iso-8859-1"\r\n')
    end
    -- finish headers
    coroutine.yield("\r\n")
    -- send body from source
    while true do 
        local chunk, err = mesgt.body()
        if err then coroutine.yield(nil, err)
        elseif chunk then coroutine.yield(chunk)
        else break end
    end
end

-- yield message body from a string
local function send_string(mesgt)
    -- set content-type if user didn't override
    if not mesgt.headers or not mesgt.headers["content-type"] then
        coroutine.yield('content-type: text/plain; charset="iso-8859-1"\r\n')
    end
    -- finish headers
    coroutine.yield("\r\n")
    -- send body from string
    coroutine.yield(mesgt.body)

end

-- yield the headers one by one
local function send_headers(mesgt)
    if mesgt.headers then
        for i,v in pairs(mesgt.headers) do
            coroutine.yield(i .. ':' .. v .. "\r\n")
        end
    end
end

-- message source
function send_message(mesgt)
    send_headers(mesgt)
    if type(mesgt.body) == "table" then send_multipart(mesgt)
    elseif type(mesgt.body) == "function" then send_source(mesgt)
    else send_string(mesgt) end
end

-- set defaul headers
local function adjust_headers(mesgt)
    mesgt.headers = mesgt.headers or {}
    mesgt.headers["mime-version"] = "1.0" 
    mesgt.headers["date"] = mesgt.headers["date"] or 
        os.date("!%a, %d %b %Y %H:%M:%S ") .. (mesgt.zone or ZONE)
    mesgt.headers["x-mailer"] = mesgt.headers["x-mailer"] or socket.version
end

function message(mesgt)
    adjust_headers(mesgt)
    -- create and return message source
    local co = coroutine.create(function() send_message(mesgt) end)
    return function() return socket.skip(1, coroutine.resume(co)) end
end

---------------------------------------------------------------------------
-- High level SMTP API
-----------------------------------------------------------------------------
send = socket.protect(function(mailt)
    local smtp = socket.try(open(mailt.server, mailt.port))
    smtp:greet(mailt.domain)
    smtp:send(mailt)
    smtp:quit()
    return smtp:close()
end)

return smtp
