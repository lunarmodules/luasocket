PLAT?= macosx
PLATS= macosx linux win32

#------
# Hopefully no need to change anything below this line
#
all: $(PLAT)

$(PLATS) none install local clean:
	@cd src; $(MAKE) $@

test: dummy
	lua test/hello.lua

.PHONY: dummy
