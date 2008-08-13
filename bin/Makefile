DESTDIR=

TOPDIR=..
include $(TOPDIR)/Config.mk

SCRIPTS := oda populate_oda_packages_table prepare_oda create_oscar_database \
           set_global_oscar_values populate_default_package_set
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
