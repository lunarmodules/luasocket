PLAT?= macosx
PLATS= macosx linux win32

#------
# Hopefully no need to change anything below this line
#
all: $(PLAT)

$(PLATS) none install install-unix local clean:
	@cd src; $(MAKE) $@

test:
	lua test/hello.lua

install-both:
	touch src/*.c
	@cd src; $(MAKE) $(PLAT) LUAV=5.1
	@cd src; $(MAKE) install-unix LUAV=5.1
	touch src/*.c
	@cd src; $(MAKE) $(PLAT) LUAV=5.2
	@cd src; $(MAKE) install-unix LUAV=5.2

.PHONY: test

