-- dict.lua
-- simple client for DICT protocol (see http://www.dict.org/)
-- shows definitions for each word from stdin. uses only "wn" dictionary.
-- if a word is "=", then the rest of the line is sent verbatim as a protocol
-- command to the server.

if verbose then verbose=write else verbose=function()end end

verbose(">>> connecting to server\n")
local s,e=connect("dict.org",2628)
assert(s,e)
verbose(">>> connected\n")

while 1 do
 local w=read"*w"
 if w==nil then break end
 if w=="=" then
  w=read"*l"
  verbose(">>>",w,"\n")
  send(s,w,"\r\n")
 else
  verbose(">>> looking up `",w,"'\n")
  send(s,"DEFINE wn ",w,"\r\n")
 end
 while 1 do
  local l=receive(s)
  if l==nil then break end
  if strfind(l,"^[0-9]") then
   write("<<< ",l,"\n")
  else
   write(l,"\n")
  end
  if strfind(l,"^250") or strfind(l,"^[45]") then break end
 end
end

send(s,"QUIT\r\n")
verbose("<<< ",receive(s),"\n")
close(s)
