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

__END__

=head1

This Perl modules defines few constants use in the context of ODA. This allows us to provide a single location for the definition of constants used by "components" that have an interface with ODA, and therefore avoid bugs.

=head1 Exported Symbols

=head2 OSCAR Package Selection Flags

=over 4

=item SELECTION_DEFAULT

Selector has not touched the field used during the creation of new entries in ODA.

=item UNSELECTED

Value used to specify that a given OPKG is not selected.

=item SELECTED

Value used to specify that a given OPKG is selected.

=back

=head2 OSCAR Package Status Flags

=over 4

=item SHOULD_NOT_BE_INSTALLED

Value used to specify that a given OPKG should not be installed.

=item SHOULD_BE_INSTALLED

Value used to specify that a given OPKG should be installed.

=item FINISHED

???

=back

=head1 Author

Geoffroy Vallee, Oak Ridge National Laboratory

=cut


