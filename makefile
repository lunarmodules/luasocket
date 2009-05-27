PLAT= none
PLATS= macosx linux

#------
# Hopefully no need to change anything below this line
#
all: $(PLAT)

none:
	@echo "Please run"
	@echo "   make PLATFORM"
	@echo "where PLATFORM is one of these:"
	@echo "   $(PLATS)"

$(PLATS) install local clean:
	cd src; $(MAKE) $@

dummy:

test: dummy
	lua test/hello.lua

.PHONY: dummy
