local sent = {}

local from = "luasock@tecgraf.puc-rio.br"
local server = "mail.tecgraf.puc-rio.br"
local rcpt = "luasock@tecgraf.puc-rio.br"

local name = "/var/spool/mail/luasock"

local t = _time()
local err

dofile("parsembox.lua")
local parse = parse
dofile("noglobals.lua")

local total = function()
	local t = 0
	for i = 1, getn(%sent) do
		t = t + %sent[i].count
	end
	return t
end

local similar = function(s1, s2)
    return strlower(gsub(s1, "%s", "")) == strlower(gsub(s2, "%s", ""))
end

local readfile = function(name)
    local f = readfrom(name)
    if not f then return nil end
    local s = read("*a")
    readfrom()
    return s
end

local capture = function(cmd)
    readfrom("| " .. cmd)
    local s = read("*a")
    readfrom()
    return s
end

local fail = function(s)
    s = s or "failed!"
    print(s)
    exit()
end

local empty = function()
    local f = openfile(%name, "w")
    closefile(f)
end

local get = function()
	return %readfile(%name)
end

local list = function()
    return %capture("ls -l " .. %name)
end

local check_headers = function(sent, got)
    sent = sent or {}
    got = got or {}
    for i,v in sent do
        if not %similar(v, got[i]) then %fail("header " .. v .. "failed!") end
    end
end

local check_body = function(sent, got)
    sent = sent or ""
    got = got or ""
    if not %similar(sent, got) then %fail("bodies differ!") end
end

local check = function(sent, m)
	write("checking ", m.headers.title, ": ")
	for i = 1, getn(sent) do
		local s = sent[i]
		if s.title == m.headers.title and s.count > 0 then
			%check_headers(s.headers, m.headers)
			%check_body(s.body, m.body)
			s.count = s.count - 1
			print("ok")
			return
		end
	end
	%fail("not found")
end

local insert = function(sent, message)
	if type(message.rcpt) == "table" then
		message.count = getn(message.rcpt)
	else message.count = 1 end
	message.headers = message.headers or {}
	message.headers.title = message.title
	tinsert(sent, message)
end

local mark = function()
	local time = _time()
    return { time = time }
end

local wait = function(sentinel, n)
    local to
	write("waiting for ", n, " messages: ")
    while 1 do
		local mbox = %parse.mbox(%get())
		if n == getn(mbox) then break end
        if _time() - sentinel.time > 50 then 
            to = 1 
            break
        end
        _sleep(1)
        write(".")
        flush(_STDOUT)
    end
	if to then %fail("timeout")
	else print("ok") end
end

local stuffed_body = [[
This message body needs to be
stuffed because it has a dot
.
by itself on a line. 
Otherwise the mailer would
think that the dot
.
is the end of the message
and the remaining will cause
a lot of trouble.
]]

insert(sent, {
    from = from,
    rcpt = {
		"luasock2@tecgraf.puc-rio.br",
		"luasock",
		"luasock1"
	},
	body = "multiple rcpt body",
	title = "multiple rcpt",
})

insert(sent, {
    from = from,
    rcpt = {
		"luasock2@tecgraf.puc-rio.br",
		"luasock",
		"luasock1"
	},
    headers = {
        header1 = "header 1",
        header2 = "header 2",
        header3 = "header 3",
        header4 = "header 4",
        header5 = "header 5",
        header6 = "header 6",
    },
    body = stuffed_body,
    title = "complex message",
})

insert(sent, {
    from = from,
    rcpt = rcpt,
    server = server,
    body = "simple message body",
    title = "simple message"
})

insert(sent, {
    from = from,
    rcpt = rcpt,
    server = server,
    body = stuffed_body,
    title = "stuffed message body"
})

insert(sent, {
    from = from,
    rcpt = rcpt,
    headers = {
        header1 = "header 1",
        header2 = "header 2",
        header3 = "header 3",
        header4 = "header 4",
        header5 = "header 5",
        header6 = "header 6",
    },
    title = "multiple headers"
})

insert(sent, {
    from = from,
    rcpt = rcpt,
    title = "minimum message"
})

write("testing host not found: ")
local c, e = connect("wrong.host", 25)
local err = SMTP.mail{
	from = from,
	rcpt = rcpt,
	server = "wrong.host"
}
if e ~= err then fail("wrong error message")
else print("ok") end

write("testing invalid from: ")
local err = SMTP.mail{
	from = ' " " (( _ * ', 
	rcpt = rcpt,
}
if not err then fail("wrong error message")
else print(err) end

write("testing no rcpt: ")
local err = SMTP.mail{
	from = from, 
}
if not err then fail("wrong error message")
else print(err) end

write("clearing mailbox: ")
empty()
print("ok")

write("sending messages: ")
for i = 1, getn(sent) do
    err = SMTP.mail(sent[i])
    if err then fail(err) end
    write("+")
    flush(_STDOUT)
end
print("ok")

wait(mark(), total())

write("parsing mailbox: ")
local mbox = parse.mbox(get())
print(getn(mbox) .. " messages found!")

for i = 1, getn(mbox) do
	check(sent, mbox[i])
end


print("passed all tests")
print(format("done in %.2fs", _time() - t))
