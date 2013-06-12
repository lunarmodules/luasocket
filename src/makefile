# luasocket src/makefile
#
# Definitions in this section can be overriden on the command line or in the
# environment.
#
# These are equivalent:
#
#    export PLAT=linux DEBUG=DEBUG LUAV=5.2 prefix=/sw
#    make
#
# and
#
#   make PLAT=linux DEBUG=DEBUG LUAV=5.2 prefix=/sw

# PLAT: linux macosx win32 mingw
# platform to build for
PLAT?=linux

# LUAV: 5.1 5.2
# lua version to build against
LUAV?=5.1

# DEBUG: NODEBUG DEBUG
# debug mode causes luasocket to collect and returns timing information useful
# for testing and debugging luasocket itself
DEBUG?=NODEBUG

# COMPAT: COMPAT NOCOMPAT
# when compiling for 5.2, use LUA_COMPAT_MODULE
COMPAT?=NOCOMPAT

# where lua headers are found for macosx builds
# LUAINC_macosx:
# /opt/local/include
LUAINC_macosx_base?=/opt/local/include
LUAINC_macosx?=$(LUAINC_macosx_base)/lua/$(LUAV)
# FIXME default should this default to fink or to macports?
# What happens when more than one Lua version is installed?
LUAPREFIX_macosx?=/opt/local
CDIR_macosx?=lib/lua/$(LUAV)
LDIR_macosx?=share/lua/$(LUAV)


# LUAINC_linux:
# /usr/include/lua$(LUAV)
# /usr/local/include
# /usr/local/include/lua$(LUAV)
# where lua headers are found for linux builds
LUAINC_linux_base?=/usr/include
LUAINC_linux?=$(LUAINC_linux_base)/lua/$(LUAV)
LUAPREFIX_linux?=/usr/local
CDIR_linux?=lib/lua/$(LUAV)
LDIR_linux?=share/lua/$(LUAV)

# where lua headers are found for mingw builds
# LUAINC_mingw: 
# /opt/local/include
LUAINC_mingw_base?=/usr/include
LUAINC_mingw?=$(LUAINC_mingw_base)/lua/$(LUAV)
LUALIB_mingw_base?=/usr/bin
LUALIB_mingw?=$(LUALIB_mingw_base)/lua/$(LUAV)/lua$(subst .,,$(LUAV)).dll
LUAPREFIX_mingw?=/usr
CDIR_mingw?=lua/$(LUAV)
LDIR_mingw?=lua/$(LUAV)/lua


# LUAINC_win32:
# LUALIB_win32:
# where lua headers and libraries are found for win32 builds
LUAINC_win32_base?=
LUAINC_win32?=$(LUAINC_win32_base)/lua/$(LUAV)
PLATFORM_win32?=Release
LUAPREFIX_win32?=
CDIR_win32?=lua/$(LUAV)/$(PLATFORM_win32)
LDIR_win32?=lua/$(LUAV)/$(PLATFORM_win32)/lua
LUALIB_win32?=$(LUAPREFIX_win32)/lua/$(LUAV)/$(PLATFORM_win32)

# prefix: /usr/local /usr /opt/local /sw
# the top of the default install tree
prefix?=$(LUAPREFIX_$(PLAT))

CDIR?=$(CDIR_$(PLAT))
LDIR?=$(LDIR_$(PLAT))

# DESTDIR: (no default)
# used by package managers to install into a temporary destination
DESTDIR=

#------
# Definitions below can be overridden on the make command line, but
# shouldn't have to be.


#------
# Install directories
#

INSTALL_DIR=install -d
INSTALL_DATA=install -m644
INSTALL_EXEC=install
INSTALL_TOP=$(DESTDIR)$(prefix)

INSTALL_TOP_LDIR=$(INSTALL_TOP)/$(LDIR)
INSTALL_TOP_CDIR=$(INSTALL_TOP)/$(CDIR)

INSTALL_SOCKET_LDIR=$(INSTALL_TOP_LDIR)/socket
INSTALL_SOCKET_CDIR=$(INSTALL_TOP_CDIR)/socket
INSTALL_MIME_LDIR=$(INSTALL_TOP_LDIR)/mime
INSTALL_MIME_CDIR=$(INSTALL_TOP_CDIR)/mime

print:
	@echo PLAT=$(PLAT)
	@echo LUAV=$(LUAV)
	@echo DEBUG=$(DEBUG)
	@echo prefix=$(prefix)
	@echo LUAINC_$(PLAT)=$(LUAINC_$(PLAT))
	@echo LUALIB_$(PLAT)=$(LUALIB_$(PLAT))
	@echo INSTALL_TOP_CDIR=$(INSTALL_TOP_CDIR)
	@echo INSTALL_TOP_LDIR=$(INSTALL_TOP_LDIR)

#------
# Supported platforms
#
PLATS= macosx linux win32 mingw

#------
# Compiler and linker settings
# for Mac OS X
SO_macosx=so
O_macosx=o
CC_macosx=gcc
DEF_macosx= -DLUASOCKET_$(DEBUG) -DUNIX_HAS_SUN_LEN -DLUA_$(COMPAT)_MODULE \
	-DLUASOCKET_API='__attribute__((visibility("default")))' \
	-DUNIX_API='__attribute__((visibility("default")))' \
	-DMIME_API='__attribute__((visibility("default")))'
CFLAGS_macosx= -I$(LUAINC) $(DEF) -pedantic -Wall -O2 -fno-common \
	-fvisibility=hidden
LDFLAGS_macosx= -bundle -undefined dynamic_lookup -o 
LD_macosx= export MACOSX_DEPLOYMENT_TARGET="10.3"; gcc
SOCKET_macosx=usocket.o

#------
# Compiler and linker settings
# for Linux
SO_linux=so
O_linux=o
CC_linux=gcc
DEF_linux=-DLUASOCKET_$(DEBUG) -DLUA_$(COMPAT)_MODULE \
	-DLUASOCKET_API='__attribute__((visibility("default")))' \
	-DUNIX_API='__attribute__((visibility("default")))' \
	-DMIME_API='__attribute__((visibility("default")))'
CFLAGS_linux= -I$(LUAINC) $(DEF) -pedantic -Wall -Wshadow -Wextra \
	-Wimplicit -O2 -ggdb3 -fpic -fvisibility=hidden
LDFLAGS_linux=-O -shared -fpic -o 
LD_linux=gcc
SOCKET_linux=usocket.o

#------
# Compiler and linker settings
# for MingW
SO_mingw=dll
O_mingw=o
CC_mingw=gcc
DEF_mingw= -DLUASOCKET_INET_PTON -DLUASOCKET_$(DEBUG) -DLUA_$(COMPAT)_MODULE \
	-DWINVER=0x0501 -DLUASOCKET_API='__declspec(dllexport)' \
	-DMIME_API='__declspec(dllexport)'
CFLAGS_mingw= -I$(LUAINC) $(DEF) -pedantic -Wall -O2 -fno-common \
	-fvisibility=hidden
LDFLAGS_mingw= $(LUALIB) -shared -Wl,-s -lws2_32 -o 
LD_mingw=gcc
SOCKET_mingw=wsocket.o


#------
# Compiler and linker settings
# for Win32
SO_win32=dll
O_win32=obj
CC_win32=cl
DEF_win32= //D "WIN32" //D "NDEBUG" //D "_WINDOWS" //D "_USRDLL" \
     //D "LUASOCKET_API=__declspec(dllexport)" //D "_CRT_SECURE_NO_WARNINGS" \
     //D "_WINDLL" //D "LUA_$(COMPAT)_MODULE" \
	 //D "MIME_API=__declspec(dllexport)" \
     //D "LUASOCKET_$(DEBUG)" 
CFLAGS_win32=//I "$(LUAINC)" $(DEF) //O2 //Ot //MD //W3 //nologo
LDFLAGS_win32= //nologo //link //NOLOGO //DLL //INCREMENTAL:NO \
    //MANIFEST //MANIFESTFILE:"intermediate.manifest" \
    //MANIFESTUAC:"level='asInvoker' uiAccess='false'" \
	//SUBSYSTEM:WINDOWS //OPT:REF //OPT:ICF //DYNAMICBASE:NO \
    //MACHINE:X86 /LIBPATH:"$(shell cmd //c echo $(LUALIB))" \
	lua$(subst .,,$(LUAV)).lib ws2_32.lib //OUT:
LD_win32=cl
SOCKET_win32=wsocket.obj

.SUFFIXES: .obj

.c.obj:
	$(CC) $(CFLAGS) //Fo"$@" //c $<

#------
# Output file names
#
SO=$(SO_$(PLAT))
O=$(O_$(PLAT))
SOCKET_V=3.0-rc1
MIME_V=1.0.3
SOCKET_SO=socket.$(SO).$(SOCKET_V)
MIME_SO=mime.$(SO).$(MIME_V)
UNIX_SO=unix.$(SO)
SERIAL_SO=serial.$(SO)
SOCKET=$(SOCKET_$(PLAT))

#------
# Settings selected for platform
#
CC=$(CC_$(PLAT))
DEF=$(DEF_$(PLAT))
CFLAGS=$(CFLAGS_$(PLAT))
LDFLAGS=$(LDFLAGS_$(PLAT))
LD=$(LD_$(PLAT))
LUAINC= $(LUAINC_$(PLAT))
LUALIB= $(LUALIB_$(PLAT))

#------
# Modules belonging to socket-core
#
SOCKET_OBJS= \
	luasocket.$(O) \
	timeout.$(O) \
	buffer.$(O) \
	io.$(O) \
	auxiliar.$(O) \
	options.$(O) \
	inet.$(O) \
	$(SOCKET) \
	except.$(O) \
	select.$(O) \
	tcp.$(O) \
	udp.$(O)

#------
# Modules belonging mime-core
#
MIME_OBJS= \
	mime.$(O)

#------
# Modules belonging unix (local domain sockets)
#
UNIX_OBJS=\
	buffer.$(O) \
	auxiliar.$(O) \
	options.$(O) \
	timeout.$(O) \
	io.$(O) \
	usocket.$(O) \
	unix.$(O)

#------
# Modules belonging to serial (device streams)
#
SERIAL_OBJS:=\
	buffer.$(O) \
	auxiliar.$(O) \
	options.$(O) \
	timeout.$(O) \
	io.$(O) \
	usocket.$(O) \
	serial.$(O)

#------
# Files to install
#
TO_SOCKET_LDIR= \
	http.lua \
	url.lua \
	tp.lua \
	ftp.lua \
	headers.lua \
	smtp.lua

TO_TOP_LDIR= \
	ltn12.lua \
	socket.lua \
	mime.lua

#------
# Targets
#
default: $(PLAT)

macosx:
	$(MAKE) all-unix PLAT=macosx

win32:
	$(MAKE) all PLAT=win32

linux:
	$(MAKE) all-unix PLAT=linux

mingw:
	$(MAKE) all PLAT=mingw

none:
	@echo "Please run"
	@echo "   make PLATFORM"
	@echo "where PLATFORM is one of these:"
	@echo "   $(PLATS)"

all: $(SOCKET_SO) $(MIME_SO)

$(SOCKET_SO): $(SOCKET_OBJS)
	$(LD) $(SOCKET_OBJS) $(LDFLAGS)$@

$(MIME_SO): $(MIME_OBJS)
	$(LD) $(MIME_OBJS) $(LDFLAGS)$@

all-unix: all $(UNIX_SO) $(SERIAL_SO)

$(UNIX_SO): $(UNIX_OBJS)
	$(LD) $(UNIX_OBJS) $(LDFLAGS)$@

$(SERIAL_SO): $(SERIAL_OBJS)
	$(LD) $(SERIAL_OBJS) $(LDFLAGS)$@

install: 
	$(INSTALL_DIR) $(INSTALL_TOP_LDIR)
	$(INSTALL_DATA) $(TO_TOP_LDIR) $(INSTALL_TOP_LDIR)
	$(INSTALL_DIR) $(INSTALL_SOCKET_LDIR)
	$(INSTALL_DATA) $(TO_SOCKET_LDIR) $(INSTALL_SOCKET_LDIR)
	$(INSTALL_DIR) $(INSTALL_SOCKET_CDIR)
	$(INSTALL_EXEC) $(SOCKET_SO) $(INSTALL_SOCKET_CDIR)/core.$(SO)
	$(INSTALL_DIR) $(INSTALL_MIME_CDIR)
	$(INSTALL_EXEC) $(MIME_SO) $(INSTALL_MIME_CDIR)/core.$(SO)

install-unix: install
	$(INSTALL_EXEC) $(UNIX_SO) $(INSTALL_SOCKET_CDIR)/$(UNIX_SO)
	$(INSTALL_EXEC) $(SERIAL_SO) $(INSTALL_SOCKET_CDIR)/$(SERIAL_SO)

local:
	$(MAKE) install INSTALL_TOP_CDIR=.. INSTALL_TOP_LDIR=..

clean:
	rm -f $(SOCKET_SO) $(SOCKET_OBJS) $(SERIAL_OBJS)
	rm -f $(MIME_SO) $(UNIX_SO) $(SERIAL_SO) $(MIME_OBJS) $(UNIX_OBJS)

.PHONY: all $(PLATS) default clean echo none

#------
# List of dependencies
#
auxiliar.$(O): auxiliar.c auxiliar.h
buffer.$(O): buffer.c buffer.h io.h timeout.h
except.$(O): except.c except.h
inet.$(O): inet.c inet.h socket.h io.h timeout.h usocket.h
io.$(O): io.c io.h timeout.h
luasocket.$(O): luasocket.c luasocket.h auxiliar.h except.h \
	timeout.h buffer.h io.h inet.h socket.h usocket.h tcp.h \
	udp.h select.h
mime.$(O): mime.c mime.h
options.$(O): options.c auxiliar.h options.h socket.h io.h \
	timeout.h usocket.h inet.h
select.$(O): select.c socket.h io.h timeout.h usocket.h select.h
serial.$(O): serial.c auxiliar.h socket.h io.h timeout.h usocket.h \
  options.h unix.h buffer.h
tcp.$(O): tcp.c auxiliar.h socket.h io.h timeout.h usocket.h \
	inet.h options.h tcp.h buffer.h
timeout.$(O): timeout.c auxiliar.h timeout.h
udp.$(O): udp.c auxiliar.h socket.h io.h timeout.h usocket.h \
	inet.h options.h udp.h
unix.$(O): unix.c auxiliar.h socket.h io.h timeout.h usocket.h \
	options.h unix.h buffer.h
usocket.$(O): usocket.c socket.h io.h timeout.h usocket.h
wsocket.$(O): wsocket.c socket.h io.h timeout.h usocket.h
