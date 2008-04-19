=head1 NAME

AnyEvent::Impl::CoroEV - AnyEvent adaptor for Coro::EV, EV

=head1 SYNOPSIS

  use AnyEvent;
  use EV;

  # this module gets loaded automatically as required

=head1 DESCRIPTION

This module provides transparent support for AnyEvent. You don't have to
do anything to make Coro::EV work with AnyEvent except by loading Coro::EV
before creating the first AnyEvent watcher.

Unlike all other event models, Coro::EV models allow recursion in condvars
(see L<AnyEvent>, C<< $condvar->wait >>), I<as long as this is done from
different coroutines>.

See L<AnyEvent::Impl::Coro> and L<Coro::EV> for more details about L<Coro>
integration.

=cut

package AnyEvent::Impl::CoroEV;

use base qw(AnyEvent::Impl::Coro AnyEvent::Impl::EV);

use strict;
no warnings;

use Coro::EV ();

1;

=head1 SEE ALSO

L<AnyEvent>, L<AnyEvent::Impl::Coro>, L<Coro::EV>.

=head1 AUTHOR

 Marc Lehmann <schmorp@schmorp.de>
 http://home.schmorp.de/

=cut


