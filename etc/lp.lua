-- make sure LuaSocket is loaded
local socket = require("socket")
local ltn12 = require("ltn12")
local lp = {}
--socket.lp = lp
-- make all module globals fall into lp namespace
setmetatable(lp, { __index = _G })
setfenv(1, lp)

-- default port
PORT = 515
SERVER = os.getenv("SERVER_NAME") or os.getenv("COMPUTERNAME") or "localhost"
PRINTER = os.getenv("PRINTER") or "printer"


--[[
RFC 1179
5.3 03 - Send queue state (short)

      +----+-------+----+------+----+
      | 03 | Queue | SP | List | LF |
      +----+-------+----+------+----+
      Command code - 3
      Operand 1 - Printer queue name
      Other operands - User names or job numbers

   If the user names or job numbers or both are supplied then only those
   jobs for those users or with those numbers will be sent.

   The response is an ASCII stream which describes the printer queue.
   The stream continues until the connection closes.  Ends of lines are
   indicated with ASCII LF control characters.  The lines may also
   contain ASCII HT control characters.

5.4 04 - Send queue state (long)

      +----+-------+----+------+----+
      | 04 | Queue | SP | List | LF |
      +----+-------+----+------+----+
      Command code - 4
      Operand 1 - Printer queue name
      Other operands - User names or job numbers

   If the user names or job numbers or both are supplied then only those
   jobs for those users or with those numbers will be sent.

   The response is an ASCII stream which describes the printer queue.
   The stream continues until the connection closes.  Ends of lines are
   indicated with ASCII LF control characters.  The lines may also
   contain ASCII HT control characters.
]]


-- gets server acknowledement
local function recv_ack(connection)
  local code, current, separator, _
  local ack = socket.try(connection:receive(1))
  if string.char(0) ~= ack then
    connection:close(); error"failed to receive server acknowledement"
  end
end

-- sends client acknowledement
local function send_ack(connection)
  local sent = socket.try(connection:send(string.char(0)))
  if not sent or sent ~= 1 then
    connection:close();
    error"failed to send acknowledgement"
  end
end

-- sends queue request
-- 5.2 02 - Receive a printer job
--
--       +----+-------+----+
--       | 02 | Queue | LF |
--       +----+-------+----+
--       Command code - 2
--       Operand - Printer queue name
--
--    Receiving a job is controlled by a second level of commands.  The
--    daemon is given commands by sending them over the same connection.
--    The commands are described in the next section (6).
--
--    After this command is sent, the client must read an acknowledgement
--    octet from the daemon.  A positive acknowledgement is an octet of
--    zero bits.  A negative acknowledgement is an octet of any other
--    pattern.
local function send_queue(connection,queue)
  if not queue then queue=PRINTER end
  local str = string.format("\2%s\10",queue)
  local sent = socket.try(connection:send(str))
  if not sent or sent ~= string.len(str) then
    error "failed to send print request"
  end
  recv_ack(connection)
end

-- sends control file
-- 6.2 02 - Receive control file
--
--       +----+-------+----+------+----+
--       | 02 | Count | SP | Name | LF |
--       +----+-------+----+------+----+
--       Command code - 2
--       Operand 1 - Number of bytes in control file
--       Operand 2 - Name of control file
--
--    The control file must be an ASCII stream with the ends of lines
--    indicated by ASCII LF.  The total number of bytes in the stream is
--    sent as the first operand.  The name of the control file is sent as
--    the second.  It should start with ASCII "cfA", followed by a three
--    digit job number, followed by the host name which has constructed the
--    control file.  Acknowledgement processing must occur as usual after
--    the command is sent.
--
--    The next "Operand 1" octets over the same TCP connection are the
--    intended contents of the control file.  Once all of the contents have
--    been delivered, an octet of zero bits is sent as an indication that
--    the file being sent is complete.  A second level of acknowledgement
--    processing must occur at this point.

-- sends data file
-- 6.3 03 - Receive data file
--
--       +----+-------+----+------+----+
--       | 03 | Count | SP | Name | LF |
--       +----+-------+----+------+----+
--       Command code - 3
--       Operand 1 - Number of bytes in data file
--       Operand 2 - Name of data file
--
--    The data file may contain any 8 bit values at all.  The total number
--    of bytes in the stream may be sent as the first operand, otherwise
--    the field should be cleared to 0.  The name of the data file should
--    start with ASCII "dfA".  This should be followed by a three digit job
--    number.  The job number should be followed by the host name which has
--    constructed the data file.  Interpretation of the contents of the
--    data file is determined by the contents of the corresponding control
--    file.  If a data file length has been specified, the next "Operand 1"
--    octets over the same TCP connection are the intended contents of the
--    data file.  In this case, once all of the contents have been
--    delivered, an octet of zero bits is sent as an indication that the
--    file being sent is complete.  A second level of acknowledgement
--    processing must occur at this point.


local function send_hdr(connection,control)
  local sent = socket.try(connection:send(control))
  if not sent or sent < 1 then
    error "failed to send file"
  end
  recv_ack(connection)
end


local function send_control(connection,control)
  local sent = socket.try(connection:send(control))
  if not sent or sent < 1 then
    error "failed to send file"
  end
  send_ack(connection)
end

local function send_data(connection,fh,size)
--  local sink = socket.sink("keep-open", connection)
--  ltn12.pump.all(source, sink)
  local buf, st, message
  st = true
  while size > 0 do
    buf,message = fh:read(8192)
    if buf then
      st = socket.try(connection:send(buf))
      size = size - st
    else
      if size ~= 0 then
        connection:close()
        return nil, "file size mismatch"
      end
    end
  end
  send_ack(connection)
  recv_ack(connection)
  return size,nil
end


--[[

local control_dflt = {
  "H"..string.sub(socket.hostname,1,31).."\10",        -- host
  "C"..string.sub(socket.hostname,1,31).."\10",        -- class
  "J"..string.sub(filename,1,99).."\10",               -- jobname
  "L"..string.sub(user,1,31).."\10",                   -- print banner page
  "I"..tonumber(indent).."\10",                        -- indent column count ('f' only)
  "M"..string.sub(mail,1,128).."\10",                  -- mail when printed user@host
  "N"..string.sub(filename,1,131).."\10",              -- name of source file
  "P"..string.sub(user,1,31).."\10",                   -- user name
  "T"..string.sub(title,1,79).."\10",                  -- title for banner ('p' only)
  "W"..tonumber(width or 132).."\10",                  -- width of print f,l,p only

  "f"..file.."\10",                                    -- formatted print (remove control chars)
  "l"..file.."\10",                                    -- print
  "o"..file.."\10",                                    -- postscript
  "p"..file.."\10",                                    -- pr format - requires T, L
  "r"..file.."\10",                                    -- fortran format
  "U"..file.."\10",                                    -- Unlink (data file only)
}

]]

-- generate a varying job number
local function getjobno(connection)
--  print(math.mod(socket.time() * 1000, port)) -- ok for windows
--  print(os.time() / port,math.random(0,999))
  return  math.random(0,999)
end

local function getcon(localhost,option)
  local skt, st, message
  local localport = 721
  if not option then
    error('no options',0)
  end
  if option.localbind then
    repeat
  -- bind to a local port (if we can)
      skt = socket.try(socket.tcp())
      skt:settimeout(30)

      st, message = skt:bind(localhost,localport,-1);
  --    print("bind",st,message)
      if st then
        st,message = skt:connect(option.host or SERVER, option.port or PORT)
  --      print("connect",st,message)
      end
  --    print(st,localport,message)
      if not st then
         localport = localport + 1
         skt:close()
      end
    until st or localport > 731 or (not st and message ~= "local address already in use")
    if st then return skt end
  end
  return socket.try(socket.connect(option.host or SERVER, option.port or PORT))
end

local format_codes = {
  binary = 'l',
  text = 'f',
  ps = 'o',
  pr = 'p',
  fortran = 'r',
  l = 'l',
  r = 'r',
  o = 'o',
  p = 'p',
  f = 'f'
}

lp.send = socket.protect(function(file, option)
  if not file  then error "invalid file name" end
  if not option or type(option) ~= "table" then error "invalid options" end
  local fh = socket.try(io.open(file,"rb"))
  -- get total size
  local datafile_size = fh:seek("end")
  -- go back to start of file
  fh:seek("set")
  math.randomseed(socket.time() * 1000)
  local localhost = socket.dns.gethostname() or os.getenv("COMPUTERNAME") or "localhost"

--  local connection, message = skt:connect(option.host or SERVER, option.port or PORT)

  local connection = getcon(localhost,option)

-- format the control file
  local jobno = getjobno(connection)
  local localip = socket.dns.toip(localhost)
  localhost = string.sub(localhost,1,31)

  local user = string.sub(option.user or os.getenv("LPRUSER") or os.getenv("USERNAME")
           or os.getenv("USER") or "anonymous",1,31)

  local lpfile = string.format("dfA%3.3d%-s", jobno, localhost);

  local fmt = format_codes[option.format] or 'l'

  local class = string.sub(option.class or localip or localhost,1,31)

  local _,_,ctlfn = string.find(file,".*[%/%\\](.*)")
  ctlfn = string.sub(ctlfn  or file,1,131)

	local cfile =
	  string.format("H%-s\nC%-s\nJ%-s\nP%-s\n%.1s%-s\nU%-s\nN%-s\n",
	  localhost,
    class,
	  option.job or ctlfn,
    user,
    fmt, lpfile,
    lpfile,
    ctlfn); -- mandatory part of ctl file
  if (option.banner) then cfile = cfile .. 'L'..user..'\10' end
  if (option.indent) then cfile = cfile .. 'I'..tonumber(option.indent)..'\10' end
  if (option.mail) then cfile = cfile .. 'M'..string.sub((option.mail),1,128)..'\10' end
  if (fmt == 'p' and option.title) then cfile = cfile .. 'T'..string.sub((option.title),1,79)..'\10' end
  if ((fmt == 'p' or fmt == 'l' or fmt == 'f') and option.width) then
    cfile = cfile .. 'W'..tonumber(option,width)..'\10'
  end

  connection:settimeout(option.timeout or 65)

-- send the queue header
  send_queue(connection,option.queue)

-- send the control file header
  local cfilecmd = string.format("\2%d cfA%3.3d%-s\n",string.len(cfile), jobno, localhost);
  send_hdr(connection,cfilecmd)

-- send the control file
  send_control(connection,cfile)

-- send the data file header
  local dfilecmd = string.format("\3%d dfA%3.3d%-s\n",datafile_size, jobno, localhost);
  send_hdr(connection,dfilecmd)

-- send the data file
  send_data(connection,fh,datafile_size)
  fh:close()
  connection:close();
  return datafile_size
end)


--socket.lpq({host=,queue=printer|'*', format='l'|'s', list=})
lp.query = socket.protect(function(p)
  if not p then p={} end
  local localhost = socket.dns.gethostname() or os.getenv("COMPUTERNAME") or "localhost"
  local connection = getcon(localhost,p)
  local fmt,data
  if string.sub(p.format or 's',1,1) == 's' then fmt = 3 else fmt = 4 end
  local sent = socket.try(connection:send(string.format("%c%s %s\n", fmt, p.queue or "*", p.list or "")))
  local data = socket.try(connection:receive("*a"))
  io.write(data)
  connection:close()
  return tostring(string.len(data))
end)

--for k,v in arg do print(k,v) end
local function usage()
  print('\nUsage: lp filename [keyword=val...]\n')
  print('Valid keywords are :')
  print(
     '  host=remote host or IP address (default "localhost")\n' ..
     '  queue=remote queue or printer name (default "printer")\n' ..
     '  port=remote port number (default 515)\n' ..
     '  user=sending user name\n' ..
     '  format=["binary" | "text" | "ps" | "pr" | "fortran"] (default "binary")\n' ..
     '  banner=true|false\n' ..
     '  indent=number of columns to indent\n' ..
     '  mail=email of address to notify when print is complete\n' ..
     '  title=title to use for "pr" format\n' ..
     '  width=width for "text" or "pr" formats\n' ..
     '  class=\n' ..
     '  job=\n' ..
     '  name=\n' ..
     '  localbind=true|false\n'
     )
  return nil
end

if not arg or not arg[1] then
  return usage()
end

do
    local s="opt = {"
    for i = 2 , table.getn(arg), 1 do
      s = s .. string.gsub(arg[i],"[%s%c%p]*([%w]*)=([\"]?[%w%s_!@#$%%^&*()<>:;]+[\"]\?\.?)","%1%=\"%2\",\n")
    end
    s = s .. "};\n"
    assert(loadstring(s))();
    if not arg[2] then
      return usage()
    end
    if arg[1] ~= "query" then
        r,e=lp.send(arg[1],opt)
        io.stderr:write(tostring(r or e),'\n')
    else
        r,e=lp.query(opt)
        io.stderr:write(tostring(r or e),'\n')
    end
end

-- trivial tests
--lua lp.lua lp.lua queue=default host=localhost
--lua lp.lua lp.lua queue=default host=localhost format=binary localbind=1
--lua lp.lua query queue=default host=localhost
collectgarbage()
collectgarbage()
--print(socket.lp.query{host='localhost', queue="default"})

return nil
