DESTDIR=

include ./Config.mk

SUBDIRS := etc bin lib

all:
	for dir in ${SUBDIRS} ; do ( cd $$dir ; ${MAKE} all ) ; done

install:
	for dir in ${SUBDIRS} ; do ( cd $$dir ; ${MAKE} install ) ; done

uninstall:
	for dir in ${SUBDIRS} ; do ( cd $$dir ; ${MAKE} uninstall ) ; done

clean:
	@rm -f build-stamp configure-stamp
	@rm -rf debian/oda
	@rm -f oda.tar.gz
	@rm -f oda.spec
	for dir in ${SUBDIRS} ; do ( cd $$dir ; ${MAKE} clean ) ; done

dist: clean
	@rm -rf /tmp/oda
	@mkdir -p /tmp/oda
	@cp -rf * /tmp/oda
	@cd /tmp/oda; rm -rf `find . -name ".svn"`
	@cd /tmp; tar czf oda.tar.gz oda
	@cp -f /tmp/oda.tar.gz .

rpm: dist
	sed -e "s/PERLLIBPATH/$(SEDLIBDIR)/" < oda.spec.in \
        > oda.spec
	rpmbuild -bb ./oda.spec
