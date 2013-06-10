make PLAT=win32 LUAV=5.2 LUAINC_win32='c:\cygwin\home\diego\build\include' LUALIB_win32='c:\cygwin\home\diego\build\bin\release'

#!/bin/sh
for p in Release Debug x64/Release x64/Debug; do
    for el in mime socket; do
        for e in dll lib; do
            cp $p/$el/core.$e ../bin/$p/$el/
        done;
    done;
    cp src/ltn12.lua src/socket.lua src/mime.lua ../bin/$p/
    cp src/http.lua src/url.lua src/tp.lua src/ftp.lua src/headers.lua src/smtp.lua ../bin/$p/socket/
done;
