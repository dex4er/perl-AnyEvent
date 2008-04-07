package AnyEvent::Impl::CoroEV;

use base qw(AnyEvent::Impl::Coro AnyEvent::Impl::EV);

use strict;
no warnings;

use Coro::EV ();

1

