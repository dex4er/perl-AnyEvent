package AnyEvent::Impl::CoroEV;

use base AnyEvent::Impl::EV;

use strict;
no warnings;

use Coro::EV ();
use Coro::Signal ();

sub condvar {
   new Coro::Signal
}

1

