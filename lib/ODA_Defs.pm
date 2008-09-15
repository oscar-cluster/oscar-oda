###################
# SELECTION FLAGS #
###################
use constant SELECTION_DEFAULT  => 0; # Selector has not touched the field
                                      # DEPRECATED??
use constant UNSELECTED         => 1;
use constant SELECTED           => 2;

########################
# PACKAGE STATUS FLAGS #
########################
use constant SHOULD_NOT_BE_INSTALLED    => 1;
use constant SHOULD_BE_INSTALLED        => 2;
use constant FINISHED                   => 8;

1;
