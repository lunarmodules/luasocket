#------
# Load configuration
#
include config

#------
# Hopefully no need to change anything below this line
#
INSTALL_SOCKET=$(INSTALL_TOP)/socket
INSTALL_MIME=$(INSTALL_TOP)/mime

all clean:
	cd src; $(MAKE) $@

#------
# Files to install
#
TO_SOCKET:= \
	socket.lua \
	http.lua \
	url.lua \
	tp.lua \
	ftp.lua \
	smtp.lua

TO_TOP:= \
	ltn12.lua

TO_MIME:= \
	$(MIME_SO) \
	mime.lua

#------
# Install LuaSocket according to recommendation
#
install: all
	cd src; mkdir -p $(INSTALL_TOP)
	cd src; $(INSTALL_DATA) $(COMPAT)/compat-5.1.lua $(INSTALL_TOP)
	cd src; $(INSTALL_DATA) ltn12.lua $(INSTALL_TOP)
	cd src; mkdir -p $(INSTALL_SOCKET)
	cd src; $(INSTALL_EXEC) $(SOCKET_SO) $(INSTALL_SOCKET)
	cd src; $(INSTALL_DATA) $(TO_SOCKET) $(INSTALL_SOCKET)
	cd src; cd $(INSTALL_SOCKET); $(INSTALL_LINK) -s $(SOCKET_SO) core.$(EXT)
	cd src; cd $(INSTALL_SOCKET); $(INSTALL_LINK) -s socket.lua init.lua
	cd src; mkdir -p $(INSTALL_MIME)
	cd src; $(INSTALL_DATA) $(TO_MIME) $(INSTALL_MIME)
	cd src; cd $(INSTALL_MIME); $(INSTALL_LINK) -s $(MIME_SO) core.$(EXT)
	cd src; cd $(INSTALL_MIME); $(INSTALL_LINK) -s mime.lua init.lua

#------
# End of makefile
#
