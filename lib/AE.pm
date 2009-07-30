=head1 NAME

AE - simpler/faster/newer/cooler AnyEvent API

=head1 SYNOPSIS

See the L<AnyEvent> manpage for everything there is to say about AE.

=head1 DESCRIPTION

This module implements the new simpler AnyEvent API. There is no
description of this API here, refer to the L<AnyEvent> module for this.

The rationale for the new API is that experience with L<EV> shows that
this API actually "works", despite it's simplicity. This API is (will be)
much faster and also requires less typing.

The "old" API is still supported, and there are no plans to "switch".

=cut

package AE;

use AnyEvent (); # BEGIN { AnyEvent::common_sense }

1;

=head1 AUTHOR

 Marc Lehmann <schmorp@schmorp.de>
 http://home.schmorp.de/

=cut

