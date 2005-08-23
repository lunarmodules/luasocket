#------
# Load configuration
#
include config

#------
# Hopefully no need to change anything below this line
#
INSTALL_SOCKET_LUA=$(INSTALL_TOP_LUA)/socket
INSTALL_SOCKET_LIB=$(INSTALL_TOP_LIB)/socket
INSTALL_MIME_LUA=$(INSTALL_TOP_LUA)/mime
INSTALL_MIME_LIB=$(INSTALL_TOP_LIB)/mime

all clean:
	cd src; $(MAKE) $@

#------
# Files to install
#
TO_SOCKET_LUA:= \
	socket.lua \
	http.lua \
	url.lua \
	tp.lua \
	ftp.lua \
	smtp.lua

TO_TOP_LUA:= \
	ltn12.lua

TO_MIME_LUA:= \
	mime.lua

#------
# Install LuaSocket according to recommendation
#
install: all
	cd src; mkdir -p $(INSTALL_TOP_LUA)
	cd src; mkdir -p $(INSTALL_TOP_LIB)
	cd src; $(INSTALL_DATA) $(COMPAT)/compat-5.1.lua $(INSTALL_TOP_LUA)
	cd src; $(INSTALL_DATA) ltn12.lua $(INSTALL_TOP_LUA)
	cd src; mkdir -p $(INSTALL_SOCKET_LUA)
	cd src; mkdir -p $(INSTALL_SOCKET_LIB)
	cd src; $(INSTALL_DATA) $(TO_SOCKET_LUA) $(INSTALL_SOCKET_LUA)
	cd src; $(INSTALL_EXEC) $(SOCKET_SO) $(INSTALL_SOCKET_LIB)/core.$(EXT)
	cd src; mkdir -p $(INSTALL_MIME_LUA)
	cd src; mkdir -p $(INSTALL_MIME_LIB)
	cd src; $(INSTALL_DATA) $(TO_MIME_LUA) $(INSTALL_MIME_LUA)
	cd src; $(INSTALL_EXEC) $(MIME_SO) $(INSTALL_MIME_LIB)/core.$(EXT)

#------
# End of makefile
#
