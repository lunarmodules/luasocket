-- make sure LuaSocket is loaded
if not LUASOCKET_LIBNAME then error('module requires LuaSocket') end
-- get LuaSocket namespace
local socket = _G[LUASOCKET_LIBNAME] 
if not socket then error('module requires LuaSocket') end
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

function stuff()
    return ltn12.filter.cycle(dot, 2)
end

local function shift(a, b, c)
    return b, c
end

-- send message or throw an exception
function psend(control, mailt) 
    socket.try(control:check("2.."))
    socket.try(control:command("EHLO", mailt.domain or DOMAIN))
    socket.try(control:check("2.."))
    socket.try(control:command("MAIL", "FROM:" .. mailt.from))
    socket.try(control:check("2.."))
    if type(mailt.rcpt) == "table" then
        for i,v in ipairs(mailt.rcpt) do
            socket.try(control:command("RCPT", "TO:" .. v))
            socket.try(control:check("2.."))
        end
    else
        socket.try(control:command("RCPT", "TO:" .. mailt.rcpt))
        socket.try(control:check("2.."))
    end
    socket.try(control:command("DATA"))
    socket.try(control:check("3.."))
    socket.try(control:source(ltn12.source.chain(mailt.source, stuff())))
    socket.try(control:send("\r\n.\r\n"))
    socket.try(control:check("2.."))
    socket.try(control:command("QUIT"))
    socket.try(control:check("2.."))
end

-- returns a hopefully unique mime boundary
local seqno = 0
local function newboundary()
    seqno = seqno + 1
    return string.format('%s%05d==%05u', os.date('%d%m%Y%H%M%S'),
        math.random(0, 99999), seqno)
end

-- sendmessage forward declaration
local sendmessage

-- yield multipart message body from a multipart message table
local function sendmultipart(mesgt)
    local bd = newboundary()
    -- define boundary and finish headers
    coroutine.yield('content-type: multipart/mixed; boundary="' .. 
        bd .. '"\r\n\r\n')
    -- send preamble
    if mesgt.body.preamble then coroutine.yield(mesgt.body.preamble) end
    -- send each part separated by a boundary
    for i, m in ipairs(mesgt.body) do
        coroutine.yield("\r\n--" .. bd .. "\r\n")
        sendmessage(m)
    end
    -- send last boundary 
    coroutine.yield("\r\n--" .. bd .. "--\r\n\r\n")
    -- send epilogue
    if mesgt.body.epilogue then coroutine.yield(mesgt.body.epilogue) end
end

-- yield message body from a source
local function sendsource(mesgt)
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
local function sendstring(mesgt)
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
local function sendheaders(mesgt)
    if mesgt.headers then
        for i,v in pairs(mesgt.headers) do
            coroutine.yield(i .. ':' .. v .. "\r\n")
        end
    end
end

-- message source
function sendmessage(mesgt)
    sendheaders(mesgt)
    if type(mesgt.body) == "table" then sendmultipart(mesgt)
    elseif type(mesgt.body) == "function" then sendsource(mesgt)
    else sendstring(mesgt) end
end

-- set defaul headers
local function adjustheaders(mesgt)
    mesgt.headers = mesgt.headers or {}
    mesgt.headers["mime-version"] = "1.0" 
    mesgt.headers["date"] = mesgt.headers["date"] or 
        os.date("!%a, %d %b %Y %H:%M:%S ") .. (mesgt.zone or ZONE)
    mesgt.headers["x-mailer"] = mesgt.headers["x-mailer"] or socket.version
end

function message(mesgt)
    adjustheaders(mesgt)
    -- create and return message source
    local co = coroutine.create(function() sendmessage(mesgt) end)
    return function() return shift(coroutine.resume(co)) end
end

function send(mailt)
    local c, e = socket.tp.connect(mailt.server or SERVER, mailt.port or PORT)
    if not c then return nil, e end
    local s, e = pcall(psend, c, mailt)
    c:close()
    if s then return true
    else return nil, e end
end

return smtp
