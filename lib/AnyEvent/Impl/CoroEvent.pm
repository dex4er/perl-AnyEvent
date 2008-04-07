package AnyEvent::Impl::CoroEvent;

use base qw(AnyEvent::Impl::Coro AnyEvent::Impl::Event);

use strict;
no warnings;

use Coro::Event ();

1

