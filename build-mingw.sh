LUA=../lua-5.2.1/src/
BUILD_FLAGS="-Wl,-s -O2 -shared -D LUA_COMPAT_MODULE -D IPV6_V6ONLY=1 -D WINVER=0x0501 -s -I src -I $LUA -L $LUA"

mkdir -p lib/mime lib/socket
gcc $BUILD_FLAGS -o "lib/mime/core.dll" src/mime.c -llua \
  || { echo "Error: failed to build LuaSocket/mime"; exit 1; }
gcc $BUILD_FLAGS -o "lib/socket/core.dll" \
  src/{luasocket.c,auxiliar.c,buffer.c,except.c,inet.c,io.c,options.c,select.c,tcp.c,timeout.c,udp.c,wsocket.c} -lwsock32 -lws2_32 -llua \
  || { echo "Error: failed to build LuaSocket/socket"; exit 1; }
