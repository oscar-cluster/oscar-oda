#!/bin/bash
#
# $Id:$
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

# this script is responsible of upgrading the ODA database for GPU support.
# It adds the gpu_num column if missing.
# This script can be run multiple times harmlessly.
# It should be compatible with all mysql version including older ones.
# Tested successfully on mysql 4.1.22 on CentOS-4.8

# (C)opyright Olivier Lahaye <olivier.lahaye at cea.fr>

#  Copyright (c) 2012   CEA²
#                       All rights reserved.

if mysql oscar >/dev/null 2>&1 </dev/null
then
	if test -z "$(echo 'DESC Nodes;' |mysql -u root oscar|grep gpu_num)"
	then
		echo "ALTER TABLE Nodes ADD COLUMN gpu_num int(11) AFTER cpu_num;"|mysql -u root oscar
	fi
else
	echo "oda: OSCAR database not available: Assuming fresh install."
	echo "oda: If it is not the case, please start the database manually and"
	echo "oda: run /usr/share/oscar/prereqs/oda/etc/Migration_AddGpuSupport.sh"
fi
