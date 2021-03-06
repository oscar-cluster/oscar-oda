package OSCAR::Database;

#   This program is free software; you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation; either version 2 of the License, or
#   (at your option) any later version.

#   This program is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.

#   You should have received a copy of the GNU General Public License
#   along with this program; if not, write to the Free Software
#   Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

# Copyright (c) 2003, The Board of Trustees of the University of Illinois.
#                     All rights reserved.
#
# Copyright (c) 2005-2007 The Trustees of Indiana University.  
#                    All rights reserved.
# 
# Copyright (c) 2005 Bernard Li <bli@bcgsc.ca>
#
# Copyright (c) 2006 Erich Focht <efocht@hpce.nec.com>
#

#
# $Id$
#

# This is a new version of ODA

# Database.pm, located at the next level of the ODA hierarchy, is an
# abstract Perl module to handle directly all the database operations
# under the control of oda.pm. Many Perl subroutines defined at
# Database.pm are exported so that non-database codes of OSCAR can use
# its subroutines as if they are defined by importing Database.pm


####  OSCAR TABLES  ####
#
# Clusters
# Groups
# Status
# Packages
# Images
# Nodes
# OscarFileServer
# Networks
# Nics
# Packages_servicelists
# Packages_switcher
# Packages_config
# Node_Package_Status
# Group_Nodes
# Group_Packages
# Image_Package_Status
#
########################

BEGIN {
    if (defined $ENV{OSCAR_HOME}) {
        unshift @INC, "$ENV{OSCAR_HOME}/lib";
    }
}

use strict;
use Carp;
use vars qw(@EXPORT $VERSION);
use base qw(Exporter);
use OSCAR::PackagePath;
use OSCAR::Database_generic;
use OSCAR::oda;
use OSCAR::Distro;
use OSCAR::Utils;
use OSCAR::Logger;
use OSCAR::LoggerDefs;
use OSCAR::ConfigManager;
use OSCAR::ODA_Defs;
use OSCAR::SystemServices;
use OSCAR::SystemServicesDefs;
use OSCAR::OCA::OS_Settings;
use OSCAR::Utils;
use Data::Dumper;

# oda may or may not be installed and initialized
my $oda_available = 0;
my %options = ();
my @error_strings = ();
my $options_ref = \%options;
my $database_connected = 0;
my $CLUSTER_NAME = "oscar";
my $DEFAULT = "Default";
my $OSCAR_SERVER = "oscar-server";

my $verbose = $ENV{OSCAR_VERBOSE};

$options{debug} = 1 
    if (exists $ENV{OSCAR_VERBOSE} && $ENV{OSCAR_VERBOSE} == 10)
        || $ENV{OSCAR_DB_DEBUG};

@EXPORT = qw(
              create_database
              create_database_tables
              database_connect
              database_disconnect
              start_database_service

              delete_package
              delete_node
              delete_group_packages
              delete_groups
              del_pkgconfig_vars
              get_client_nodes
              get_client_nodes_info
              get_cluster_info_with_name
              get_gateway
              get_group_packages
              get_group_packages_with_groupname
              get_groups
              get_groups_for_packages
              get_headnode_iface
              get_image_info_with_name
              get_image_package_status_with_image
              get_image_package_status_with_image_package
              get_install_mode
              get_installable_packages
              get_manage_status
              get_networks
              get_nics_info_with_node
              get_nics_with_name_node
              get_nodes
              get_node_info_with_name
              get_node_package_status_with_group_node
              get_node_package_status_with_node
              get_node_package_status_with_node_package
              get_package_info_with_name
              get_packages
              get_packages_servicelists
              get_pkgconfig_vars
              get_selected_group
              get_selected_group_packages
              get_selected_packages
              get_status_name
              get_status_num
              get_pkg_status_num
              get_unselected_group_packages
              get_unselected_packages
              get_wizard_status
              insert_opkgs
              insert_packages
              insert_pkg_rpmlist
              is_installed_on_node
              link_node_nic_to_network
              list_selected_packages
              pkgs_of_opkg
              pkgconfig_values
              set_all_groups
              set_group_packages
              set_group_nodes
              set_groups
              set_groups_selected
              set_images
              set_image_packages
              set_install_mode
              set_manage_status
              set_nics_with_node
              set_node_with_group
              set_pkgconfig_var
              set_status
              set_wizard_status
              translate_fields
              update_image_package_status_hash
              update_image_package_status
              update_node
              update_node_package_status_hash
              update_node_package_status
              update_packages

              dec_already_locked
              locking
              unlock
              single_dec_locked

              simple_oda_query
              oda_query_single_result
              set_opkgs_selection_data
              get_opkgs_selection_data
              get_selected_opkgs
	      );

######################################################################
#
#       Database Connection subroutines
#
######################################################################

################################################################################
# Connect to the oscar database if the oda package has been installed and the  #
# oscar database has been initialized.                                         #
# This function is not needed before executing any ODA database functions,     #
# since they automatically connect to the database if needed, but it is more   #
# effecient to call this function at the start of your program and leave the   #
# database connected throughout the execution of your program.                 #
#                                                                              #
# Inputs:   errors_ref     if defined and a list reference,                    #
#                          put error messages into the list;                   #
#                          if defined and a non-zero scalar,                   #
#                          print out error messages on STDERR.                 #
#           options        options reference to oda options hash.              #
# Outputs:  status         non-zero if success.                                #
################################################################################
sub database_connect ($$) {
    my ( $passed_options_ref,
         $passed_errors_ref ) = @_;

    oscar_log_section (">$0: Connecting to the database...");
    # We get the configuration from the OSCAR configuration file.
    my $oscar_configurator = OSCAR::ConfigManager->new();
    if ( ! defined ($oscar_configurator) ) {
        print "ERROR: Impossible to get the OSCAR configuration\n";
        exit 1;
    }
    my $config = $oscar_configurator->get_config();

    if ($config->{oda_type} ne "db") {
        oscar_log_subsection (">$0: Not using a real database, connection done");
        return 1;
    }
    # take care of faking any non-passed input parameters, and
    # set any options to their default values if not already set
    my ( $options_ref, $error_strings_ref ) = fake_missing_parameters
        ( $passed_options_ref, $passed_errors_ref );

    if ( $$options_ref{debug} ) {
    my ($package, $filename, $line) = caller;
        oscar_log_subsection (">$0:\n".
            "====> in Database\:\:connect called from package = ".
            "$package $filename\:$line\n");
    }

    # if the database is not already available, ...
    if ( ! $database_connected ) {

        # if oda was not installed the last time that 
        # this was called, try to load in the module again
        if ( ! $oda_available ) {
            eval "use OSCAR::oda";
            $oda_available = ! $@;
            carp("in database_connect cannot use oda: $@") if ! $oda_available;
        }
        oscar_log_subsection (">$0:\n====> in Database::database_connect now oda_available=$oda_available\n")
            if $$options_ref{debug};

        # assuming oda is available now, ...
        if ( $oda_available ) {
            # try to connect to the database
            if ( OSCAR::oda::oda_connect( $options_ref,
                       $error_strings_ref ) ) {
                oscar_log_subsection (">$0:\n".
                    "====> in Database::database_connect connect worked\n") 
                    if $$options_ref{debug};
                $database_connected = 1;
            }
            print_error_strings($error_strings_ref);
        }
    }

    oscar_log_subsection (">$0:\n".
        "====> in Database::database_connect returning database_connected = ".
        "$database_connected\n")
        if $$options_ref{debug};
    oscar_log_subsection (">$0: Database connection done");
    return $database_connected;
}

#
# Disconnect database connection. This is done through the
# oda_disconnect in OSCAR::oda.pm
#
# inputs:   errors_ref   if defined and a list reference,
#                          put error messages into the list;
#                          if defined and a non-zero scalar,
#                          print out error messages on STDERR
#           options        options reference to oda options hash
# outputs:  status         non-zero if success

sub database_disconnect ($$) {
    my ( $passed_options_ref, 
         $passed_errors_ref ) = @_;

    # take care of faking any non-passed input parameters, and
    # set any options to their default values if not already set
    my ( $options_ref, $error_strings_ref ) = fake_missing_parameters
        ( $passed_options_ref, $passed_errors_ref );

    if ( $$options_ref{debug} ) {
    my ($package, $filename, $line) = caller;
        print "DB_DEBUG>$0:\n====> in Database\:\:disconnect called from package=$package $filename\:$line\n";
    }

    # if the database is not connected, done
    return 1 if ! $database_connected;

    # disconnect from the database
    OSCAR::oda::oda_disconnect( $options_ref, $error_strings_ref );
    $database_connected = 0;

    print_error_strings($error_strings_ref);

    return 1;
}




#########################################################################
#  Subroutine: list_selected_packages                                   #
#  Returns   : A list of packages selected for installation.            #
#                                                                       #
#  Usage: @packages_that_are_selected = list_selected_packages();       #
#  Return: an array of OPKGs' names, undef else.
#########################################################################
sub list_selected_packages () {
    my $sql = "SELECT * FROM Group_Packages WHERE group_name='oscar_server'";
    my @res = ();
    if (OSCAR::Database_generic::do_select ($sql, \@res, undef, undef) == 0) {
        carp "ERROR: Impossible to query Group_Packages ($sql)\n";
        return undef;
    }
    my @selected_opkgs;
    foreach my $ref (@res){
        my $opkg = $$ref{package};
        my $cur_selection = $$ref{selected};
        if ($cur_selection eq OSCAR::ODA_Defs::SELECTED()) {
            push (@selected_opkgs, $opkg);
        }
    }

    return @selected_opkgs;
}

######################################################################
#
#       Select SQL query: database subroutines
#
######################################################################


sub get_node_info_with_name {
    my ($node_name,
        $options_ref,
        $error_strings_ref) = @_;
    my @results = ();
    my $sql = "SELECT * FROM Nodes WHERE name='$node_name'";
    print "DB_DEBUG>$0:\n====> in Database::get_node_info_with_name SQL : $sql\n" if $$options_ref{debug};
    if(do_select($sql,\@results, $options_ref, $error_strings_ref)) {
        my $node_ref = pop @results;
        return $node_ref;
    } else {
        undef;
    }
}

sub get_client_nodes {
    my ($results_ref,
        $options_ref,
        $error_strings_ref) = @_;
    my $sql = "SELECT Nodes.* FROM Nodes ".
            "WHERE group_name='oscar_clients'";
    print "DB_DEBUG>$0:\n====> in Database::get_client_nodes SQL : $sql\n" if $$options_ref{debug};
    return do_select($sql, $results_ref, $options_ref, $error_strings_ref);
}

sub get_nodes {
    my ($results_ref,
        $options_ref,
        $error_strings_ref) = @_;
    my $sql = "SELECT * FROM Nodes";
    print "DB_DEBUG>$0:\n====> in Database::get_nodes SQL : $sql\n" if $$options_ref{debug};
    return do_select($sql, $results_ref, $options_ref, $error_strings_ref);
}

sub get_client_nodes_info {
    my ($server,
        $results_ref,
        $options_ref,
        $error_strings_ref) = @_;
    my $sql = "SELECT * FROM Nodes WHERE name!='$server'";
    print "DB_DEBUG>$0:\n====> in Database::get_client_nodes_info SQL : $sql\n" if $$options_ref{debug};
    return do_select($sql, $results_ref, $options_ref, $error_strings_ref);
}


sub get_networks {
    my ($results,
        $options_ref,
        $error_strings_ref)= @_;
    my $sql ="SELECT * FROM Networks ";
    print "DB_DEBUG>$0:\n====> in Database::get_networks SQL : $sql\n" if $$options_ref{debug};
    return do_select($sql, $results, $options_ref, $error_strings_ref);
}

# Return: 1 if success, 0 else.
sub get_nics_info_with_node {
    my ($node,
        $results,
        $options_ref,
        $error_strings_ref)= @_;
    my $sql ="SELECT Nics.* FROM Nics, Nodes ".
             "WHERE Nodes.id=Nics.node_id AND Nodes.name='$node'";
    print "DB_DEBUG>$0:\n====> in Database::get_nics_info_with_node SQL : $sql\n" if $$options_ref{debug};
    return do_select($sql, $results, $options_ref, $error_strings_ref);
}

################################################################################
# Return NICs information for a given node (identified by its name).           #
#                                                                              #
# Input: nic, network interface we are looking for (e.g., "eth0").(optional)   #
#        node, node name for which we want to get NICs information (e.g.,      #
#              oscar_server). Note for here, we know for instance we want      #
#              info about eth0 on oscar_server.                                #
#        results, reference to a table of hash(es) that represents the result. #
#        options_ref, ???.                                                     #
#        error_strings_ref, reference to a hash that gives error handling      #
#                           options.                                           #
# Return: 0 if success, -1 else.                                               #
#                                                                              #
# TODO: specify the format of the hash used for "results".                     #
#       Is it a hash with the following keys? (ip, broadcast, net)?
# TODO: specify the interest of "options_ref".                                 #
# TODO: specify the format of the "error_string_ref" hash.                     #
#                                                                              #
# NOTE: why do we need to save that into the database?                         #
################################################################################
sub get_nics_with_name_node {
    my ($nic,
        $node,
        $results,
        $options_ref,
        $error_strings_ref)= @_;

    # We get the configuration from the OSCAR configuration file.
    my $oscar_configurator = OSCAR::ConfigManager->new();
    if ( ! defined ($oscar_configurator) ) {
        carp "ERROR: Impossible to get the OSCAR configuration\n";
        return -1;
    }
    my $config = $oscar_configurator->get_config();

    if ($config->{oda_type} eq "file") {
        require OSCAR::Network;
        my ($ip, $broadcast, $net) = OSCAR::Network::interface2ip ($nic);
        if (!defined $ip || !defined $broadcast || !defined $net) {
            carp "ERROR: Invalid NIC info";
            return -1;
        }
        $results = { 'ip' => $ip,
                     'broadcast' => $broadcast,
                     'net' => $net};
    } elsif ($config->{oda_type} eq "db") {
        my $sql ="SELECT Nics.* FROM Nics, Nodes ".
                "WHERE Nodes.id=Nics.node_id AND Nodes.name='$node'";
	if(defined($nic)) {
                $sql .= " AND Nics.name='$nic'";
	}
        print "DB_DEBUG>$0:\n====> in Database::get_nics_with_name_node SQL :".
              " $sql\n" if $$options_ref{debug};
        my $rc = do_select($sql,$results, $options_ref, $error_strings_ref);
        if ($rc == 0) {
            carp "ERROR: Impossible to get the data about $node/$nic";
            return -1;
        }
    } else {
        carp "ERROR: Unknow ODA mode ($config->{oda_type})";
        return -1;
    }
    return 0;
}

sub get_cluster_info_with_name {
    my ($cluster_name,
        $options_ref,
        $error_strings_ref) = @_;
    my @results = ();
    my $where = ($cluster_name?"'$cluster_name'":"'oscar'");
    my $sql = "SELECT * FROM Clusters WHERE name=$where";
    print "DB_DEBUG>$0:\n====> in Database::get_cluster_info_with_name SQL : $sql\n" if $$options_ref{debug};
    do_select($sql,\@results, $options_ref, $error_strings_ref);
    if(@results) {
        return ((scalar @results)==1?(pop @results):@results);
    } else {
        return undef;
    }
}


################################################################################
# Get information from the database for all available OPKGs.                   #
# This is a generalisation of all other get_packages calls. It can             #
# replace all of them and make the calls more readable.                        #
#                                                                              #
# Usage:                                                                       #
#   get_packages(\@res,\%opts, $err, class => "core", distro => $distro);      #
#   get_packages(\@res,\%opts, $err, version => $ver, distro => $distro);      #
#   get_packages(\@res,\%opts, $err, package => $name, version => $ver,        #
#                distro => $distro);                                           #
# etc...                                                                       #
# The selectors all add up and invoked with AND between them.                  #
#                                                                              #
# Input: results_ref,                                                          #
#        options_ref,                                                          #
#        error_strings_ref,                                                    #
#        sel, hash specifying querying options (can be undef if no option).    #
# Return: 1 if success, 0 else.                                                #
################################################################################
sub get_packages {
    my ($results_ref,
        $options_ref,
        $error_strings_ref,
        %sel) = @_;

    # We get the configuration from the OSCAR configuration file.
    my $oscar_configurator = OSCAR::ConfigManager->new();
    if ( ! defined ($oscar_configurator) ) {
        carp "ERROR: Impossible to get the OSCAR configuration\n";
        return 1;
    }
    my $config = $oscar_configurator->get_config();

    if ($config->{oda_type} eq "db") {
        my $sql = "SELECT * FROM Packages";
        if (defined($sel{class})) {
            $sel{__class} = $sel{class};
            delete $sel{class};
        }
        if (defined($sel{group})) {
            $sel{__group} = $sel{group};
            delete $sel{group};
        }
        my @where = map { "$_=\'$sel{$_}\'" } keys(%sel);
        if (scalar(@where) > 0) {
            $sql .= " WHERE ";
            $sql .= join(" AND ", @where);
        }
        oscar_log_subsection (">$0:\n".
            "====> in Database::get_packagess SQL : $sql\n")
            if $$options_ref{debug};
        return do_select($sql,$results_ref, $options_ref, $error_strings_ref);
    } elsif ($config->{oda_type} eq "file") {
        oscar_log_subsection (">$0:\n".
            "====> getting OPKGs info from configuration file\n")
            if $$options_ref{debug};
        carp "ERROR: not yet implemented ($0)\n";
        return 0;
    } else {
        carp "ERROR: Unknown database type ($config->{oda_type})";
        return 0;
    }
}

sub get_package_info_with_name {
    my ($opkg, $options_ref, $errors_ref, $ver) = @_;

    carp "WARNING: The call of get_package_info_with_name is deprecated!\n".
    "         Please work on removing it!\n".
    "On multi-distro clusters the result may be wrong!\n";
    my $os = &OSCAR::PackagePath::distro_detect_or_die();
    my $dist = &OSCAR::PackagePath::os_cdistro_string($os);
    my @results;
    my %sel = ( package => $opkg , distro => $dist );
    $sel{version} = $ver if ($ver);
    &get_packages(\@results, $options_ref, $errors_ref, %sel);
    my $p_ref;
    if (@results) {
    $p_ref = pop(@results);
    }
    return $p_ref;
}

# This is called only by "DelNode.pm" and if group_name is not specified,
# it will assume that you are querying for all the client nodes because we
# can not remove oscar_server node here.
# As Bernard suggested, this should query from installed packages.
# The extra condition to check to see if a package is installed or not
# is added.
sub get_packages_servicelists ($$$$) {
    my ($results_ref,
        $group_name,
        $options_ref,
        $error_strings_ref) = @_;
    my $sql = "SELECT distinct P.package, S.service " .
              "FROM Packages P, Packages_servicelists S, ".
              "Node_Package_Status N, Group_Nodes G " .
              "WHERE P.package=S.package AND N.package=S.package ".
              "AND G.node_id=N.node_id AND N.requested=8 ";
    $sql .= ($group_name?
        " AND G.group_name='$group_name' AND S.group_name='$group_name'":
        " AND S.group_name!='$OSCAR_SERVER'");
    print "DB_DEBUG>$0:\n====> in Database::get_packages_servicelists SQL : $sql\n" if $$options_ref{debug};
    return do_select($sql,$results_ref,$options_ref,$error_strings_ref);
}

sub get_selected_group ($$) {
    my ($options_ref,
        $error_strings_ref) = @_;
    my $sql = "SELECT id, name From Groups " .
              "WHERE selected=1 ";
    my @results = ();
    print "DB_DEBUG>$0:\n====> in Database::get_selected_group SQL : $sql\n" if $$options_ref{debug};
    my $success = do_select($sql,\@results,$options_ref,$error_strings_ref);
    my $answer = undef;
    if ($success){
        my $ref = pop @results;
        $answer = $$ref{name};
    }
    return $answer;
}

# Return 1 if success, anything else if error
sub get_selected_group_packages ($$$$$) {
    my ($results_ref,
        $options_ref,
        $error_strings_ref,
        $group,
        $flag) = @_;
#     $group = get_selected_group($options_ref,$error_strings_ref) if(!$group);
#     print STDERR $group;
    $flag = OSCAR::ODA_Defs::SELECTED() if(! $flag);
#     my $sql = "SELECT Group_Packages.package " .
#               "From Group_Packages, Groups " .
#               "WHERE Group_Packages.group_name=Groups.name ".
#               "AND Groups.name='$group' ".
#               "AND Groups.selected=1 ".
#               "AND Group_Packages.selected=$flag";
    my $sql = "SELECT Group_Packages.package ".
              "FROM Group_Packages ".
              "WHERE Group_Packages.selected=$flag";
    print "DB_DEBUG>$0:\n====> in Database::get_selected_group_packages SQL : $sql\n" if $$options_ref{debug};
    return do_select($sql,$results_ref,$options_ref,$error_strings_ref);
}

sub get_unselected_group_packages ($$$$) {
    my ($results_ref,
        $options_ref,
        $error_strings_ref,
        $group) = @_;
    return get_selected_group_packages($results_ref,$options_ref,
                                       $error_strings_ref,$group,0);
}

#
# Return selected packages in a group
#
sub get_group_packages ($$$$) {
    my ($group,
        $results_ref,
        $options_ref,
        $errors_ref) = @_;
    my $sql = "SELECT package FROM Group_Packages " .
              "WHERE group_name='$group' ".
              "AND selected=1";
    print "DB_DEBUG>$0:\n====> in Database::get_group_packages ".
    "SQL : $sql\n" if $$options_ref{debug};
    return &do_select($sql, $results_ref, $options_ref, $errors_ref);
}

# Get the list of packages to install at the step "PackageInUn".
# This subroutine checks the flag "selected" and get the list of
# packages from the table "Node_Package_Status" where the "selected"
# flag is 2.

# Flag : see the ODA_Defs.pm file.
sub get_selected_packages ($$$$) {
    my ($results,
        $options_ref,
        $error_strings_ref,
        $node_name) = @_;

    $node_name = $OSCAR_SERVER if (!$node_name);

    my $sql = "SELECT Node_Package_Status.* " .
             "From Node_Package_Status, Nodes ".
             "WHERE Node_Package_Status.node_id=Nodes.id ".
             "AND Node_Package_Status.selected=".SELECTED()." ".
             "AND Nodes.name='$node_name'";
    print "DB_DEBUG>$0:\n====> in Database::is_installed_on_node SQL : $sql\n" if $$options_ref{debug};
    return do_select($sql,$results, $options_ref, $error_strings_ref);
}

# Get the list of packages to uninstall at the step "PackageInUn".
# This subroutine checks the flag "selected" and get the list of
# packages from the table "Node_Package_Status" where the "selected"
# flag is 1.

# Flag : see the ODA_Defs.pm file.
sub get_unselected_packages ($$$$) {
    my ($results,
        $options_ref,
        $error_strings_ref,
        $node_name) = @_;

    $node_name = $OSCAR_SERVER if (!$node_name);

    my $sql = "SELECT Node_Package_Status.* " .
             "From Node_Package_Status, Nodes ".
             "WHERE Node_Package_Status.node_id=Nodes.id ".
             "AND Node_Package_Status.selected=".UNSELECTED()." ".
             "AND Nodes.name='$node_name'";
    print "DB_DEBUG>$0:\n====> in Database::is_installed_on_node SQL : $sql\n" if $$options_ref{debug};
    return do_select($sql,$results, $options_ref, $error_strings_ref);
}

sub get_group_packages_with_groupname ($$$$) {
    my ($group,
        $results_ref,
        $options_ref,
        $error_strings_ref) = @_;
    my $sql = "SELECT package " .
              "From Group_Packages " .
              "WHERE Group_Packages.group_name='$group'";
    print "DB_DEBUG>$0:\n====> in Database::get_group_packages_with_groupname SQL : $sql\n" if $$options_ref{debug};
    return do_select($sql,$results_ref,$options_ref,$error_strings_ref);
}

sub get_node_package_status_with_group_node ($$$$$) {
    my ($group,
        $node,
        $results,
        $options_ref,
        $error_strings_ref) = @_;
        my $sql = "SELECT Node_Package_Status.* " .
                 "From Group_Packages, Node_Package_Status, Nodes ".
                 "WHERE Group_Packages.group_name='$group' ".
                 "AND Node_Package_Status.package=Group_Packages.package ".
                 "AND Node_Package_Status.node_id=Nodes.id ".
                 "AND Nodes.name='$node'";
    print "DB_DEBUG>$0:\n====> in Database::get_node_package_status_with_group_node SQL : $sql\n" if $$options_ref{debug};
    return do_select($sql, $results, $options_ref, $error_strings_ref);
}

sub get_node_package_status_with_node ($$$$$) {
    my ($node,
        $results,
        $options_ref,
        $error_strings_ref,
        $requested) = @_;
    my $sql = "SELECT Node_Package_Status.* " .
              "From Node_Package_Status, Nodes ".
              "WHERE Node_Package_Status.node_id=Nodes.id ".
              "AND Nodes.name='$node'";
    if (defined $requested && $requested ne "") {
        $sql .= " AND Node_Package_Status.requested=$requested ";
    }
    print "DB_DEBUG>$0:\n====> in Database::get_node_package_status_with_node SQL : $sql\n" if $$options_ref{debug};
    return do_select($sql,$results, $options_ref, $error_strings_ref);
}

sub get_node_package_status_with_node_package {
    my ($node,
        $package,
        $results,
        $options_ref,
        $error_strings_ref,
        $requested,
        $version) = @_;
    my $sql = "SELECT Node_Package_Status.* " .
              "From Node_Package_Status, Nodes ".
              "WHERE Node_Package_Status.package='$package' ".
              "AND Node_Package_Status.node_id=Nodes.id ".
              "AND Nodes.name='$node'";
    if(defined $requested && $requested ne ""){
        $sql .= " AND Node_Package_Status.requested=$requested ";
    }
    print "DB_DEBUG>$0:\n====> in ". 
        "Database::get_node_package_status_with_node_package SQL : $sql\n" 
        if $$options_ref{debug};
    return do_select($sql, $results, $options_ref, $error_strings_ref);
}

# TODO: code duplication with get_node_package_status_with_node_package, we
# should avoid that.
sub get_image_package_status_with_image ($$$$$$) {
    my ($image,
        $package,
        $results,
        $options_ref,
        $error_ref,
        $requested) = @_;
    my $sql = "SELECT Image_Package_Status.* " .
              "FROM Image_Package_Status, Images ".
              "WHERE Image_Package_Status.package='$package' ".
              "AND Image_Package_Status.image_id=Nodes.id ".
              "AND Images.name='$image'";
    if(defined $requested && $requested ne ""){
        $sql .= " AND Image_Package_Status.requested=$requested ";
    }
    print "DB_DEBUG>$0:\n====> in ".
          "Database::get_node_package_status_with_node_package SQL : $sql\n"
          if $$options_ref{debug};
    return do_select($sql,$results, $options_ref, $error_ref);
}


# sub get_image_package_status_with_image {
#     my ($image,
#         $results,
#         $options_ref,
#         $error_strings_ref,
#         $requested,
#         $version) = @_;
#         my $sql = "SELECT Packages.package, Image_Package_Status.* " .
#                  "From Packages, Image_Package_Status, Images ".
#                  "WHERE Node_Package_Status.package_id=Packages.id ".
#                  "AND Image_Package_Status.image_id=Images.id ".
#                  "AND Images.name='$image'";
#         if (defined $requested && $requested ne "") {
#             $sql .= " AND Image_Package_Status.requested=$requested ";
#         }
#         if (defined $version && $version ne "") {
#             $sql .= " AND Packages.version=$version ";
#         }
#     print "DB_DEBUG>$0:\n====> in Database::get_image_package_status_with_image SQL : $sql\n" if $$options_ref{debug};
#     return do_select($sql,$results, $options_ref, $error_strings_ref);
# }

sub get_image_package_status_with_image_package ($$$$$$) {
    my ($image,
        $package,
        $results,
        $options_ref,
        $error_ref,
        $requested) = @_;
    my $sql = "SELECT Images_Package_Status.* " .
              "From Image_Package_Status, Images ".
              "WHERE Image_Package_Status.package='$package' ".
              "AND Image_Package_Status.image_id=Images.id ".
              "AND Imagse.name='$image'";
    if(defined $requested && $requested ne ""){
        $sql .= " AND Image_Package_Status.requested=$requested ";
    }
    print "DB_DEBUG>$0:\n====> in ".
        "Database::get_image_package_status_with_image_package SQL : $sql\n" 
        if $$options_ref{debug};
    return do_select($sql, $results, $options_ref, $error_ref);
}

sub get_installable_packages ($$$) {
    my ($results,
        $options_ref,
        $error_ref) = @_;
    my $sql = "SELECT Packages.id, Packages.package " .
              "FROM Packages, Group_Packages " .
              "WHERE Packages.id=Group_Packages.package_id ".
              "AND Group_Packages.group_name='Default'";
    print "DB_DEBUG>$0:\n====> in Database::get_installable_packages SQL : $sql\n" if $$options_ref{debug};
    return do_select($sql,$results, $options_ref, $error_ref);
}


sub get_groups_for_packages ($$$$) {
    my ($results,
        $options_ref,
        $error_strings_ref,
        $group)= @_;
    my $sql ="SELECT distinct group_name FROM Group_Packages ";
    if(defined $group) {
        $sql .= "WHERE group_name='$group'";
    }
    print "DB_DEBUG>$0:\n".
        "====> in Database::get_groups_for_packages SQL : $sql\n" 
        if $$options_ref{debug};
    return do_select($sql,$results, $options_ref, $error_strings_ref);
}

################################################################################
# Get the group data based on a group name.                                    #
# Input: - results, reference to the result hash.                              #
#        - options_ref, reference to the option hash (???).                    #
#        - error_string_ref, reference to the string to personnalize debugging #
#                            output.                                           #
#        - group, group name.                                                  #
# Return: reference to the result hash if success, undef else.                 #
################################################################################
sub get_groups ($$$$) {
    my ($results,
        $options_ref,
        $error_strings_ref,
        $group)= @_;
    my $sql ="SELECT * FROM Groups ";
    if(defined $group) {
        $sql .= "WHERE name='$group'";
    }
    print "DB_DEBUG>$0:\n====> in Database::get_groups SQL : $sql\n" 
        if $$options_ref{debug};
    die "DB_DEBUG>$0:\n====>Failed to query values via << $sql >>"
        if! do_select($sql,$results, $options_ref, $error_strings_ref);
    return $$results[0] if $group;
    return undef;
}

###############################################################################
# Get image information from the database.                                    #
# Public function.                                                            #
# Input: image, image's name.                                                 #
#        options_ref, option(??). This is optional, it can be empty.          #
#        error, array (???). This can be empty.                               #
# Return: ???.                                                                #
###############################################################################
sub get_image_info_with_name ($$$) {
    my ($image,
        $options_ref,
        $error_strings_ref) = @_;
    print "DB_DEBUG>$0: Getting information about the image ".
        "($image)...\n"
        if $$options_ref{debug} ;
    my $sql = "SELECT * FROM Images WHERE Images.name='$image'";
    print "DB_DEBUG>$0:\n".
          "====> in Database::get_image_info_with_name SQL : $sql\n"
          if $$options_ref{debug};
    my @images = ();
    die "DB_DEBUG>$0:\n====>Failed to query values via << $sql >>"
        if! do_select($sql,\@images, $options_ref, $error_strings_ref);
    print "Success...\n"
        if $$options_ref{debug} ;
    return (@images?pop @images:undef);
}

sub get_gateway ($$$$$) {
    my ($node,
        $interface,
        $results,
        $options_ref,
        $error_strings_ref)= @_;
    my $sql ="SELECT Networks.gateway FROM Networks, Nics, Nodes ".
             "WHERE Nodes.id=Nics.node_id AND Nodes.name='$node'".
             "AND Networks.n_id=Nics.network_id AND Nics.name='$interface'";
    print "DB_DEBUG>$0:\n====> in Database::get_gateway SQL : $sql\n"
        if $$options_ref{debug};
    return do_select($sql,$results, $options_ref, $error_strings_ref);
}

################################################################################
# This function returns the interface on the headnode that is on the same      #
# network as the compute nodes, typically = ./install_cluster <iface>          #
#                                                                              #
# Input: options_ref, optional - specify options for the query.                #
#        error_string_ref, optional - string display in front of each error    #
#                          msg.                                                #
# Return: the network interface id if success (e.g. "eth0"), undef else.       #
################################################################################
sub get_headnode_iface ($$) {
    my ($options_ref, $error_strings_ref) = @_;

    # We get the configuration from the OSCAR configuration file.
    my $oscar_configurator = OSCAR::ConfigManager->new();
    if ( ! defined ($oscar_configurator) ) {
        carp "ERROR: Impossible to get the OSCAR configuration\n";
        return undef;
    }
    my $config = $oscar_configurator->get_config();

    if ($config->{oda_type} eq "file") {
        return $config->{nioscar};
    } elsif ($config->{oda_type} eq "db") {
        my $cluster_ref = get_cluster_info_with_name("oscar",
                                                     $options_ref,
                                                     $error_strings_ref);
        return $$cluster_ref{headnode_interface};
    } else {
        carp "ERROR: Unknow ODA mode ($config->{oda_type})";
        return undef;
    }
}

# Retrieve installation mode for cluster
sub get_install_mode ($$) {
    my ($options_ref,
        $error_strings_ref) = @_;

    # We get the configuration from the OSCAR configuration file.
    my $oscar_configurator = OSCAR::ConfigManager->new();
    if ( ! defined ($oscar_configurator) ) {
        carp "ERROR: Impossible to get the OSCAR configuration\n";
        return undef;
    }
    my $config = $oscar_configurator->get_config();

    if ($config->{oda_type} eq "file") {
        # TODO: we currently return a fack value, we assume we use a basic 
        # installation mode
        return "systemimager-rsync";
    } elsif ($config->{oda_type} eq "db") {
        my $cluster = "oscar";

        my $cluster_ref = get_cluster_info_with_name($cluster, 
            $options_ref,
            $error_strings_ref);
        return $$cluster_ref{install_mode};
    } else {
        carp "ERROR: Unknown ODA mode ($config->{oda_type})";
    }
    return undef
}


# Return the wizard step status
sub get_wizard_status ($$) {
    my ($options_ref,
        $error_strings_ref) = @_;
    my $sql = "SELECT * FROM Wizard_status";
    my $sql_2 = "SELECT * FROM Images";
    my @results = ();
    my $success = do_select($sql,\@results,$options_ref,$error_strings_ref);
    my %wizard_status = ();
    if ($success){
        foreach my $ref (@results){
            $wizard_status{$$ref{step_name}} = $$ref{status};
        }
    }
    my @res = ();
    my $success_2 = do_select($sql_2,\@res,$options_ref,$error_strings_ref);
    if ($success_2 && @res){
        $wizard_status{"addclients"} = "normal";
        set_wizard_status("addclients",$options_ref,$error_strings_ref);
    }
    return \%wizard_status;
}

# Return the manage step status
sub get_manage_status ($$) {
    my ($options_ref,
        $error_strings_ref) = @_;
    my $sql = "SELECT * FROM Manage_status";
    my @results = ();
    my $success = do_select($sql,\@results,$options_ref,$error_strings_ref);
    my %manage_status = ();
    if ($success){
        foreach my $ref (@results){
            $manage_status{$$ref{step_name}} = $$ref{status};
        }
    }
    return \%manage_status;
}

# Initialize the "selected" field in the table "Node_Package_Status"
# to get the table "Node_Package_Status" ready for another "PackageInUn"
# process
sub initialize_selected_flag ($$) {
    my ($options_ref,
        $error_strings_ref) = @_;
    my $table = "Node_Package_Status";
    my %field_value_hash = ("selected" => 0);
    my $where = "";
    die "DB_DEBUG>$0:\n====>Failed to update the flag of selected"
        if(!update_table($options_ref,
                         $table,
                         \%field_value_hash,
                         $where,
                         $error_strings_ref));
}

# Input: selector, DEPRECATED OPTION
#
# TODO: Remove the selector input parameter.
sub is_installed_on_node ($$$$$$) {
    my ($package,
        $node_name,
        $options_ref,
        $error_strings_ref,
        $selector,
        $requested) = @_;
    my @result = ();
    $requested = 8 if (!$requested);
    my $sql = "SELECT Node_Package_Status.* " .
             "FROM Node_Package_Status, Nodes ".
             "WHERE Node_Package_Status.node_id=Nodes.id ".
             "AND Node_Package_Status.package='$package' ".
             "AND Nodes.name=";
    $sql .= ($node_name?"'$node_name'":"'$OSCAR_SERVER'"); 
    if(defined $requested && $requested ne ""){
        if($selector){
            $sql .= " AND Node_Package_Status.ex_status=$requested ";
        }else{
            $sql .= " AND Node_Package_Status.requested=$requested ";
        }
    }
    print "DB_DEBUG>$0:\n".
        "====> in Database::is_installed_on_node SQL : $sql\n"
        if $$options_ref{debug};
    die "DB_DEBUG>$0:\n====>Failed to query values via << $sql >>"
        if! do_select($sql,\@result, $options_ref, $error_strings_ref);
    return (@result?1:0);
}

######################################################################
#
#       Delete/Insert/Update SQL query: database subroutines
#
######################################################################

sub delete_group_node ($$$) {
    my ($node_id,
        $options_ref,
        $error_strings_ref) = @_;
    my $sql = "DELETE FROM Group_Nodes WHERE node_id=$node_id";
    print "DB_DEBUG>$0:\n====> in Database::delete_group_node SQL : $sql\n"
        if $$options_ref{debug};
    return do_update($sql,"Group_Nodes", $options_ref, $error_strings_ref);
}

# Deselect an opkg from a group.
# Somewhat misleading name...
#
# DEPRECATED??
sub delete_group_packages ($$$$) {
    my ($group,
        $opkg,
        $options_ref,
        $errors_ref) = @_;

    my $sql = "UPDATE Group_Packages SET selected=0 ".
        "WHERE group_name='$group' AND package='$opkg'";
    print "DB_DEBUG>$0:\n====> in Database::delete_group_packages SQL : $sql\n"
        if $$options_ref{debug};
    die "DB_DEBUG>$0:\n====>Failed to delete values via << $sql >>"
    if !&do_update($sql, "Group_Packages", $options_ref, $errors_ref);

    # Set "should_not_be_installed" to the package status    
    &update_node_package_status($options_ref, $OSCAR_SERVER, $opkg, 1,
                $errors_ref);
    return 1;
}

sub delete_groups ($$$) {
    my ($group,
        $options_ref,
        $error_strings_ref) = @_;
    my @results = ();
    get_groups(\@results,$options_ref,$error_strings_ref,$group);
    if(!@results){
        my $sql = "DELETE FROM Groups WHERE name='$group'";
        print "DB_DEBUG>$0:\n====> in Database::delete_groups SQL : $sql\n"
            if $$options_ref{debug};
        die "DB_DEBUG>$0:\n====>Failed to delete values via << $sql >>"
            if! do_update($sql,"Groups", $options_ref, $error_strings_ref);
    }
    return 1;
}

# TODO: extend this function to the case where we do not have a real db but
# configuration files.
sub delete_package ($$%) {
    my ($options_ref,
        $errors_ref,
        %sel) = @_;

    my $sql = "DELETE FROM Packages WHERE ";
    my @where = map { "$_=\'$sel{$_}\'" } keys(%sel);
    if (!scalar(@where)) {
        carp("WARNING: no selection criteria passed to delete_package");
        return undef;
    }
    $sql .= join(" AND ", @where);
    print "DB_DEBUG>$0:\n====> in Database::delete_package SQL : $sql\n"
        if $$options_ref{debug};
    return &do_update($sql, "Packages", $options_ref, $errors_ref);
}

sub delete_node ($$$) {
    my ($node_name,
        $options_ref,
        $error_strings_ref) = @_;

    my $node_ref = get_node_info_with_name($node_name,
                                           $options_ref,
                                           $error_strings_ref);
    my $node_id = $$node_ref{id};
    return 1 if !$node_id;

    delete_group_node($node_id, $options_ref, $error_strings_ref);
    delete_node_packages($node_id, $options_ref, $error_strings_ref);
    my $sql = "DELETE FROM Nodes ";
    print "DB_DEBUG>$0:\n====> in Database::delete_node SQL : $sql\n" 
        if $$options_ref{debug};
    $sql .= ($node_name?"WHERE name='$node_name'":"");
    return do_update($sql,"Nodes", $options_ref, $error_strings_ref);
}

sub delete_node_packages {
    my ($node_id,
        $options_ref,
        $error_ref) = @_;
    my $sql = "DELETE FROM Node_Package_Status WHERE node_id=$node_id";
    print "DB_DEBUG>$0:\n".
        "====> in Database::delete_node_package_status SQL : $sql\n" 
        if $$options_ref{debug};
    return do_update($sql, "Node_Package_Status", $options_ref, $error_ref);
}

################################################################################
# Translate some table fields name by token that are not reserved by           #
# databases.                                                                   #
# If a field name is "group", "__" should be added in front of $key to avoid   #
# the conflict of reserved keys.                                               #
#                                                                              #
# Input: table, name of the table for which we want to translate forbidden     #
#               field name (e.g., Packages).                                   #
# Return: a hash with the list of table's field, with the guarantee no         #
#         forbidden keywords are used; undef if error.                         #
#                                                                              #
# TODO: we should describe the returned hash, but right now i (GV) do not know #
#       yet what the hash looks like.                                          #
################################################################################
sub translate_fields ($) {
    my $table = shift;
    my %fields = ();
    my %table_fields_hash = ();

    OSCAR::oda::list_fields(\%options, "$table", \%fields, undef);
    my %packages_hash = %fields;
    foreach my $field (keys %packages_hash) {
        # Work around for many databases: __group and __class are reserved 
        # tokens
        if ($field eq "__group") { $field = "group"; }
        if ($field eq "__class") { $field = "class"; }
        $packages_hash{$field} = 1;
    }
    $table_fields_hash{"$table"} = \%packages_hash;

    return %table_fields_hash;
}

################################################################################
# This function aims at simplifying the insert_packages function, with the     #
# ultimate goal of providing a simpler API.                                    #
#                                                                              #
# Input: opkgs, a reference to a hash which has the following contents:        #
#               my %opkg = %{$o{$package}};                                    #
#               where $o is the hash of OpkgDB::opkg_hash_available and        #
#               $package is one the oscar package name. For an example,        #
#               please refer to the perldoc of this module.                    #
# Return: 0 if success, -1 else.                                               #
#                                                                              #
# TODO: do we want to have a "options" parameter?                              #
################################################################################
sub insert_opkgs ($) {
    my $opkgs_hash_ref = shift;
    my $table = "Packages";

    my %table_fields_hash = OSCAR::Database::translate_fields ($table);
    if (insert_packages ($opkgs_hash_ref,
                         $table,
                         \%table_fields_hash,
                         undef,
                         undef) == 0) {
        carp "ERROR: Impossible to include some packages";
        return -1;
    }
    return 0;
}

################################################################################
# This function includes given OSCAR Packages into the database.               #
#                                                                              #
# Input: passed_ref, a reference to a hash which has the following contents:   #
#                    my %opkg = %{$o{$package}};                               #
#                    where $o is the hash of OpkgDB::opkg_hash_available and   #
#                    $package is one the oscar package name. For an example,   #
#                    please refer to the perldoc of this module.               #
#        table_fields_ref, a reference to a hash gathering the list of table   #
#                          fields that need to be translated (typically        #
#                          __group and __class are reserved, we cannot use     #
#                          them).                                              #
# Return: 1 if success, 0 else.                                                #
#                                                                              #
# TODO: extend this function to the case where we do not have a real db but    #
#       configuration files.                                                   #
################################################################################
sub insert_packages ($$$$$) {
    my ($passed_ref, $table, $table_fields_ref,
        $passed_options_ref, $passed_errors_ref) = @_;

    # take care of faking any non-passed input parameters, and
    # set any options to their default values if not already set
    my ($options_ref, $errors_ref) = fake_missing_parameters (
        $passed_options_ref,
        $passed_errors_ref );
    my $sql = "INSERT INTO $table ( ";
    my $sql_values = " VALUES ( ";
    my $flag = 0;
    my $comma = "";
    foreach my $key (keys %$passed_ref) {

        if ($$table_fields_ref{$table}->{$key}
        && $key ne "package-specific-attribute") {
            $key = ( $key eq "group"?"__$key":$key);
            $key = ( $key eq "class"?"__$key":$key);
            $comma = ", " if $flag;
            $sql .= "$comma $key";
            $flag = 1;
            $key = ( $key eq "__group"?"group":$key);
            $key = ( $key eq "__class"?"class":$key);
            my $value;
            $value = ($passed_ref->{$key} ?
                trim($passed_ref->{$key}) : "");
            $value =~ s#'#\\'#g;
            $sql_values .= "$comma '$value'";
        }
    }
    $sql .= ") $sql_values )\n";

    my $debug_msg = "DB_DEBUG>$0:\n".
        "====> in Database::insert_packages SQL : $sql\n";
    print "$debug_msg" if $$options_ref{debug};
    push @$errors_ref, $debug_msg;

    print "DB_DEBUG>$0:\n====> in Database::insert_packages: ".
        "Inserting package(".$passed_ref->{package}.") into Packages\n"
        if $$options_ref{verbose};
    my $success = OSCAR::oda::do_sql_command($options_ref,
            $sql,
            "INSERT Table into $table",
            "Failed to insert values into $table table",
            $errors_ref);
    $errors_ref = \@error_strings;
    return  $success;
}

# links a node nic to a network in the database
#
sub link_node_nic_to_network ($$$$$) {

    my ($node_name,
        $nic_name,
        $network_name,
        $options_ref,
        $error_strings_ref) = @_;

    my $sql = "SELECT Nodes.id, Networks.n_id FROM Nodes, Networks WHERE ". 
        "Nodes.name='$node_name' AND Networks.name='$network_name' ";
    my @results = ();
    my @error_strings = ();
    OSCAR::oda::do_query(\%options,
                $sql,
                \@results,
                \@error_strings);
    my $res_ref = pop @results;
    my $node_id = $$res_ref{"id"};
    my $network_id = $$res_ref{"n_id"};
    my $command = "UPDATE Nics SET network_id=$network_id ".
        "WHERE name='$nic_name' AND node_id=$node_id ";
    print "DB_DEBUG>$0:\n".
        "====> in Database::link_node_nic_to_network linking node $node_name ".
        "nic $nic_name to network $network_name using command <$command>\n"
        if $$options_ref{debug};
    print "DB_DEBUG>$0:\n====> in Database::link_node_nic_to_network Linking node $node_name nic $nic_name to network $network_name.\n"
        if $$options_ref{verbose} && ! $$options_ref{debug};

    return do_update($command, "Nics", $options_ref, $error_strings_ref);
}


# Return: 1 if success, 0 else.
# TODO: this function has to been extended for the case where we do not use a
#       real db but configuration files.
sub update_node ($$$$) {
    my ($node,
        $field_value_ref,
        $options_ref,
        $error_strings_ref) = @_;
    my $sql = "UPDATE Nodes SET ";
    my $flag = 0;
    my $comma = "";
    while ( my($field,$value) = each %$field_value_ref ){
        $comma = "," if $flag;
        $sql .= "$comma $field='$value'";
        $flag = 1;
    }
    $sql .= " WHERE name='$node' ";
    print "DB_DEBUG>$0:\n====> in Database::update_node SQL : $sql\n" 
        if $$options_ref{debug};
    return  do_update($sql,"Nodes", $options_ref, $error_strings_ref);
}

# For normal oscar package installation, the possible values of  "requested"  #
# are defined in ODA_Defs.
#
# Input: passed_pkg, array of OPKGs name.
# Return: 1 is success, 0 else.
sub update_node_package_status ($$$$$$) {
    my ($options_ref,
        $node,
        $passed_pkg,
        $requested,
        $errors_ref,
        $selected) = @_;

    # By default, we assume the package should not be installed.
    $requested = SHOULD_NOT_BE_INSTALLED() if ! $requested;
    if (ref($passed_pkg) ne "ARRAY") {
        carp "ERROR: Invalid argument";
        return 0;
    }
    # If requested is one of the names of the fields being passed in, convert it
    # to the enum version instead of the string
    if($requested && $requested !~ /\d/) {
        $requested = get_status_num($options_ref, $requested, $errors_ref);
	}
    my $node_ref = get_node_info_with_name($node, $options_ref, $errors_ref);
    my $node_id = $$node_ref{id};
    foreach my $opkg (@$passed_pkg) {
        my %field_value_hash = ("requested" => $requested);
        if ($$options_ref{debug} || defined($ENV{DEBUG_OSCAR_WIZARD}) ) {
            print "DB_DEBUG>$0:\n====> in ".
                  "Database::update_node_package_status Updating the status of ".
                  "$opkg to \"";
            if ($requested == FINISHED()) {
                print "installed";
            } elsif ($requested == SHOULD_BE_INSTALLED()) {
                print "should be installed";
            } elsif ($requested == SHOULD_NOT_BE_INSTALLED()) {
                print "should not be installed";
            } else {
                print "... unknown status: ($requested)";
            }
            print "\".\n";
        }
        my @results = ();
        my $table = "Node_Package_Status";
        get_node_package_status_with_node_package($node,
                           $opkg,
                           \@results,
                           $options_ref,
                           $errors_ref);
        if (@results) {
            my $pstatus_ref = pop @results;
            my $ex_status = $$pstatus_ref{ex_status};
            $field_value_hash{requested} = $ex_status
                if($ex_status == FINISHED()
                    && $requested == SHOULD_BE_INSTALLED());
            $field_value_hash{ex_status} = $$pstatus_ref{requested};

            # If $requested is 8(finished), set the "ex_status" to 8
            # because setting "finished" to the "ex_status" prevents
            # package status from being updated incorrectly when a 
            # package is selected/unselected on Seletor.
            #
            # NOTE : the "selected" field is only for PackageInUn
            #
            $field_value_hash{ex_status} = $requested 
                if ($requested == FINISHED()
                    && $ex_status != SHOULD_BE_INSTALLED());
            $field_value_hash{selected} = $selected if ($selected);
            my $where = "WHERE node_id=$node_id AND package=\'$opkg\'";
            if (!&update_table($options_ref,
                                $table,
                                \%field_value_hash,
                                $where,
                                $errors_ref)) {
                die "DB_DEBUG>$0:\n".
                    "====>Failed to update the status of $opkg";
            }
        } else {
            %field_value_hash = ("node_id" => $node_id,
                                 "package" => $opkg,
                                 "requested" => $requested);
            if (!&insert_into_table ($options_ref,
                                     $table,
                                     \%field_value_hash,
                                     $errors_ref)) {
                die "DB_DEBUG>$0:\n".
                    "====>Failed to insert values into table $table";
            }
        }
    }
    return 1;
}



# Translates the string representation of a status to the enumerated numeric
# version stored in the database
sub get_status_num ($$$) {
	my ($options_ref,
		$status,
		$error_ref) = @_;
	
	# Get the internal id for a requested value from the status table
	my @field = ("id");
	my $where = "WHERE name=\'$status\'";
	my @result;
	select_table($options_ref, "Status", \@field, $where, \@result, $error_ref);
	my $status_id = $result[0]->{id};
	
	return $status_id;
}

# Translates the enumerated numeric representation of a status stored in the
# database to a string
sub get_status_name ($$$) {
	my ($options_ref,
		$status,
		$error_ref) = @_;
	
	# Get the internal id for a requested value from the status table
	my @field = ("name");
	my $where = "WHERE id=\'$status\'";
	my @result;
	select_table($options_ref, "Status", \@field, $where, \@result, $error_ref);
	my $status_name = $result[0]->{name};
	
	return $status_name;
}

# Translates the string representation of a package status to the enumerated
# numeric version stored in the database
sub get_pkg_status_num ($$$) {
	my ($options_ref,
		$status,
		$error_ref) = @_;
	
	# Get the internal id for a value from the package status table
	my @field = ("id");
	my $where = "WHERE status=\'$status\'";
	my @result;
	select_table($options_ref,
                "Package_status",
                \@field,
                $where,
                \@result,
                $error_ref);
	my $status_num = $result[0]->{id};
	
	return $status_num;
}

# Updates the status information for a package by passing in a hash
# The keys in the hash are the names of the database fields (requested, 
# current, status, etc.).  The values are the values that should be put
# into the database.
sub update_node_package_status_hash ($$$$$) {
	my ($options_ref,
		$node,
		$passed_pkg,
		$field_value_hash,
		$error_ref) = @_;
	my $packages;
	
	# Get the information passed in about a package
	if(ref($passed_pkg) eq "ARRAY") {
		$packages = $passed_pkg;
	} else {
		my %opkg = ();
		my @temp_packages = ();
		$opkg{package} = $passed_pkg;
		push @temp_packages, \%opkg;
		$packages = \@temp_packages;
	}
	
	# If requested is one of the names of the fields being passed in, convert it
	# to the enum version instead of the string
	if(exists $$field_value_hash{requested}) {
		$$field_value_hash{requested} = get_status_num($options_ref,
            $$field_value_hash{requested},
            $error_ref);
	}
	
	# If current is one of the names of the fields being passed in, convert it
	# to the enum version instead of the string
	if(exists $$field_value_hash{curr}) {
		$$field_value_hash{curr} = get_status_num($options_ref,
            $$field_value_hash{curr},
            $error_ref);
	}
	
	# If status is one of the names of the fields being passed in, convert it
	# to the enum version instead of the string
	if(exists $$field_value_hash{status}) {
		$$field_value_hash{status} = get_pkg_status_num($options_ref,
            $$field_value_hash{status},
            $error_ref);
	}
	
	# Get the internal id for the node
	my $node_ref = get_node_info_with_name($node,
        $options_ref,
        $error_ref);
	my $node_id = $$node_ref{id};
	
	# Get more information about the package
	foreach my $pkg_ref (@$packages) {
		my $opkg = $$pkg_ref{package};
		my $where = "WHERE package=\'$opkg\' AND node_id=$node_id";
		
		# Check to see if there is an entry in the table already
		my @field = ("package");
		my @result;
		select_table($options_ref,
            "Node_Package_Status",
            \@field,
            $where,
            \@result,
            $error_ref);
		if($result[0]->{package} && $result[0]->{package} == $opkg) {
			die "DB_DEBUG>$0:\n".
                "====>Failed to update the request for $opkg"
        		if(!update_table($options_ref,
                    "Node_Package_Status",
                    $field_value_hash,
                    $where,
                    $error_ref));
        } else {
        	$$field_value_hash{package} = $opkg;
        	$$field_value_hash{node_id} = $node_id;
        	die "DB_DEBUG>$0:\n====>Failed to insert the request for $opkg" 
        		if(!insert_into_table($options_ref,
                    "Node_Package_Status",
                    $field_value_hash,
                    $error_ref));
        }
    }
    return 1;
}

# Updates the status information for a package by passing in a hash
# The keys in the hash are the names of the database fields (requested, current,
# status, etc.).  The values are the values that should be put
# into the database.
sub update_image_package_status_hash ($$$$$) {
	my ($options_ref,
		$image,
		$passed_pkg,
		$field_value_hash,
		$error_ref) = @_;
	my $packages;
	
	# Get the information passed in about a package
	if(ref($passed_pkg) eq "ARRAY") {
		$packages = $passed_pkg;
	} else {
		my %opkg = ();
		my @temp_packages = ();
		$opkg{package} = $passed_pkg;
		push @temp_packages, \%opkg;
		$packages = \@temp_packages;
	}
	
	# If requested is one of the names of the fields being passed in, convert it
	# to the enum version instead of the string
	if(exists $$field_value_hash{requested}) {
		$$field_value_hash{requested} = get_status_num($options_ref,
            $$field_value_hash{requested},
            $error_ref);
	}
	
	# If current is one of the names of the fields being passed in, convert it
	# to the enum version instead of the string
	if(exists $$field_value_hash{current}) {
		$$field_value_hash{current} = get_status_num($options_ref,
            $$field_value_hash{current},
            $error_ref);
	}
	
	# Get the internal id for the node
	my $image_ref = get_image_info_with_name($image, $options_ref, $error_ref);
	my $image_id = $$image_ref{id};
	
	# Get more information about the package
	foreach my $pkg_ref (@$packages) {
		my $opkg = $$pkg_ref{package};
		my $where = "WHERE package=\'$opkg\' AND image_id=$image_id";
        if(!update_table($options_ref,
            "Image_Package_Status",
            $field_value_hash,
            $where,
            $error_ref)) {
		    die "DB_DEBUG>$0:\n====>Failed to update the request for $opkg" 
        }
	}
	return 1;
}

# TODO: code duplication with the function update_image_package_status, we
# shoudl avoid that.
# For normal oscar package installation, 
# the possible values of  "requested" are defined in ODA_Defs.pm.
# 1 : should_not_be_installed.
# 2 : should_be_installed
# 8 : finished
sub update_image_package_status {
    my ($options_ref,
        $image,
        $passed_pkg,
        $requested,
        $errors_ref,
        $selected) = @_;

    $requested = SHOULD_NOT_BE_INSTALLED() if ! $requested;
    my $packages;
    if (ref($passed_pkg) eq "ARRAY"){
        $packages = $passed_pkg;
    } else {
        my %opkg = ();
        my @temp_packages = ();
        $opkg{package} = $passed_pkg;
        push @temp_packages, \%opkg;
        $packages = \@temp_packages;
    }
    # If requested is one of the names of the fields being passed in, convert it
    # to the enum version instead of the string
    if($requested && $requested !~ /\d/) {
        $requested = get_status_num($options_ref, $requested, $errors_ref);
    }
    my $image_ref = get_image_info_with_name($image, $options_ref, $errors_ref);
    my $image_id = $$image_ref{id};
    foreach my $pkg_ref (@$packages) {
        my $opkg = $$pkg_ref{package};
        my %field_value_hash = ("requested" => $requested);
        if ($$options_ref{debug} || defined($ENV{DEBUG_OSCAR_WIZARD})) {
            print "DB_DEBUG>$0:\n====> in ".
                "Database::update_node_package_status Updating the status ".
                "of $opkg to \"";
            if ($requested == 8) {
                print "installed";
            } elsif ($requested == SHOULD_BE_INSTALLED()) {
                print "should be installed";
            } elsif ($requested == SHOULD_NOT_BE_INSTALLED()) {
                print "should not be installed";
            } else {
                print "... unknown status ($requested)";
            }
            print "\".\n";
        }
        my @results = ();
        my $table = "Image_Package_Status";
        &get_image_package_status_with_image($image,
            $opkg,
            \@results,
            $options_ref,
            $errors_ref);
        print_array (@results);

        my $where = "WHERE package=\'$opkg\' AND image_id=$image_id";
        if (!@results) {
            print "The OPKG status information is already in ODA\n";
            my $pstatus_ref = pop @results;
            my $ex_status = $$pstatus_ref{ex_status};
            $field_value_hash{requested} = $ex_status
                if($ex_status == FINISHED()
                    && $requested == SHOULD_BE_INSTALLED());
            $field_value_hash{ex_status} = $$pstatus_ref{requested};

            # If $requested is 8(finished), set the "ex_status" to 8
            # because setting "finished" to the "ex_status" prevents
            # package status from being updated incorrectly when a 
            # package is selected/unselected on Seletor.
            #
            # NOTE : the "selected" field is only for PackageInUn
            #
            $field_value_hash{ex_status} = $requested 
                if ($requested == FINISHED()
                    && $ex_status != SHOULD_BE_INSTALLED());
            $field_value_hash{selected} = $selected if ($selected);
            if (!&update_table($options_ref,
                $table,
                \%field_value_hash,
                $where,
                $errors_ref)) {
                die "DB_DEBUG>$0:\n====>Failed to update the status of $opkg";
            }
        } else {
            print "The OPKG status information is not in ODA, we create an ".
                  "entry\n";
            %field_value_hash = ("image_id" => $image_id,
                                 "package" => $opkg,
                                 "requested" => $requested);
            if (!&insert_into_table ($options_ref,
                $table,
                \%field_value_hash,
                $errors_ref)) {
                die "DB_DEBUG>$0:\n".
                    "====>Failed to insert values into table $table";
            }
        }
    }
    return 1;
}

#
# Return: non-zero for success.
#
# TODO: extend this function to the case where we do not have a real database
# but configuration files.
sub update_packages ($$$$$$) {
    my ($passed_ref,
        $table,
        $package_id,
        $table_fields_ref,
        $options_ref,
        $errors_ref) = @_;
    my $sql = "UPDATE $table SET ";
    my $sql_values = " VALUES ( ";
    my $flag = 0;
    my $comma = "";
    foreach my $key (keys %$passed_ref){
        # If a field name is "group", "__" should be added
        # in front of $key to avoid the conflict of reserved keys

        if ($$table_fields_ref{$table}->{$key}
        && $key ne "package-specific-attribute") {

            $comma = ", " if $flag;
            $key = ( $key eq "group"?"__$key":$key);
            $key = ( $key eq "class"?"__$key":$key);
            $sql .= "$comma $key=";
            $flag = 1;
            $key = ( $key eq "__group"?"group":$key);
            $key = ( $key eq "__class"?"class":$key);
            my $value;
        $value = ($passed_ref->{$key}?trim($passed_ref->{$key}):""); 
        $value =~ s#'#\\'#g;
        $sql .= "'$value'";
        }
    }
    $sql .= " WHERE id=$package_id\n";

    my $debug_msg = "DB_DEBUG>$0:\n====> in Database::update_packages SQL : $sql\n";
    print "$debug_msg" if $$options_ref{debug};
    push @$errors_ref, $debug_msg;

    my $success = OSCAR::oda::do_sql_command($options_ref,
                    $sql,
                    "UPDATE Table, $table",
                    "Failed to update $table table",
                    $errors_ref);
    $errors_ref = \@error_strings;
    return $success;
}

sub set_all_groups ($$$) {
    my ($groups_ref,
        $options_ref,
        $error_ref) = @_;
    my $sql = "SELECT * FROM Groups";
    print "DB_DEBUG>$0:\n====> in Database::set_all_groups SQL : $sql\n" 
        if $$options_ref{debug};
    my @groups = ();
    die "DB_DEBUG>$0:\n====>Failed to query values via << $sql >>"
        if! do_select($sql,\@groups, $options_ref, $error_ref);
    if(!@groups){
        foreach my $group (keys %$groups_ref){
            set_groups($group,
                $options_ref,
                $error_ref,
                $$groups_ref{$group});
        }
    }
    return 1;
}

################################################################################
# Include a new group of nodes into the database.                              #
#                                                                              #
# Input: - group, group id (as specified in the "Groups" table in ODA.         #
#        - node_ref, reference to an array that contains the list of nodes'    #
#                    name.                                                     #
#        - options_ref, ???                                                    #
#        - error_strings_ref, ???                                              #
# Return: 1 if success, 0 else.                                                #
################################################################################
sub set_group_nodes ($$$$) {
    my ($group,
        $nodes_ref,
        $options_ref,
        $error_ref) = @_;

    if (!OSCAR::Utils::is_a_valid_string ($group)) {
        carp "ERROR: Invalid group";
        return 0;
    }
    my %field_value_hash = ( "group_name" => $group );
    my $success = 0;
    foreach my $node (@$nodes_ref){
        my $node_ref = get_node_info_with_name($node,
                                               $options_ref,
                                               $error_ref);
        my $node_id = $$node_ref{id};
        if (!OSCAR::Utils::is_a_valid_string ($node_id)) {
            carp "ERROR: Invalid node ID";
            return 0;
        }
        my $sql = "SELECT * FROM Group_Nodes WHERE group_name='$group' ".
                  "AND node_id=$node_id";
        my @results = ();
        print "DB_DEBUG>$0:\n====> in Database::set_group_nodes SQL : $sql\n"
            if $$options_ref{debug};
        do_select($sql, \@results, $options_ref, $error_ref);
        if(!@results){
            $sql = "INSERT INTO Group_Nodes VALUES('$group', $node_id )";
            print "DB_DEBUG>$0:\n===> in Database::set_group_nodes SQL:  $sql\n"
                if $$options_ref{debug};
            $success = do_insert($sql,
                                 "Group_Nodes",
                                 $options_ref,
                                 $error_ref);
            last if !$success;
            $success = update_node($node,
                                   \%field_value_hash,
                                   $options_ref,
                                   $error_ref);
            last if ! $success;
        }
    }
    return $success;
}

# Return: 1 if success, 0 else.
# DEPRECATED??
sub set_group_packages {
    my ($group,
        $package,
        $requested,
        $options_ref,
        $error_ref) = @_;

    $group = get_selected_group($options_ref, $error_ref)
        if(!$group);
    my @results = ();
    # Update Node_Package_Status to set the "selected" value according to the
    # "requested" value:
    # if requested = 1 then selected = 0
    # if requested >= 2 then selected = 1
    my $selected = 0;
    my $sql = "SELECT package " .
              "From Group_Packages " .
              "WHERE Packages='$package' AND group_name='$group'";
    print "DB_DEBUG>$0:\n====> in Database::set_group_packages SQL: $sql\n"
        if $$options_ref{debug};
    do_select($sql, \@results, $options_ref, $error_ref);
    if (!@results) {
        $selected = 1;
        $sql = "INSERT INTO Group_Packages (group_name, package, selected) ".
               "VALUES ('$group', '$package', '$selected')";
        oscar_log_subsection ("DB_DEBUG>$0:\n".
            "====> in Database::set_group_packages SQL : $sql\n")
            if $$options_ref{debug};
        if (!do_update($sql, "Group_Packages", $options_ref, $error_ref)) {
            carp "DB_DEBUG>$0:\n====>Failed to insert values via << $sql >>";
            return 0;
        }
    } else {
        $selected = 1 if ($requested && $requested >= 2);
        my $result_ref = pop @results;
        my $package_id = $$result_ref{id};
        $sql = "UPDATE Group_Packages SET selected=$selected ".
            "WHERE group_name='$group' ".
            "AND package='$package'";
        oscar_log_subsection ("DB_DEBUG>$0:\n".
            "====> in Database::set_group_packages SQL : $sql\n")
            if $$options_ref{debug};
        if (!do_update($sql,
                "Group_Packages",
                $options_ref,
                $error_ref)) {
            carp "ERROR>$0:\n====>Failed to update values via << $sql >>";
            return 0;
        }
    }

    $requested = 1 if !$requested;
    update_node_package_status($options_ref,
                               $OSCAR_SERVER,
                               $package,
                               $requested,
                               $error_ref,
                               undef);
    return 1;
}

# Return: 1 if success, 0 else.
sub set_groups ($$$$) {
    my ($group,
        $options_ref,
        $error_ref,
        $type) = @_;
    $type = "package" if ! $type;
    my @results = ();
    get_groups(\@results,$options_ref,$error_ref,$group);
    if(!@results){
        my $sql = "INSERT INTO Groups (name,type) VALUES ('$group','$type')";
        print "DB_DEBUG>$0:\n====> in Database::set_groups SQL : $sql\n" 
            if $$options_ref{debug};
        if (!do_insert($sql,"Groups", $options_ref, $error_ref)) {
            carp "DB_DEBUG>$0:\n====>Failed to insert values via << $sql >>";
            return 0;
        }
    }
    return 1;
}

# Return: 1 if success, 0 else.
sub set_groups_selected ($$$) {
    my ($group,
        $options_ref,
        $error_ref) = @_;
    my @results = ();
    get_groups(\@results, $options_ref, $error_ref, $group);
    if(@results){
        # Initialize the "selected" flag (selected = 0)
        my $sql = "UPDATE Groups SET selected=0";
        print "DB_DEBUG>$0:\n====> in Database::set_groups_selected SQL: $sql\n"
            if $$options_ref{debug};
        if (!do_insert($sql,"Groups", $options_ref, $error_ref)) {
            carp "DB_DEBUG>$0:\n====>Failed to update values via << $sql >>";
            return 0;
        }

        # Set the seleted group to have "selected" flag
        # (selected = 1)
        $sql = "UPDATE Groups SET selected=1 WHERE name='$group'";
        print "DB_DEBUG>$0:\n====> in Database::set_groups_selected SQL : $sql\n"
            if $$options_ref{debug};
        if (!do_insert($sql,"Groups", $options_ref, $error_ref)) {
            carp "DB_DEBUG>$0:\n====>Failed to update values via << $sql >>";
            return 0;
        }
    }
    return 1;
}

sub rename_group ($$$$) {
    my ($old_name,
        $new_name,
        $options_ref,
        $errors_ref) = @_;

    my $sql = "UPDATE Groups SET name='$new_name' WHERE name='$old_name'";
        print "DB_DEBUG>$0:\n====> in Database::rename_group SQL : $sql\n"
        if $$options_ref{debug};
    die "DB_DEBUG>$0:\n====>Failed to update values via << $sql >>"
    if !&do_update($sql, "Groups", $options_ref, $errors_ref);
    return 1;
}

# Return: 0 if success, -1 else.
sub set_image_packages ($$$$) {
    my ($image,
        $package,
        $options_ref,
        $errors_ref) = @_;
    my $image_ref = get_image_info_with_name($image, $options_ref, $errors_ref);
    if (!defined ($image_ref)) {
        carp ("ERROR: Image $image not found in OSCAR Database");
        return -1;
    }
    my $image_id = $$image_ref{id};
    my $sql = "SELECT * FROM Image_Package_Status WHERE image_id=$image_id".
        " AND package='$package'";
    print "DB_DEBUG>$0:\n====> in Database::set_image_packages SQL : $sql\n"
        if $$options_ref{debug};
    my @images = ();
    die "DB_DEBUG>$0:\n====>Failed to query values via << $sql >>"
        if !&do_select($sql, \@images, $options_ref, $errors_ref);
    if (!@images){
        $sql = "INSERT INTO Image_Package_Status (image_id,package) VALUES ".
            "($image_id,'$package')";
        print "DB_DEBUG>$0:\n====> in Database::set_image_packages SQL : ".
            "$sql\n" if $$options_ref{debug};
        die "DB_DEBUG>$0:\n====>Failed to insert values via << $sql >>"
            if !&do_insert($sql,
                "Image_Package_Status",
                $options_ref,
                $errors_ref);
    }
    return 1;
}

################################################################################
# Insert or update image data.                                                 #
#                                                                              #
# Input: image_ref,  a ref to a hash representing the image data. The hash has #
# the following structure:                                                     #
#   name: image name,                                                          #
#   architecture: target architecture for the image (e.g., x86_64).            #
#   path: where the image is saved on the system.                              #
#   options_ref, options used for the addition of a new image (reference to a  #
#                hash). Optional - can be "undef".                             #
#   error_ref, reference to an array that gathers messages to display in case  #
#              of errors or debugging. Optional - can be "undef".              #
# Return: 1 if success, 0 else.                                                #
################################################################################
sub set_images ($$$) {
    my ($image_ref,
        $options_ref,
        $error_ref) = @_;

    my $imgname = $$image_ref{name};
    my $architecture = $$image_ref{architecture};
    my $images = get_image_info_with_name($imgname, $options_ref, $error_ref);
    my $imagepath = $$image_ref{path};
    my $sql = "";
    if(!$images){ 
        $sql = "INSERT INTO Images (name,architecture,path) VALUES ".
            "(\'$imgname\',\'$architecture\',\'$imagepath\')";
        print "DB_DEBUG>$0:\n====> in Database::set_images SQL : $sql\n"
            if $$options_ref{debug};
        if (do_insert($sql, "Images", $options_ref, $error_ref) == 0) {
            carp "DB_DEBUG>$0:\n====>Failed to insert values via << $sql >>";
            return 0;
        }
    } else {
        $sql = "UPDATE Images SET name='$imgname', ".
               "architecture='$architecture', path='$imagepath' ".
               "WHERE name='$imgname'";
        print "DB_DEBUG>$0:\n====> in Database::set_images SQL : $sql\n"
            if $$options_ref{debug};
        die "DB_DEBUG>$0:\n====>Failed to update values via << $sql >>"
            if! do_update($sql, "Images", $options_ref, $error_ref);
    }
    return 1;
}

# Set installation mode for cluster
sub set_install_mode ($$$) {
    my ($install_mode,
        $options_ref,
        $error_ref) = @_;

    my $cluster = "oscar";
    my $sql = "UPDATE Clusters SET install_mode='$install_mode' ".
        "WHERE name ='$cluster'";

    print "DB_DEBUG>$0:\n====> in Database::set_install_mode SQL : $sql\n" 
        if $$options_ref{debug};
    return do_update($sql, "Clusters", $options_ref, $error_ref);
}

# Set the Manage status with a new value
sub set_manage_status{
    my ($step_name, $options_ref, $error_ref) = @_;
    my $sql = "UPDATE Manage_status SET status='normal' ".
        "WHERE step_name='$step_name'";
    return do_update($sql, "Manage_status", $options_ref, $error_ref);
}

# set package configuration name/value pair
# Usage example:
#   set_pkgconfig_var(opkg => "ganglia" , context => "",
#                     name => "gmond_if", value => [ "eth0" ]);
#
# "value" needs to point to an anonymous array reference!
# The arguments "name" and "context" are optional.
sub set_pkgconfig_var (%) {
    my (%val) = @_;
    if (!exists($val{opkg}) || !exists($val{name}) || !exists($val{value})) {
        croak("missing one of opkg/name/value : ".Dumper(%val));
    }
    if (!exists($val{context}) || $val{context} eq "") {
        $val{context} = "global";
    }
    my (%options, @errors);
    my %sel = %val;
    delete $sel{value};
    my $sql;
    # delete all existing records
    &del_pkgconfig_vars(%sel);

    # get opkg_id first
    my $opkg = $val{opkg};
    delete $val{opkg};
    $val{package} = $opkg;

    my @values = @{$val{value}};
    delete $val{value};

    for my $v (@values) {
        $val{value} = $v;
        $sql = "INSERT INTO Packages_config (".join(", ",(keys(%val))).") " .
               "VALUES ('" . join("', '",values(%val)) . "')";;
        croak("$0:Failed to insert values via << $sql >>")
            if !do_insert($sql, "Packages_config", \%options, \@errors);
    }
    return 1;
}

# get package configuration values
# Usage example:
#   get_pkgconfig_vars(opkg => "ganglia", context => "",
#                      name => "gmond_if");
# The arguments "name" and "context" are optional.
#
# Returns an array of hashes with the data from ODA.
sub get_pkgconfig_vars (%) {
    my (%sel) = @_;
    croak("opkg not specified!")	if (!exists($sel{opkg}));
    if (!exists($sel{context}) || $sel{context} eq "") {
        $sel{context} = "global";
    }
    my (%options, @errors);
    my $opkg = $sel{opkg};
    delete $sel{opkg};
    my $sql = "SELECT package AS opkg, " .
              "config_id AS config_id, " .
              "name AS name, " .
              "value AS value, " .
              "context AS context ".
              "FROM Packages_config " .
              "WHERE package='$opkg' AND ";
    my @where = map { "Packages_config.$_='".$sel{$_}."'" } keys(%sel);
    $sql .= join(" AND ", @where);
    my @result = ();
    die "$0:Failed to query values via << $sql >>"
        if (!do_select($sql, \@result, \%options, \@errors));

    return @result;
}

# convert pkgconfig vars query result into a values hash tree
# good to be used with the configurator routines
sub pkgconfig_values (@) {
    my (@result) = @_;
    my %values;
    for my $r (@result) {
        my $name = $r->{name};
        my $val  = $r->{value};
        if (!exists($values{$name})) {
            $values{"$name"} = [ "$val" ];
        } else {
            push @{$values{"$name"}}, "$val";
        }
    }
    return %values;
}

# delete package configuration values
# Usage example:
#   del_pkgconfig_vars(opkg => "ganglia", context => "",
#                      name => "gmond_if");
# At least the "opkg" selection must be specified!
# The arguments "name" and "context" are optional.
sub del_pkgconfig_vars {
    my (%sel) = @_;
    croak("opkg not specified!") if (!exists($sel{opkg}));
    if (!exists($sel{context}) || $sel{context} eq "") {
        $sel{context} = "global";
    }
    my (%options, @errors);

    my @exists = &get_pkgconfig_vars(%sel);
    return 1 if (!scalar(@exists));

    for my $e (@exists) {
        my $id = $e->{config_id};

        my $sql = "DELETE FROM Packages_config WHERE config_id='$id'";
        die "$0:Failed to delete values via << $sql >>"
            if (!do_update($sql, "Packages_config", \%options, \@errors));
    }
    return 1;
}

# Return: 1 if success, 0 else.
sub set_node_with_group {
    my ($node,
        $group,
        $options_ref,
        $error_ref,
        $cluster_name) = @_;
    my $sql = "SELECT name FROM Nodes WHERE name='$node'";
    my @nodes = ();
    print "DB_DEBUG>$0:\n====> in Database::set_node_with_group SQL : $sql\n" 
        if $$options_ref{debug};
    die "DB_DEBUG>$0:\n====>Failed to query values via << $sql >>"
        if! do_select($sql, \@nodes, $options_ref, $error_ref);
    if(!@nodes){
        $cluster_name = $CLUSTER_NAME if !$cluster_name;
        my $cluster_ref = get_cluster_info_with_name($cluster_name,
                                                     $options_ref,
                                                     $error_ref);
        if (!defined $cluster_ref || ref{$cluster_ref} ne "HASH") {
            carp "ERROR: Impossible to get cluster data";
            return 0;
        }
        my $cluster_id = $$cluster_ref{id} if $cluster_ref;
        if (!defined $cluster_id) {
            carp "ERROR: Unknown cluster ID";
            return 0;
        }
        # Assume hostname = name.(sync_hosts): required for client postinstall 
        # (e.g.: sge)
        $sql = "INSERT INTO Nodes (cluster_id, hostname, name, group_name) ".
               "SELECT $cluster_id, '$node', '$node', '$group'";
        print "DB_DEBUG>$0:\n====> in Database::set_node_with_group SQL: $sql\n"
            if $$options_ref{debug};
        if (do_insert($sql, "Nodes", $options_ref, $error_ref) == 0) {
            carp "DB_DEBUG>$0:\n====>Failed to insert values via << $sql >>";
            return 0;
        }
    } else {
	# This function is inapropriate for node info update (cpu count info)
        print "The node $node is already in the database\n";
    }
    return 1;
}

################################################################################
# Set a NIC to a node.                                                         #
#                                                                              #
# Input: nic, NIC name.                                                        #
#        node, node name we have to assign the NIC to.                         #
#        field_value_ref, hash giving the values of the different table        #
#                         entries (for instance 'mac => 00:A0:00:A0:B1:BB'.    #
#                         All the table's entry do not need to be specified.   #
#        options_ref, optional reference to options hash.                      #
#        error_strings_ref, ??? (optional, i.e., may be empty).                #
################################################################################
sub set_nics_with_node ($$$$$) {
    my ($nic,
        $node,
        $field_value_ref,
        $options_ref,
        $error_ref) = @_;
    my $sql = "SELECT Nics.* FROM Nics, Nodes WHERE Nodes.id=Nics.node_id " .
              "AND Nics.name='$nic' AND Nodes.name='$node'";
    print "DB_DEBUG>$0:\n====> in Database::set_nics_with_node SQL : $sql\n"
        if $$options_ref{debug};
    my @nics = ();
    die "DB_DEBUG>$0:\n====>Failed to query values via << $sql >>"
        if! do_select($sql,\@nics, $options_ref, $error_ref);

    my $node_ref = get_node_info_with_name($node, $options_ref, $error_ref);
    my $node_id = $$node_ref{id};
    if(!@nics) {
        $sql = "INSERT INTO Nics ( name, node_id ";
        my $sql_value = " VALUES ('$nic', $node_id ";
        if( $field_value_ref ){
            while (my ($field, $value) = each %$field_value_ref){
                $sql .= ", $field";
                $sql_value .= ", '$value'";
            }
        }
        $sql .= " ) $sql_value )";
        print "DB_DEBUG>$0:\n====> in Database::set_nics_with_node SQL : $sql\n"
            if $$options_ref{debug};
        die "DB_DEBUG>$0:\n====>Failed to insert values via << $sql >>"
            if! do_insert($sql,"Nodes", $options_ref, $error_ref);
    } else {
        $sql = "UPDATE Nics SET ";
        my $flag = 0;
        my $comma = "";
        if( $field_value_ref ) {
            while (my ($field, $value) = each %$field_value_ref){
                $comma = ", " if $flag;
                $sql .= "$comma $field='$value'";
                $flag = 1;
            }
            $sql .= " WHERE name='$nic' AND node_id=$node_id ";
            print "DB_DEBUG>$0:\n".
                "====> in Database::set_nics_with_node SQL : $sql\n"
                if $$options_ref{debug};
            die "DB_DEBUG>$0:\n====>Failed to update values via << $sql >>"
                if! do_update($sql, "Nics", $options_ref, $error_ref);
        }
    }
    return 1;
}

sub set_status ($$) {
    my ($options_ref, $error_ref) = @_;
    my $sql = "SELECT * FROM Status";
    print "DB_DEBUG>$0:\n====> in Database::set_status SQL : $sql\n"
        if $$options_ref{debug};
    my @status = ();
    die "DB_DEBUG>$0:\n====>Failed to query values via << $sql >>"
        if! do_select($sql, \@status, $options_ref, $error_ref);
    if(!@status){ 
        foreach my $status (
                            "should_not_be_installed",
                            "should_be_installed",
                            "run-configurator",
                            "install-bin-pkgs",
                            "run-script-post-image",
                            "run-script-post-clients",
                            "run-script-post-install",
                            "finished"
                            ){
#   OLD Status values
#                          ( "installable", "installed",
#                            "install_allowed","should_be_installed", 
#                            "should_be_uninstalled","uninstalled",
#                            "finished")

            $sql = "INSERT INTO Status (name) VALUES ('$status')";
            print "DB_DEBUG>$0:\n====> in Database::set_status SQL : $sql\n" 
                if $$options_ref{debug};
            die "DB_DEBUG>$0:\n====>Failed to insert values via << $sql >>"
                if! do_insert($sql, "Nodes", $options_ref, $error_ref);
        }
    }
    return 1;
}

# Set the Wizard status with a new value
sub set_wizard_status ($$$) {
    my ($step_name, $options_ref, $error_ref) = @_;
    my $sql = "UPDATE Wizard_status SET status='normal' ".
        "WHERE step_name='$step_name'";
    return do_update($sql, "Wizard_status", $options_ref, $error_ref);
}


######################################################################
#
#       Miscellaneous database subroutines
#
######################################################################



#********************************************************************#
#********************************************************************#
#                                                                    #
# internal function to fill in any missing function parameters       #
#                                                                    #
#********************************************************************#
#********************************************************************#
# inputs:  options            optional reference to options hash
#          error_strings_ref  optional reference to array for errors

sub fake_missing_parameters ($$) {
    my ($passed_options_ref, $passed_error_ref ) = @_;

    my %options = ( 'debug'         => 0,
                    'raw'           => 0,
                    'verbose'       => 0 );
    # take care of faking any non-passed input parameters, and
    # set any options to their default values if not already set
    my @ignored_error_strings;
    my $errors_ref = ( defined $passed_error_ref ) ?
        $passed_error_ref : \@ignored_error_strings;

    my $options_ref;
    if (ref($passed_options_ref) eq "HASH" && defined $passed_options_ref) {
        $options_ref = $passed_options_ref;
    } else {
        $options_ref = \%options;
    }

    oscar_log_subsection "DB_DEBUG>$0:\n".
        "====> in Database.pm::fake_missing_parameters handling the missing ". 
        "parameters" if $$options_ref{verbose};

    return ($options_ref, $errors_ref );
}

######################################################################
#
#       LOCK / UNLOCK database subroutines
#
######################################################################

#
# NEST
# This subroutine is renamed from database_execute_command and represents
# the $command_args_ref in the subroutine is already locked in the outer lock block.
# Basically this subroutine is the exactly same as database_execute_command
# except for its name.
#
sub dec_already_locked ($$) {
    my ($sql_command, $passed_errors_ref) = @_;

    # sometimes this is called without a database_connected being 
    # called first, so we have to connect first if that is the case
    ( my $was_connected_flag = $database_connected ) ||
        database_connect( undef, $passed_errors_ref ) ||
        return undef;

    # execute the command
    my @error_strings = ();
    my $error_strings_ref = ( defined $passed_errors_ref && 
                  ref($passed_errors_ref) eq "ARRAY" ) ?
                  $passed_errors_ref : \@error_strings;
    my $success =  OSCAR::oda::do_sql_command( $options_ref,
                                $sql_command,
                                undef,
                                undef,
                                $error_strings_ref );
    if ( defined $passed_errors_ref
            && ! ref($passed_errors_ref)
            && $passed_errors_ref ) {
        warn shift @$error_strings_ref while @$error_strings_ref;
    }

    # if we weren't connected to the database when called, disconnect
    database_disconnect(undef, undef) if ! $was_connected_flag;

    return $success;
}

#********************************************************************#
#********************************************************************#
#                            NEST                                    #
# function to write/read lock one or more tables in the database     #
#                                                                    #
#********************************************************************#
#********************************************************************#
# inputs:  type_of_lock              String of lock types (READ/WRITE)
#          options            optional reference to options hash
#          passed_tables_ref         reference to modified tables list
#          error_strings_ref  optional reference to array for errors
#
# outputs: non-zero if success
sub locking ($$$$) {
    my ( $type_of_lock,
         $options_ref,
         $passed_tables_ref,
         $error_strings_ref,
       ) = @_;
    my @empty_tables = ();
    my $tables_ref = ( defined $passed_tables_ref ) ? $passed_tables_ref : \@empty_tables;

    my $msg = "DB_DEBUG>$0:\n====> in oda:";
        $type_of_lock =~ s/(.*)/\U$1/gi;
    if( $type_of_lock eq "WRITE" ){
        $msg .= "write_lock write_locked_tables=(";
    } elsif ( $type_of_lock eq "READ" ) {
        $msg .= "read_lock read_locked_tables=(";
    } else {
        return 0;
    }

    oscar_log_section ($msg . join( ',', @$tables_ref ) . ")\n")
        if $$options_ref{debug};

    # connect to the database if not already connected
    $database_connected ||
        database_connect( $options_ref, $error_strings_ref ) ||
        return 0;

    # find a list of all the table names, and all the fields in each table
    my $all_tables_ref = OSCAR::oda::list_tables( $options_ref, $error_strings_ref );
    if ( ! defined $all_tables_ref ) {
        database_disconnect( $options_ref, $error_strings_ref )
            if ! $database_connected;
        return 0;
    }

    # make sure that the specified modified table names
    # are all valid table names, and save the valid ones
    my @locked_tables = ();
    foreach my $table_name ( @$tables_ref ) {
        if ( exists $$all_tables_ref{$table_name} ) {
            push @locked_tables, $table_name;
        } else {
            push @$error_strings_ref,
            "DB_DEBUG>$0:\n====> table <$table_name> does not exist in " .
            "database <$$options_ref{database}>";
        }
    }

    # make the database command
    my $sql_command = "LOCK TABLES " .
        join( " $type_of_lock, ", @locked_tables ) . " $type_of_lock;" ;

    my $success = 1;

    # now do the single command
    $success = 0 
    if ! OSCAR::oda::do_sql_command( $options_ref,
                  $sql_command,
                  "oda\:\:$type_of_lock"."_lock",
                  "$type_of_lock lock in tables (" .
                  join( ',', @locked_tables ) . ")",
                  $error_strings_ref );
    # disconnect from the database if we were not connected at start
    database_disconnect($options_ref, $error_strings_ref)
        if ! $database_connected;

    return $success;
}

#********************************************************************#
#********************************************************************#
#                            NEST                                    #
# function to unlock one or more tables in the database              #
#                                                                    #
#********************************************************************#
#********************************************************************#
# inputs:  options            optional reference to options hash
#          error_strings_ref  optional reference to array for errors
#
# outputs: non-zero if success
sub unlock ($$) {
    my (
        $options_ref,
        $error_strings_ref,
       ) = @_;


    print "DB_DEBUG>$0:\n====> in oda:unlock \n" if $$options_ref{debug};

    # connect to the database if not already connected
    $database_connected ||
        database_connect( $options_ref,
        $error_strings_ref ) ||
        return 0;

    # make the database command
    my $sql_command = "UNLOCK TABLES ;" ;

    my $success = 1;

    # now do the single command
    $success = 0 if ! OSCAR::oda::do_sql_command( $options_ref,
                      $sql_command,
                      "oda\:\:unlock",
                      "unlock the tables locked in the database",
                      $error_strings_ref );

    # disconnect from the database if we were not connected at start
    database_disconnect( $options_ref, $error_strings_ref )
        if ! $database_connected;

    OSCAR::oda::initialize_locked_tables();

    return $success;

}


#
# NEST
# This is locking a single database_execute_command with some argurments
# Basically Lock -> 1 oda::execute_command -> unlock
# $type_of_lock is optional, if it is omitted, the default type of lock is "READ".
# The required argument is $tables_ref, which is the reference of the list of tables.
# The other arguments are the same as the database_execute_command.
#
sub single_dec_locked ($$$$$) {

    my ( $command_args_ref,
         $type_of_lock,
         $tables_ref,
         $results_ref,
         $passed_errors_ref ) = @_;

    # execute the command
    my @error_strings = ();
    my $errors_ref = ( defined $passed_errors_ref && 
                  ref($passed_errors_ref) eq "ARRAY" ) ?
                  $passed_errors_ref : \@error_strings;
    my @tables = ();
    if ( (ref($tables_ref) eq "ARRAY")
        && (defined $tables_ref)
        && (scalar @$tables_ref != 0) ){
        @tables = @$tables_ref;
    } else {
        #chomp(@tables = oda::list_tables);
        my $all_tables_ref = OSCAR::oda::list_tables( $options_ref, $errors_ref );
        foreach my $table (keys %$all_tables_ref){
            push @tables, $table;
        }
    }
    my $lock_type = (defined $type_of_lock)? $type_of_lock : "READ";
    # START LOCKING FOR NEST && open the database
    my %options = ();
#    if(! locking($lock_type, $options_ref, \@tables, $error_strings_ref)){
#        return 0;
        #die "DB_DEBUG>$0:\n====> cannot connect to oda database";
#    }
    my $success = OSCAR::oda::do_query( $options_ref,
                    $command_args_ref,
                    $results_ref,
                    $errors_ref );
    # UNLOCKING FOR NEST
#    unlock($options_ref, $error_strings_ref);
    if ( defined $passed_errors_ref && ! ref($passed_errors_ref) && $passed_errors_ref ) {
        warn shift @$errors_ref while @$errors_ref;
    }

    return $success;
}

################################################################################
# This function executes a simple query against the database. Typically it     #
# allows us to execute a simple SQL query which returns an array of hashes,    #
# each hash having a single key (always the same). The hash is then converted  #
# into an array in order to simplifies future usage.                           #
# Example: the call "simple_oda_query ("SELECT Clusters.Id FROM Clusters WHERE #
# name='oscar'", "id")" will generates the the SQL query "SELECT Clusters.Id   #
# FROM Clusters WHERE name='oscar'"                                            #
# The query will return:                                                       #
# $VAR1 = {                                                                    #
#          'id' => '1'                                                         #
#        };                                                                    #
# Which is the converted into an array: [ 1 ].                                 #
#                                                                              #
# Input: - sql, string representing the SQL query.                             #
#        - elt, a filter we want to use to "parse" the result. For instance,   #
#               "cluster_id" means we want to have only values of the          #
#               "cluster_id" field for a given query.                          #
# Output: array of results, or undef.                                          #
################################################################################
sub simple_oda_query ($$) {
    my ($sql, $elt) = @_;
    my @list;

    my $options_ref;
    my $error_strings_ref;
    my @result_ref;
    oscar_log_subsection ("SQL query: $sql\n") if $verbose;
    if (!do_select($sql,\@result_ref, $options_ref, $error_strings_ref)) {
        print "ERROR: Impossible to query the database ($sql)\n";
        return undef;
    }
    # We parse the result in order to get a more usefull formated info
    foreach my $result (@result_ref) {
        if ($result->{$elt} ne "") {
            push (@list, $result->{$elt});
        }
    }
    return (@list);
}

################################################################################
# This function executes a simple query against the database and check that    #
# the result is unique. For that we use simple_oda_query and check that the    #
# array we get as result get one and only one element.                         #
# Input: - sql, string representing the SQL query.                             #
#        - id, the table element we want to query against. For instance the    #
#              cluster_id element of the Cluster table.                        #
# Return: - the query result or undef,                                         #
################################################################################
sub oda_query_single_result ($$) {
    my ($sql, $id) = @_;
    my @list = simple_oda_query ($sql, $id);
    if (scalar (@list) != 1) {
        return undef;
    }
    return ($list[0]);
}

################################################################################
# Create the database if not already there and leave us connected to it.       #
# WARNING the created database is empty!                                       #
#                                                                              #
# Input: - options: reference to a hash representing the options.              #
#        - error_strings: reference to an array representing the error strings #
#                         (???).                                               #
# Return: 0 if success, -1 else.                                               #
################################################################################
sub create_database ($$) {
    my ($options, $error_strings) = @_;
    my %databases = ();

    OSCAR::oda::list_databases($options, \%databases, $error_strings );
    if ( ! $databases{ oscar } ) {
        oscar_log_subsection ("Creating the OSCAR database ...\n");
        my @error_strings = ();
        if ( ! OSCAR::oda::create_database( \%options, \@error_strings ) ) {
            warn shift @error_strings while @error_strings;
            carp "ERROR>$0:\n====> cannot create the OSCAR database";
            return -1;
        }
        oscar_log_subsection ("... OSCAR database successfully created.\n");
    }
    return 0;
}


################################################################################
# Starts the appropriate database service.                                     #
#                                                                              #
# Input: None.                                                                 #
# Return: o if success, -1 else.                                               #
################################################################################
sub start_database_service {
    # We get the configuration from the OSCAR configuration file.
    my $oscar_configurator = OSCAR::ConfigManager->new();
    if ( ! defined ($oscar_configurator) ) {
        carp "ERROR: [$0] start_database_service:Impossible to get the OSCAR ".
             "configuration";
        return -1;
    }
    my $config = $oscar_configurator->get_config();
    if ( !defined($config) ) {
        carp "ERROR: [$0] Unable to parse oscar.conf";
        return -1;
    }

    my $oda_type = $config->{'oda_type'};
    if (!OSCAR::Utils::is_a_valid_string ($oda_type)) {
        carp "ERROR: [$0] ODA_TYPE not set in oscar.conf";
        return -1;
    }
    if ($config->{'oda_type'} eq "file") { # test ODA_TYPE db|file
        oscar_log_subsection (">$0: Not using a real database, connection done");
        return 0;
    }

    my $db_type = $config->{'db_type'};
    if (!OSCAR::Utils::is_a_valid_string ($db_type)) {
        carp "ERROR: [$0] DB_TYPE not set in oscar.conf";
        return -1;
    }

    my $service = $db_type."_service";
    if (!OSCAR::Utils::is_a_valid_string($service)) {
        carp "ERROR: [$0] Unknown DB_TYPE=".$db_type."\n".
        return -1;
    }
    my $db_service = OSCAR::OCA::OS_Settings::getitem($service);
    if (enable_system_services($db_service)) {
        # It's not an dramatic error if we are still able to start the DB.
        # (so no return)
        print "WARNING: [$0] start_database_service: Unable to enable ".
              $db_service." service at each boot.\n";
    }
    # Start the database service.
    if (system_service($db_type, OSCAR::SystemServicesDefs::START())) {
        carp "ERROR: [$0] start_database_service: Unable to start ".
             $db_service." service.";
        return -1;
    } 

    sleep 2; # The database deamon may be starting in background. We wait
             # 2 seconds to make sure the deamon is up (do not ask me why
             # 2s and not more or less).   

    return 0;
}

################################################################################
# Create database tables.                                                      #
# Creation of OSCAR tables is not done through the config.xml of oda package   #
# any more. The table information of all the OSCAR database tables is defined  #
# at /usr/share/oscar/prereqs/oda/etc/oscar_table.sql
# Database_generic::create_table creates all the tables with the above sql     #
# file. If oda tables already exist, just skip the creation of tables.         #
#                                                                              #
# Input: - options: reference to a hash representing the options.              #
#        - error_strings: reference to an array representing the error strings #
#                         (???).                                               #
# Return: 0 if success, -1 else.                                               #
################################################################################
sub create_database_tables ($$) {
    my ($options, $error_strings) = @_;

    my $tables_are_created = 0;
    my $all_table_names_ref = OSCAR::oda::list_tables( $options,
                                                $error_strings );
    if ( defined $all_table_names_ref ) {
        my @result_strings = sort keys %$all_table_names_ref;
        $tables_are_created = 1 if @result_strings;
    }
    if (! $tables_are_created) {
        die "DB_DEBUG>$0:\n====> cannot create OSCAR tables" 
            if ! create_table(\%options, \@error_strings);
        print "\nDB_DEBUG>$0:\n===========================".
              "((( All the OSCAR tables are created )))".
              "===========================\n"
            if $options{debug} || $options{verbose};
    }

    return 0;
}

#
# SELECTOR API
#

################################################################################
# Update selection data for one or many OPKGs.                                 #
#                                                                              #
# Input: selection_data, data from Selector representing the user selection of #
#                        OPKGs. The data is implemented via a hash with the    #
#                        list of OPKGs and their selection information.        #
#                        Example: {'lam' => SELECTED, 'openmpi' => UNSELECTED} #
# Return: 0 if success, -1 else.                                               #
################################################################################
sub update_selection_data (%) {
    my %selection_data = @_;

    # We have two groups impacted by the selection: the headnode and the compute
    # nodes.
    my @groups = ("oscar_server", "oscar_clients");

    # We store the selection for those groups
    foreach my $group (@groups) {
        foreach my $opkg ( keys %selection_data ) {
            my $current_selection = get_current_selection ( $opkg, $group );
            my $sql;
            if (!defined ($current_selection)) {
                # We do not have yet any selection data for that OPKG
                $sql = "INSERT INTO ".
                       "Group_Packages(group_name, package, selected) VALUES (".
                       "'$group', '$opkg', '$selection_data{$opkg}'" .
                       ")";
                if (!OSCAR::Database_generic::do_insert($sql,
                        "Group_Packages", undef, undef)) {
                    carp "ERROR: Failed to insert selection data ($sql)";
                    return -1;
                }
            } elsif ($current_selection != $selection_data{$opkg}) {
                # The info is not up-to-date, we need to update.
                $sql = "UPDATE Group_Packages SET ".
                       "selected='$selection_data{$opkg}' ".
                       "WHERE group_name='$group' AND package='$opkg'";
                if (!&do_update($sql, "Group_Packages", undef, undef)) {
                    carp "ERROR: Impossible to update selection data ($sql)";
                    return -1;
                }
            }
        }
    }

    return 0;
}

################################################################################
# Query the database in order to get the current selection data for a given    #
# OPKG.                                                                        #
#                                                                              #
# Input: opkg, name of the OPKG we are looking for.                            #
#        group, node group id (tyically "oscar_server" or "oscar_clients".     #
# Return: - undef if no selection data is stored in the database for that      #
#           specific OPKG.                                                     #
#         - the selection code if a record is available in the database (see   #
#           ODA_Defs.pm for more details about the possible codes).            #
################################################################################
sub get_current_selection (%) {
    my ($opkg, $group) = @_;

    my $sql = "SELECT * FROM Group_Packages WHERE package='$opkg' and ".
              "group_name='$group'";
    my $current_selection = oda_query_single_result ($sql, "selected");

    return $current_selection;
}

################################################################################
# Set OPKG selection data for a set of OPKGs. The possible flags are available #
# in ODA_Defs.pm                                                               #
#                                                                              #
# Input: A hash with the list of OPKGs and their selection information.        #
#        Example: { 'lam' => SELECTED, 'openmpi' => UNSELECTED }               #
# Return: 0 if success, -1 else.                                               #
################################################################################
sub set_opkgs_selection_data (%) {
    my %selection_data = @_;

    # For each OPKG, we first check is the OPKG is already in the database
    # (Packages table), if not we add it. Then we add or update the selection
    # info for that OPKG.
    my (@res, %opts);
    for my $opkg ( keys %selection_data ) {
        my %opts = (debug => 0);
        @res = ();
        if (get_packages(\@res, \%opts, undef, package => "$opkg") == 0) {
            carp "ERROR: Impossible to query database";
            return -1;
        }
        if (scalar (@res) == 0) {
            # TODO: we should save real OPKG data and not only the name
            my %opkg_data = (package => $opkg);
            my (%table_fields_hash, @error_strings);
            if (insert_opkgs (\%opkg_data)) {
                carp "ERROR: Impossible to insert the new OPKGs";
                return -1;
            }
        }
    }

    # Then we store selection data
    if (update_selection_data (%selection_data)) {
        carp "ERROR: Impossible to update selection data";
        return -1;
    }

    return 0;
}

################################################################################
# Return all selection data, i.e., the content of the Group_Packages table.    #
#                                                                              #
# Input: a list of package name, if undef, we assume we want all of them
# Return: hash with OPKG selection data, undef if error.                       #
#         Example: { 'lam' => SELECTED, 'openmpi' => UNSELECTED }              #
################################################################################
sub get_opkgs_selection_data {
    my @opkgs = @_;
    my %selection_data;

    # Make sure we understand that we want to get data for all available OPKGs
    if (scalar (@opkgs) == 1 && (!defined $opkgs[0] || $opkgs[0] eq "all")) {
	delete ($opkgs[0]);
    }

    my $sql = "SELECT * FROM Group_Packages WHERE group_name='oscar_server'";
    my @res = ();
    if (OSCAR::Database_generic::do_select ($sql, \@res, undef, undef) == 0) {
        carp "ERROR: Impossible to query Group_Packages ($sql)\n";
        return undef;
    }
    foreach my $ref (@res){
        my $opkg = $$ref{package};
        my $cur_selection = $$ref{selected};
        if (scalar (@opkgs) == 0
            || OSCAR::Utils::is_element_in_array ($opkg, @opkgs)) {
            $selection_data{$opkg} = $cur_selection;
        }
    }

    return %selection_data;
}

# Returns the name of all selected OPKGs.
#
# Input: None
# Return: an array of OPKGs names (the selected OPKGs).
sub get_selected_opkgs () {
    my @selected_opkgs;

    my $sql = "SELECT * FROM Group_Packages WHERE group_name='oscar_server' ".
              "and selected='".OSCAR::ODA_Defs::SELECTED()."'";

    my @res = ();
    if (OSCAR::Database_generic::do_select ($sql, \@res, undef, undef) == 0) {
        carp "ERROR: Impossible to query Group_Packages ($sql)\n";
        return undef;
    }
    foreach my $ref (@res){
        my $opkg = $$ref{package};
        push (@selected_opkgs, $opkg);
    }

    return @selected_opkgs
}

1;

__END__

=head1 NAME

Database - Perl module for the utilisation of the OSCAR database.

=head1 APIs Description

=head2 Database Connection/Disconnection API

The function database_connect allows the connection to the database. This
initialization step is mandatory before to try to read/write data from/to the
database:

database_connect ( $options_ref, $error_strings_ref );

where options_ref is a reference to a hash representing database options, and
error_strings_ref is a reference to an array that specifies extra debugging
information. Those two parameters can be undefined.
The function returns non-zero if success.

The function database_disconnect allows the disconnection from the database.
This initialization step is mandatory to finalize the database usage:

database_disconnect ( $options_ref, $error_strings_ref );

where options_ref is a reference to a hash representing database options, and
error_strings_ref is a reference to an array that specifies extra debugging
information. Those two parameters can be undefined.
The function returns non-zero if success.

=head2 OPKG Management API

=head3 OPKG Addition

To add a specific OPKG:
insert_opkgs (\%opkgs);
where opkgs is a hash gathering all OPKG data which has the following contents:
my %opkg = %{$o{$package}};
where $o is the hash of OpkgDB::opkg_hash_available and $package is one the 
oscar package name. So, %opkg would look like this (as an example, we take 
yume):

$VAR1 = {
          'distro' => 'fc-9-x86_64',
          'version' => '2.7-1',
          'packager' => 'Erich Focht <efocht@hpce.nec.com>',
          'description' => ' Tool for setting up, exporting yum repositories and 
executing yum commands for only these repositories. Use it as high level RPM 
replacement which resolves dependencies automatically. This tool is very useful 
for clusters. It can: - prepare an rpm repository - export it through apache - 
execute yum commands applying only to this repository (locally) - execute yum 
commands on the cluster nodes applying only to this repository. This makes 
installing packages, creating cluster node images, updating revisions much 
simpler than with rpm.

This is the server part of yume.

',
          'package' => 'yume',
          'group' => 'System Environment/Base',
          'summary' => 'Tools for rpm repository control, image creation and 
          'maintenance',
          'class' => 'core'
        };

=head3 OPKG Removal

delete_package ( $options_ref, $errors_ref, %sel );

where:

- options_ref is a reference to a hash specifying the action options (may be
              undef),

- $errors_ref is a reference to an array giving extra debugging information that
              needs to be displayed when errors occur,

- sel is a hash describing the package, a typical example is %sel = (package => 
      $pkg, distro => $distro_string, version => $version ),

=head3 Get data about OPKGs

get_packages (\@res, \%opts, $error_ref, %sel)

where:

- res is an array of pointers to hashes, each hash being similar to:

$VAR1 = {
          'distro' => 'fc-9-x86_64',
          'version' => '1.1.1-1',
          'packager' => 'Geoffroy Vallee',
          'description' => 'Description of package1',
          'package' => 'package1',
          'group' => 'System Environment/Base',
          'summary' => 'Summary of the package',
          'class' => 'core'
        };

- options_ref is a reference to a hash specifying the action options (may be
              undef),

- $errors_ref is a reference to an array giving extra debugging information that
              needs to be displayed when errors occur,

- sel is a hash describing the package, a typical example is %sel = (package => 
      $pkg, distro => $distro_string, version => $version ),

Example:

To get the list of OPKGs available for Debian-4-i386:

get_packages (\@opkgs_data, \%options, undef, distro => 'debian-4-i386');

=head2 OPKG Selection - Selector API

Data from Selector is saved in the Group_Packages table: the OPKGs can actually
be selected before the definition of compute nodes; this selection data is in
fact a fairly static configuration data, and is not related to the tracking of
the status of OPKGs on nodes during and after deployment.

=head3 API for Setting Selection Information

To set selection information, the following function is available:
my $return_code = OSCAR::Database::set_opkgs_selection_data (%opkgs_data);

=head3 API for Getting Selection Information

To get selection information, the following function is available:
my %results = OSCAR::Database::get_opkgs_selection_data ();

=head2 Image Management API

An API allows one to save image data in ODA:

=over 8

=item my $image_ref = ();

=item my $options_ref = undef; # options

=item my $error_ref = undef;   # error/debugging messages

=item my $rc = set_images ($image_ref, $options_ref, $error_ref);

=cut

