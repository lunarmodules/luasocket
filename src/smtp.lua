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

-- default port
PORT = 25 
-- domain used in HELO command and default sendmail 
-- If we are under a CGI, try to get from environment
DOMAIN = os.getenv("SERVER_NAME") or "localhost"
-- default server used to send e-mails
SERVER = "localhost"

function stuff()
    return ltn12.filter.cycle(dot, 2)
end

local function skip(a, b, c)
    return b, c
end

function psend(control, mailt) 
    socket.try(control:command("EHLO", mailt.domain or DOMAIN))
    socket.try(control:check("2.."))
    socket.try(control:command("MAIL", "FROM:" .. mailt.from))
    socket.try(control:check("2.."))
    if type(mailt.rcpt) == "table" then
        for i,v in ipairs(mailt.rcpt) do
            socket.try(control:command("RCPT", "TO:" .. v))
        end
    else
        socket.try(control:command("RCPT", "TO:" .. mailt.rcpt))
    end
    socket.try(control:check("2.."))
    socket.try(control:command("DATA"))
    socket.try(control:check("3.."))
    socket.try(control:source(ltn12.source.chain(mailt.source, stuff())))
    socket.try(control:send("\r\n.\r\n"))
    socket.try(control:check("2.."))
    socket.try(control:command("QUIT"))
    socket.try(control:check("2.."))
end

local seqno = 0
local function newboundary()
    seqno = seqno + 1
    return string.format('%s%05d==%05u', os.date('%d%m%Y%H%M%S'),
        math.random(0, 99999), seqno)
end

local function sendmessage(mesgt)
    -- send headers
    if mesgt.headers then
        for i,v in pairs(mesgt.headers) do
            coroutine.yield(i .. ':' .. v .. "\r\n")
        end
    end
    -- deal with multipart
    if type(mesgt.body) == "table" then
        local bd = newboundary()
        -- define boundary and finish headers
        coroutine.yield('mime-version: 1.0\r\n') 
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
    -- deal with a source 
    elseif type(mesgt.body) == "function" then
        -- finish headers
        coroutine.yield("\r\n")
        while true do 
            local chunk, err = mesgt.body()
            if err then return nil, err
            elseif chunk then coroutine.yield(chunk)
            else break end
        end
    -- deal with a simple string
    else
        -- finish headers
        coroutine.yield("\r\n")
        coroutine.yield(mesgt.body)
    end
end

function message(mesgt)
    local co = coroutine.create(function() sendmessage(mesgt) end)
    return function() return skip(coroutine.resume(co)) end
end

function send(mailt)
    local control, err = socket.tp.connect(mailt.server or SERVER, 
        mailt.port or PORT)
    if not control then return nil, err end
    local status, err = pcall(psend, control, mailt)
    control:close()
    if status then return true
    else return nil, err end
end

return smtp
