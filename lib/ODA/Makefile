DESTDIR=
TOP_LIB_DIR = ../..
include $(TOP_LIB_DIR)/Config.mk

FILES := mysql.pm  pgsql.pm
SUBDIRS := 

all:
	for dir in ${SUBDIRS} ; do ( cd $$dir ; ${MAKE} all ) ; done

install:
	@echo Creating $(DESTDIR)$(LIBDIR)/OSCAR/ODA
	install -d -m 0755 $(DESTDIR)$(LIBDIR)/OSCAR/ODA
	install    -m 0755 ${FILES} $(DESTDIR)$(LIBDIR)/OSCAR/ODA
	for dir in ${SUBDIRS} ; do ( cd $$dir ; ${MAKE} install ) ; done

uninstall:
	cd $(DESTDIR)$(LIBDIR)/OSCAR/ODA; rm -f ${FILES}
	for dir in ${SUBDIRS} ; do ( cd $$dir ; ${MAKE} uninstall ) ; done
