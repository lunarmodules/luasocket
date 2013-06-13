package = "LuaSocket"
version = "scm-0"

source = {
  url = "https://github.com/diegonehab/luasocket/archive/master.zip",
  dir = "luasocket-master",
}

description = {
   summary = "Network support for the Lua language",
   detailed = [[
      LuaSocket is a Lua extension library that is composed by two parts: a C core
      that provides support for the TCP and UDP transport layers, and a set of Lua
      modules that add support for functionality commonly needed by applications
      that deal with the Internet.
   ]],
   homepage = "http://luaforge.net/projects/luasocket/",
   license = "MIT"
}

dependencies = {
   "lua >= 5.1, < 5.3"
}

build = {
   type = "make",
   build_variables = {
      PLAT="linux",
      LUAINC_linux="$(LUA_INCDIR)"
   },
   install_variables = {
      INSTALL_TOP_LDIR = "$(LUADIR)",
      INSTALL_TOP_CDIR = "$(LIBDIR)"
   },
   platforms = {
      macosx = {
         build_variables = {
            PLAT="macosx",
            LUAINC_macosx="$(LUA_INCDIR)"
         }
      },
      windows={
        type= "builtin",
        modules = {
          ["mime.core"] = {
            sources = {"src/mime.c"},
            defines = {
              'MIME_EXPORTS',
              'MIME_API=__declspec(dllexport)',
              'WIN32','_WIN32','_WINDOWS',
            },
          },
          ["socket.core"] = {
            sources = {
              "src/auxiliar.c","src/buffer.c","src/except.c","src/timeout.c",
              "src/luasocket.c","src/options.c","src/select.c", "src/wsocket.c",
              "src/io.c","src/tcp.c","src/udp.c","src/inet.c"
            },
            libraries = {"ws2_32", "iphlpapi"},
            defines = {
              'LUASOCKET_EXPORTS',
              'LUASOCKET_API=__declspec(dllexport)',
              'WIN32','_WIN32','_WINDOWS',
              -- '_WIN32_WINNT=0x0501', 'LUASOCKET_INET_PTON',
            },
          },
          ["ltn12"       ] = "src/ltn12.lua",
          ["mime"        ] = "src/mime.lua",
          ["socket"      ] = "src/socket.lua",
          ["socket.ftp"  ] = "src/ftp.lua",
          ["socket.http" ] = "src/http.lua",
          ["socket.smtp" ] = "src/smtp.lua",
          ["socket.tp"   ] = "src/tp.lua",
          ["socket.url"  ] = "src/url.lua",
        }
      }
   },
   copy_directories = { "doc", "samples", "etc", "test" }
}

build.platforms.mingw32 = build.platforms.windows
