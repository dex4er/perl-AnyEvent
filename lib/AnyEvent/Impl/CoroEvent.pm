=head1 NAME

AnyEvent::Impl::CoroEvent - AnyEvent adaptor for Coro::Event, Event

=head1 SYNOPSIS

  use AnyEvent;
  use Coro::Event;

  # this module gets loaded automatically as required

=head1 DESCRIPTION

This module provides transparent support for AnyEvent. You don't have
to do anything to make Coro::Event work with AnyEvent except by loading
Coro::Event before creating the first AnyEvent watcher.

Unlike most other event models, Coro::Event models allow recursion in
condvars (see L<AnyEvent>, C<< $condvar->wait >>), I<< as long as this is
done from different coroutines AND C<Coro::unblock> is used to register
callbacks >>. See L<AnyEvent::Coro::Event> for even less restrictions.

See L<AnyEvent::Impl::Coro> and L<Coro::Event> for more details about Coro
integration.

=cut

package AnyEvent::Impl::CoroEvent;

use base qw(AnyEvent::Impl::Coro AnyEvent::Impl::Event);

use strict;
no warnings;

use Coro::Event ();

1;

=head1 SEE ALSO

  L<AnyEvent>, L<AnyEvent::Impl::Coro>, L<Coro::Event>.

=head1 AUTHOR

 Marc Lehmann <schmorp@schmorp.de>
 http://home.schmorp.de/

=cut


