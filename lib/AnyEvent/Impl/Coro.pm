package AnyEvent::Impl::Coro;

use base AnyEvent::Impl::Event;

use Coro::Event ();
use Coro::Signal ();

sub condvar {
   new Coro::Signal
}

1

