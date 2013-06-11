package = "LuaSocket"
version = "2.1-1"
source = {
   url = "git://github.com/diegonehab/luasocket.git",
   branch = "unstable"
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
   "lua >= 5.1"
}
build = {
   type = "make",
   build_variables = {
      PLAT="linux",
      LUAINC_linux="$(LUA_INCDIR)"
   },
   install_variables = {
      INSTALL_TOP_SHARE = "$(LUADIR)",
      INSTALL_TOP_LIB = "$(LIBDIR)"
   },
   platforms = {
      macosx = {
         build_variables = {
            PLAT="macosx",
            LUAINC_macosx="$(LUA_INCDIR)"
         }
      },
      windows={
         type= "command",
         build_command=
            "set INCLUDE=$(LUA_INCDIR);%INCLUDE% &"..
            "set LIB=$(LUA_LIBDIR);%LIB% &"..
            "msbuild /p:\"VCBuildAdditionalOptions= /useenv\" luasocket.sln &"..
            "mkdir mime & mkdir socket &"..
            "cp src/mime.dll mime/core.dll &"..
            "cp src/socket.dll socket/core.dll",
         install= {
            lib = {
               ["mime.core"] = "mime/core.dll",
               ["socket.core"] = "socket/core.dll"
            },
            lua = {
               "src/ltn12.lua",
               "src/mime.lua",
               "src/socket.lua",
               ["socket.headers"] = "src/headers.lua",
               ["socket.ftp"] = "src/ftp.lua",
               ["socket.http"] = "src/http.lua",
               ["socket.smtp"] = "src/smtp.lua",
               ["socket.tp"] = "src/tp.lua",
               ["socket.url"] = "src/url.lua",               
            }
         }
      }
   },
   copy_directories = { "doc", "samples", "etc", "test" }
}
