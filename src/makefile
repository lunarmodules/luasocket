PLAT = none
INSTALL_DATA=cp
INSTALL_EXEC=cp
INSTALL_TOP= /opt/local
LUAINC= $(LUAINC_$(PLAT))

#------
# Install directories
#
INSTALL_TOP_SHARE=$(INSTALL_TOP)/share/lua/5.1
INSTALL_TOP_LIB=$(INSTALL_TOP)/lib/lua/5.1
INSTALL_SOCKET_SHARE=$(INSTALL_TOP_SHARE)/socket
INSTALL_SOCKET_LIB=$(INSTALL_TOP_LIB)/socket
INSTALL_MIME_SHARE=$(INSTALL_TOP_SHARE)/mime
INSTALL_MIME_LIB=$(INSTALL_TOP_LIB)/mime

#------
# Output file names
#
EXT=so
SOCKET_V=2.0.3
MIME_V=1.0.3
SOCKET_SO=socket.$(EXT).$(SOCKET_V)
MIME_SO=mime.$(EXT).$(MIME_V)
UNIX_SO=unix.$(EXT)

#------
# Compiler and linker settings
# for Mac OS X
LUAINC_macosx= -I/opt/local/include
CC_macosx=gcc
DEF_macosx= -DLUASOCKET_DEBUG -DUNIX_HAS_SUN_LEN \
	-DLUASOCKET_API='__attribute__((visibility("default")))' \
	-DMIME_API='__attribute__((visibility("default")))'
CFLAGS_macosx= $(LUAINC) $(COMPAT) $(DEF) -pedantic -Wall -O2 -fno-common \
	-fvisibility=hidden
LDFLAGS_macosx= -bundle -undefined dynamic_lookup
LD_macosx= export MACOSX_DEPLOYMENT_TARGET="10.3"; gcc

#------
# Compiler and linker settings
# for Linux
LUAINC_linux= -I/usr/local/include/lua5.1
CC_linux=gcc
DEF_linux=-DLUASOCKET_DEBUG \
	-DLUASOCKET_API='__attribute__((visibility("default")))' \
	-DMIME_API='__attribute__((visibility("default")))'
CFLAGS_linux= $(LUAINC) $(DEF) -pedantic -Wall -O2 -fpic \
	-fvisibility=hidden
LDFLAGS_linux=-O -shared -fpic
LD_linux= gcc

#------
# Settings selected for platform
#
CC=$(CC_$(PLAT))
DEF=$(DEF_$(PLAT))
CFLAGS=$(CFLAGS_$(PLAT))
LDFLAGS=$(LDFLAGS_$(PLAT))
LD=$(LD_$(PLAT))

#------
# Modules belonging to socket-core
#
SOCKET_OBJS= \
	luasocket.o \
	timeout.o \
	buffer.o \
	io.o \
    auxiliar.o \
	options.o \
	inet.o \
	usocket.o \
	except.o \
	select.o \
	tcp.o \
	udp.o

#------
# Modules belonging mime-core
#
MIME_OBJS= \
	mime.o

#------
# Modules belonging unix (local domain sockets)
#
UNIX_OBJS:=\
	buffer.o \
	auxiliar.o \
	options.o \
	timeout.o \
	io.o \
	usocket.o \
	unix.o

#------
# Files to install
#
TO_SOCKET_SHARE:= \
	http.lua \
	url.lua \
	tp.lua \
	ftp.lua \
	headers.lua \
	smtp.lua

TO_TOP_SHARE:= \
	ltn12.lua \
	socket.lua \
	mime.lua

default: $(PLAT)

macosx:
	$(MAKE) all PLAT=macosx

linux:
	$(MAKE) all PLAT=linux

none:
	@echo "Please choose a platform:"
	@echo "   $(PLATS)"

all: $(SOCKET_SO) $(MIME_SO)

$(SOCKET_SO): $(SOCKET_OBJS)
	$(LD) $(LDFLAGS) -o $@ $(SOCKET_OBJS)

$(MIME_SO): $(MIME_OBJS)
	$(LD) $(LDFLAGS) -o $@ $(MIME_OBJS)

$(UNIX_SO): $(UNIX_OBJS)
	$(LD) $(LDFLAGS) -o $@ $(UNIX_OBJS)

install: 
	mkdir -p $(INSTALL_TOP_SHARE)
	$(INSTALL_DATA) $(TO_TOP_SHARE) $(INSTALL_TOP_SHARE)
	mkdir -p $(INSTALL_SOCKET_SHARE)
	$(INSTALL_DATA) $(TO_SOCKET_SHARE) $(INSTALL_SOCKET_SHARE)
	mkdir -p $(INSTALL_SOCKET_LIB)
	$(INSTALL_EXEC) $(SOCKET_SO) $(INSTALL_SOCKET_LIB)/core.$(EXT)
	mkdir -p $(INSTALL_MIME_LIB)
	$(INSTALL_EXEC) $(MIME_SO) $(INSTALL_MIME_LIB)/core.$(EXT)

local:
	$(MAKE) install INSTALL_TOP_LIB=.. INSTALL_TOP_SHARE=..

clean:
	rm -f $(SOCKET_SO) $(SOCKET_OBJS)
	rm -f $(MIME_SO) $(UNIX_SO) $(MIME_OBJS) $(UNIX_OBJS)

.PHONY: all $(PLATS) default clean echo none

#------
# List of dependencies
#
auxiliar.o: auxiliar.c auxiliar.h
buffer.o: buffer.c buffer.h io.h timeout.h
except.o: except.c except.h
inet.o: inet.c inet.h socket.h io.h timeout.h usocket.h
io.o: io.c io.h timeout.h
luasocket.o: luasocket.c luasocket.h auxiliar.h except.h \
	timeout.h buffer.h io.h inet.h socket.h usocket.h tcp.h \
	udp.h select.h
mime.o: mime.c mime.h
options.o: options.c auxiliar.h options.h socket.h io.h \
	timeout.h usocket.h inet.h
select.o: select.c socket.h io.h timeout.h usocket.h select.h
tcp.o: tcp.c auxiliar.h socket.h io.h timeout.h usocket.h \
	inet.h options.h tcp.h buffer.h
timeout.o: timeout.c auxiliar.h timeout.h
udp.o: udp.c auxiliar.h socket.h io.h timeout.h usocket.h \
	inet.h options.h udp.h
unix.o: unix.c auxiliar.h socket.h io.h timeout.h usocket.h \
	options.h unix.h buffer.h
usocket.o: usocket.c socket.h io.h timeout.h usocket.h
wsocket.o: wsocket.c socket.h io.h timeout.h usocket.h
