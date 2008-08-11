DESTDIR=

TOPDIR=..
include $(TOPDIR)/Config.mk

SCRIPTS := oda populate_oda_packages_table prepare_oda
SUBDIRS :=

all:
	for dir in ${SUBDIRS} ; do ( cd $$dir ; ${MAKE} all ) ; done

install:
	@install -d -m 0755 $(DESTDIR)/usr/bin
	@install    -m 0755 $(SCRIPTS) $(DESTDIR)/usr/bin
	for dir in ${SUBDIRS} ; do ( cd $$dir ; ${MAKE} install ) ; done

uninstall:
	cd $(DESTDIR)/usr/bin; rm -f $(SCRIPTS)
	for dir in ${SUBDIRS} ; do ( cd $$dir ; ${MAKE} uninstall ) ; done

clean:
