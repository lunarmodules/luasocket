ltn012.pdf: ltn012.ps
	./myps2pdf ltn012.ps

ltn012.ps: ltn012.dvi
	dvips -G0 -t letter -o ltn012.ps ltn012.dvi

ltn012.dvi: ltn012.tex
	latex ltn012

clean:
	rm -f *~ *.log *.aux *.bbl *.blg ltn012.pdf ltn012.ps ltn012.dvi ltn012.lof ltn012.toc ltn012.lot

pdf: ltn012.pdf
	open ltn012.pdf

test: gem.so


gem.o: gem.c
	gcc -c -o gem.o -Wall -ansi -W -O2 gem.c

gem.so: gem.o
	export MACOSX_DEPLOYMENT_TARGET="10.3"; gcc -bundle -undefined dynamic_lookup -o gem.so gem.o
