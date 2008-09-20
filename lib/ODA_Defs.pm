package OSCAR::ODA_Defs;

# $Id$
#
# Copyright (c) 2008 Geoffroy Vallee <valleegr@ornl.gov>
#                    Oak Ridge National Laboratory.
#                    All rights reserved.

use strict;
use base qw(Exporter);

###################
# SELECTION FLAGS #
###################
use constant SELECTION_DEFAULT  => 0; # Selector has not touched the field
                                      # used during the creation of new entries
                                      # in ODA.
use constant UNSELECTED         => 1;
use constant SELECTED           => 2;

########################
# PACKAGE STATUS FLAGS #
########################
use constant SHOULD_NOT_BE_INSTALLED    => 1;
use constant SHOULD_BE_INSTALLED        => 2;
use constant FINISHED                   => 8;

my @ISA = qw(Exporter);

our @EXPORT = qw(
                SELECTION_DEFAULT
                UNSELECTED
                SELECTED
                SHOULD_NOT_BE_INSTALLED
                SHOULD_BE_INSTALLED
                FINISHED
                );

1;
