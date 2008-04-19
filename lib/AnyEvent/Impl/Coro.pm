=head1 NAME

AnyEvent::Impl::Coro - Base class for Coro::EV and Coro::Event

=head1 SYNOPSIS

  # this module gets loaded automatically as required, never
  # load it manually.

=head1 DESCRIPTION

This module provides general coro support for both
L<AnyEvent::Impl::CoroEV> and L<AnyEvent::Impl::CoroEvent>.

It is recommended to use L<Coro::unblock> to register callbacks
if your program uses Coroutines, as most event models are not
coroutine-safe/reentrant (only L<EV> is known to be).

Internally, L<Coro::Signal>'s are used to implement AnyEvent's condvars.

=cut

package AnyEvent::Impl::Coro;

use strict;
no warnings;

use Coro ();
use Coro::Signal ();

sub condvar {
   bless [], __PACKAGE__
}

sub broadcast {
   $_[0][0] = 1;
   $_[0][1]->ready if $_[0][1];
}

sub wait {
   while (!$_[0][0]) {
      local $_[0][1] = $Coro::current;
      Coro::schedule;
   }
}

1;

=head1 SEE ALSO

L<AnyEvent>, L<Coro>, L<AnyEvent::Impl::CoroEV>, L<AnyEvent::Impl::CoroEvent>.

=head1 AUTHOR

 Marc Lehmann <schmorp@schmorp.de>
 http://home.schmorp.de/

=cut


