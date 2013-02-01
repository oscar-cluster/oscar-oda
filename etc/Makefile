DESTDIR=

TOPDIR=..
include $(TOPDIR)/Config.mk

FILES := mysql.cfg pgsql.cfg oscar_table.sql Migration_AddGpuSupport.sh
SUBDIRS :=

all:
	for dir in ${SUBDIRS} ; do ( cd $$dir ; ${MAKE} all ) ; done

install:
	install -d -m 0755 $(DESTDIR)/usr/share/oscar/prereqs/oda/etc
	install    -m 0755 ${FILES} $(DESTDIR)/usr/share/oscar/prereqs/oda/etc
	for dir in ${SUBDIRS} ; do ( cd $$dir ; ${MAKE} install ) ; done

uninstall:
	cd $(DESTDIR)/usr/share/oscar/prereqs/oda/etc; rm -f $(SCRIPTS)
	for dir in ${SUBDIRS} ; do ( cd $$dir ; ${MAKE} uninstall ) ; done

clean:
	rm -f *~
