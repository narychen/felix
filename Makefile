all: build test doc 

# Build directory structure:
#
# build/release: the default build location, optimised
# build/debug:   debug symbols, optimisation off
#
# build32, build64: so you can build "the other" word size version
#   if your platform can build it, to check code is portable
#

# 
# default build
#

VERSION = 1.1.7dev
DISTDIR ?= ./build/dist

build:
	python3 fbuild/fbuild-light build $(FBUILD_PARAMS)

build-clang:
	python3 fbuild/fbuild-light build --build-cc=clang --build-cxx=clang++ $(FBUILD_PARAMS)

test:
	python3 fbuild/fbuild-light test $(FBUILD_PARAMS)

test-clang:
	python3 fbuild/fbuild-light build --build-cc=clang --build-cxx=clang++ test $(FBUILD_PARAMS)


#
# debug build
#
build-debug:
	python3 fbuild/fbuild-light -g build $(FBUILD_PARAMS)

test-debug:
	python3 fbuild/fbuild-light -g test $(FBUILD_PARAMS)

#
# 32 bit build
#
build32:
	python3 fbuild/fbuild-light --c-flag=-m32 --buildroot=build32 build $(FBUILD_PARAMS)

test32:
	python3 fbuild/fbuild-light --c-flag=-m32 --buildroot=build32 test $(FBUILD_PARAMS)

#
# 32 bit debug build
#
build32-debug:
	python3 fbuild/fbuild-light -g --c-flag=-m32 --buildroot=build32 build $(FBUILD_PARAMS)

test32-debug:
	python3 fbuild/fbuild-light -g --c-flag=-m32 --buildroot=build32 test $(FBUILD_PARAMS)

#
# 64 bit build
#
build64:
	python3 fbuild/fbuild-light --c-flag=-m64 --buildroot=build64 build $(FBUILD_PARAMS)

test64:
	python3 fbuild/fbuild-light --c-flag=-m64 --buildroot=build64 test $(FBUILD_PARAMS)

#
# 64 bit debug build
build64-debug:
	python3 fbuild/fbuild-light -g --c-flag=-m64 --buildroot=build64 build $(FBUILD_PARAMS)

test64-debug:
	python3 fbuild/fbuild-light -g --c-flag=-m64 --buildroot=build64 test $(FBUILD_PARAMS)
#
#
# Install default build into /usr/local/lib/felix/version/
#
install:
	sudo build/release/bin/flx --test=build/release --install 
	sudo build/release/bin/flx --test=build/release --install-bin
	sudo rm -rf $(HOME)/.felix/cache
	sudo rm -f /usr/local/lib/felix/felix-latest
	sudo ln -s /usr/local/lib/felix/felix-$(VERSION) /usr/local/lib/felix/felix-latest
	echo 'println ("installed "+ Version::felix_version);' > install-done.flx
	flx install-done
	rm install-done.*
	sudo chown $(USER) $(HOME)/.felix
	flx_libcontents --html > tmp1.html
	flx_libindex --html > tmp2.html
	flx_gramdoc --html > tmp3.html
	sudo cp tmp1.html /usr/local/lib/felix/felix-latest/web/flx_libcontents.html
	sudo cp tmp2.html /usr/local/lib/felix/felix-latest/web/flx_libindex.html
	sudo cp tmp3.html /usr/local/lib/felix/felix-latest/web/flx_gramdoc.html
	rm tmp1.html tmp2.html tmp3.html


#
# Install binaries on felix-lang.org
#
install-felix-lang.org:
	-sudo stop felixweb
	sudo build/release/bin/flx --test=build/release --install 
	sudo build/release/bin/flx --test=build/release --install-bin
	sudo rm -rf $(HOME)/.felix/cache
	echo 'println ("installed "+ Version::felix_version);' > install-done.flx
	flx install-done
	rm install-done.*
	flx_libcontents --html > tmp1.html
	flx_libindex --html > tmp2.html
	flx_gramdoc --html > tmp3.html
	sudo cp tmp1.html /usr/local/lib/felix/felix-latest/web/flx_libcontents.html
	sudo cp tmp2.html /usr/local/lib/felix/felix-latest/web/flx_libindex.html
	sudo cp tmp3.html /usr/local/lib/felix/felix-latest/web/flx_gramdoc.html
	rm tmp1.html tmp2.html tmp3.html
	sudo start felixweb

#
# Finalise a release??
#
release:
	git tag v`flx --version`
	git commit v`flx --version`
	git push
	fbuild/fbuild-light configure build doc dist
	sudo build/release/bin/flx --test=build/release --install
	sudo build/release/bin/flx --test=build/release --install-bin
	echo "Restart webservers now"
	echo "Upgrade buildsystem/version.py now and rebuild"


make-dist:
	rm -rf $(DISTDIR)
	./build/release/bin/flx --test=build/release --dist=$(DISTDIR)
	rm -rf $(HOME)/.felix/cache
	echo 'println ("installed "+ Version::felix_version);' > $(DISTDIR)/install-done.flx
	./build/release/bin/flx --test=$(DISTDIR)/lib/felix/felix-$(VERSION) $(DISTDIR)/install-done.flx
	echo "export LD_LIBRARY_PATH=$(DISTDIR)/lib:$(DISTDIR)/lib/felix/felix-$(VERSION)/lib/rtl">$(DISTDIR)/build-idx.sh
	echo "$(DISTDIR)/bin/flx_libcontents --html > $(DISTDIR)/tmp1.html">>$(DISTDIR)/build-idx.sh
	echo "$(DISTDIR)/bin/flx_libindex --html > $(DISTDIR)/tmp2.html">>$(DISTDIR)/build-idx.sh
	echo "$(DISTDIR)/bin/flx_gramdoc --html > $(DISTDIR)/tmp3.html">>$(DISTDIR)/build-idx.sh
	sh $(DISTDIR)/build-idx.sh
	cp $(DISTDIR)/tmp1.html $(DISTDIR)/lib/felix/felix-$(VERSION)/web/flx_libcontents.html
	cp $(DISTDIR)/tmp2.html $(DISTDIR)/lib/felix/felix-$(VERSION)/web/flx_libindex.html
	cp $(DISTDIR)/tmp3.html $(DISTDIR)/lib/felix/felix-$(VERSION)/web/flx_gramdoc.html
	rm -f $(DISTDIR)/tmp1.html $(DISTDIR)/tmp2.html $(DISTDIR)/tmp3.html $(DISTDIR)/build-idx.sh $(DISTDIR)/install-done.flx  $(DISTDIR)/install-done.so


install-plugins:
	sudo cp build/release/shlib/* /usr/local/lib/

install-website:
	sudo cp -r build/release/web/* /usr/local/lib/felix/felix-latest/web


#
# Helper for checking new syntax
#
syntax:
	rm -f build/release/lib/grammar/*
	cp src/lib/grammar/* build/release/lib/grammar
	rm *.par2

#
# Documentation
#
doc: copy-doc check-tut

# Copy docs from repo src to release image
copy-doc: gen-doc
	build/release/bin/flx_cp src/web '(.*\.fdoc)' 'build/release/web/$${1}'
	build/release/bin/flx_cp src/web '(.*\.(png|jpg|gif))' 'build/release/web/$${1}'
	build/release/bin/flx_cp src/web '(.*\.html)' 'build/release/web/$${1}'
	build/release/bin/flx_cp src/ '(.*\.html)' 'build/release/$${1}'

# upgrade tutorial indices in repo src
# must be done prior to copy-doc
# muut be done after primary build
# results should be committed to repo.
# Shouldn't be required on client build because the results
# should already have been committed to the repo.
gen-doc:
	build/release/bin/mktutindex tut Tutorial tutorial.fdoc
	build/release/bin/mktutindex fibres Fibres tutorial.fdoc
	build/release/bin/mktutindex objects Objects tutorial.fdoc
	build/release/bin/mktutindex polymorphism Polymorphism tutorial.fdoc
	build/release/bin/mktutindex pattern Patterns tutorial.fdoc
	build/release/bin/mktutindex literals Literals tutorial.fdoc
	build/release/bin/mktutindex cbind "C Binding" tutorial.fdoc
	build/release/bin/mktutindex streams Streams tutorial.fdoc
	build/release/bin/mktutindex array "Arrays" tutorial.fdoc
	build/release/bin/mktutindex garray "Generalised Arrays" tutorial.fdoc
	build/release/bin/mktutindex uparse "Universal Parser" uparse.fdoc
	build/release/bin/mktutindex nutut/intro/intro "Ground Up" ../../tutorial.fdoc

# Checks correctness of tutorial in release image
# must be done after copy-doc
# must be done after primary build
check-tut:
	build/release/bin/flx_tangle --inoutdir=build/release/web/nutut/intro/ '.*'
	for  i in build/release/web/nutut/intro/*.flx; \
	do \
		j=$$(echo $$i | sed s/.flx//); \
		echo $$j; \
		build/release/bin/flx --test=build/release --stdout=$$j.output $$j; \
		diff -N $$j.expect $$j.output; \
	done

# optional build of compiler docs
# targets repository
# Don't run by default because ocamldoc is a bit buggy
ocamldoc:
	mkdir -p parsedoc
	ocamldoc -d parsedoc -html \
		-I build/release/src/compiler/flx_version \
		-I build/release/src/compiler/ocs/src \
		-I build/release/src/compiler/dypgen/dyplib \
		-I build/release/src/compiler/sex \
		-I build/release/src/compiler/flx_lex \
		-I build/release/src/compiler/flx_parse \
		-I build/release/src/compiler/flx_parse \
		-I build/release/src/compiler/flx_misc \
		-I build/release/src/compiler/flx_file \
		src/compiler/flx_version/*.mli \
		src/compiler/flx_version/*.ml \
		src/compiler/sex/*.mli \
		src/compiler/sex/*.ml \
		src/compiler/flx_lex/*.mli \
		src/compiler/flx_lex/*.ml \
		src/compiler/flx_parse/*.ml \
		src/compiler/flx_parse/*.mli \
		src/compiler/flx_file/*.mli \
		src/compiler/flx_file/*.ml \
		src/compiler/flx_misc/*.mli \
		src/compiler/flx_misc/*.ml 


.PHONY : build32 build64 build test32 test64 test  
.PHONY : build32-debug build64-debug build-debug test32-debug test64-debug test-debug 
.PHONY : doc install websites-linux  release install-bin 
.PHONY : copy-doc gen-doc check-tut

