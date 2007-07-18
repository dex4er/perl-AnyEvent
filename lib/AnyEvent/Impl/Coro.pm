package AnyEvent::Impl::Coro;

use base AnyEvent::Impl::Event;

use strict;
no warnings;

use Coro::Event ();
use Coro::Signal ();

sub condvar {
   new Coro::Signal
}

1

