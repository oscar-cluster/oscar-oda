package OSCAR::ODA::Bootstrap;

#
# Copyright (c) 2007-2008 Geoffroy Vallee <valleegr@ornl.gov>
#                         Oak Ridge National Laboratory
#                         All rights reserved.
#
#   This program is free software; you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation; either version 2 of the License, or
#   (at your option) any later version.
#
#   This program is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this program; if not, write to the Free Software
#   Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
#
# This package provides a set of functions for the ODA bootstrap.
#

#
# $Id$
#

use strict;
use vars qw(@EXPORT);
use base qw(Exporter);
use File::Basename;
use Carp;
use OSCAR::Logger;
use OSCAR::LoggerDefs;

@EXPORT = qw (
                init_db
                init_file_db
             );


################################################################################
# Initialize the database used by ODA when a real database is used (e.g.,      #
# mysql).                                                                      #
#                                                                              #
# Input: OSCAR configurator object (ConfigManager object).                     #
# Return: 0 if success, -1 else.                                               #
# TODO: that should be in ODA, not here.                                       #
################################################################################
sub init_db ($) {
    my $configurator = shift;
    if (!defined ($configurator)) {
        oscar_log(6, ERROR, "Invalid configurator object.");
        return -1;
    }
    my $config = $configurator->get_config();
    
    require OSCAR::oda;
    oscar_log(3, INFO, "Database Initialization...");
    require OSCAR::SystemServices;
    require OSCAR::SystemServicesDefs;
    my $db_type = $config->{'db_type'};
    my $db_service = OSCAR::SystemServicesDefs::MYSQL(); # Default value.
    if (defined ($db_type)) {
        if ("$db_type" eq "mysql") {
            $db_service = OSCAR::SystemServicesDefs::MYSQL();
        } elsif ("$db_type" eq "pgsql") {
            $db_service = OSCAR::SystemServicesDefs::POSTGRESQL();
        } else {
            carp "ERROR: unknown database type (DB_TYPE) in oscar.conf";
        }
    }

    OSCAR::SystemServices::system_service ($db_service, OSCAR::SystemServicesDefs::START());
    my (%options, %errors);
    my $database_status = OSCAR::oda::check_oscar_database(
        \%options,
        \%errors);
    print "Database_status: $database_status\n";
    if (!$database_status) {
        my $scripts_path = $config->{'binaries_path'};
        my $cmd =  "$scripts_path/make_database_password";
        my $ret = system ($cmd);
        if ($ret) {
            carp "ERROR: Impossible to create the database passwd ".
                 "($cmd, $ret)\n";
            return -1;
        }

        # GV: TODO - Initialization of ODA is still messy. The initialization
        # should be composed by two phases: the common initialization, and
        # the db specific initialization. This will avoid code duplication.
        print "--> Password ok, now creating the database\n";
        $cmd = "$scripts_path/prepare_oda";
        print "--> Executing $cmd\n";
        if (system ($cmd)) {
            carp "ERROR: Impossible to populate the database ($cmd)\n";
            return -1;
        }

        # We double-check if the database really exists
        $database_status = OSCAR::oda::check_oscar_database(
            \%options,
            \%errors);
        if (!$database_status) {
            carp "ERROR: The database is supposed to have been created but\n".
                 " we cannot connect to it.\n";
            return -1;
        }
    }

    return 0;
}

################################################################################
# Initialize the database used by ODA when flat files are used (e.g.mysql).    #
#                                                                              #
# Input: None.                                                                 #
# Return: 0 if success, -1 else.                                               #
################################################################################
sub init_file_db () {
    # We get the configuration from the OSCAR configuration file.
    my $oscar_configurator = OSCAR::ConfigManager->new();
    if ( ! defined ($oscar_configurator) ) {
        carp "ERROR: Impossible to get the OSCAR configuration\n";
        return -1;
    }
    my $config = $oscar_configurator->get_config();
    my $scripts_path = $config->{binaries_path};

    # We just check if the directories exist in /etc/oscar
    my $path = "/etc/oscar/";
    my $opkgs_config_path = $path . "opkgs";
    my $clusters_path = $path . "clusters";

    if ( ! -d $path ) {
        mkdir ($path);
    }
    if ( ! -d $clusters_path ) {
        mkdir ($clusters_path);
    }
    if ( ! -d $opkgs_config_path ) {
        mkdir ($opkgs_config_path);
    }
    print "--> Database created, now populating the database\n";
    my $cmd = "$scripts_path/prepare_oda";
    if (system ($cmd)) {
        carp "ERROR: Impossible to populate the database ($cmd)\n";
        return -1;
    }
    return 0;
}

################################################################################
# Bootstrap ODA.                                                               #
#                                                                              #
# Input: option, describe the type of db we want to use. Possible values are   #
#                undef, mysql, or postgresql.                                  #
# Return: 0 if sucess, -1 else.                                                #
################################################################################
sub bootstrap_oda ($) {
    my $option = shift;
    require OSCAR::ConfigManager;
    require OSCAR::Bootstrap;

    # We get the configuration from the OSCAR configuration file.
    my $oscar_configurator = OSCAR::ConfigManager->new();
    if ( ! defined ($oscar_configurator) ) {
        carp "ERROR: Impossible to get the OSCAR configuration\n";
        return -1;
    }

    #
    # We setup ODA, creating few symlinks
    #

    my $orig;
    my $dest;
    if ($option eq "mysql" || $option eq "postgresql") {
        # First we deal with oda.pm
        if (defined $ENV{OSCAR_HOME}) {
            $dest = "$ENV{OSCAR_HOME}/lib/OSCAR/oda.pm";
            $orig = "$ENV{OSCAR_HOME}/lib/OSCAR/ODA/";
        } else {
            my @data = Config::config_re("vendorlib");
            if (scalar (@data) > 1 || scalar (@data) == 0) {
                carp "ERROR: Impossible to know where are the Perl modules";
                return -1;
            }
            my ($key, $path) = split ("=", $data[0]);
            $path =~ m/\'(.*)\'/;
            $path = $1;
            $dest = "$path/OSCAR/oda.pm";
            $orig = "$path/OSCAR/ODA/";
        }
        if ($option eq "mysql") {
            $orig = $orig . "mysql.pm";
        } else {
            $orig = $orig . "pgsql.pm";
        }

        unlink ($dest) if (-f $dest);
        if (symlink($orig, $dest) == 0) {
            carp "ERROR: Impossible to create symlink $orig -> $dest";
            return -1;
        }

        # Then we deal with prereq.cfg
        if (defined $ENV{OSCAR_HOME}) {
            $dest = "$ENV{OSCAR_HOME}/packages/oda/prereq.cfg";
            $orig = "$ENV{OSCAR_HOME}/packages/oda/prereqs/";
        } else {
            $dest = "/usr/share/oscar/prereqs/oda/prereq.cfg";
            $orig = "/usr/share/oscar/prereqs/oda/etc/";
        }
        if ($option eq "mysql") {
            $orig = $orig . "mysql.cfg";
        } else {
            $orig = $orig . "pgsql.cfg";
        }

        unlink ($dest) if (-f $dest);
        if (symlink($orig, $dest) == 0) {
            carp "ERROR: Impossible to create symlink $orig -> $dest";
            return -1;
        }
    } else {
        warn "INFO: you try to use $option, we do not need to initialize a db";
    }

    # Now everything is ready to be able to install prereqs based on the local
    # configuation.
    my $config = $oscar_configurator->get_config();
    my $prereq_mode = $config->{'prereq_mode'};
    require OSCAR::Bootstrap;
    my $prereq_cmd = $config->{'binaries_path'} . "/install_prereq";
    OSCAR::Bootstrap::install_prereq ($prereq_cmd,
                                      dirname($dest),
                                      $prereq_mode);

    # Now we can really initialize the database, eventhing is ready.
    my $oda_type = $config->{'oda_type'};
    if ($oda_type eq "db") {
        if (init_db($oscar_configurator)) {
            carp "ERROR: Impossible to initialize ODA (type=db)\n";
            return -1;
        }
    } elsif ($oda_type eq "file") {
        if (init_file_db ()) {
            carp "ERROR: Impossible to initialize ODA (type=file)\n";
            return -1;
        }
    } else {
        carp "ERROR: Unknown ODA type ($oda_type)\n";
        return -1;
    }
    
    # We start the database daemon
    require OSCAR::SystemServices;
    require OSCAR::SystemServicesDefs;
    if ($option eq "mysql") {
        OSCAR::SystemServices::system_service (OSCAR::SystemServicesDefs::MYSQL(),
            OSCAR::SystemServicesDefs::RESTART());
    } else {
        OSCAR::SystemServices::system_service (OSCAR::SystemServicesDefs::POSTGRESQL(),
            OSCAR::SystemServicesDefs::RESTART());
    }
    
    return 0;
}


1;
