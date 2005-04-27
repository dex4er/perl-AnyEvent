package AnyEvent::Impl::Coro;

use base AnyEvent::Impl::Event;

use Coro;
use Coro::Event;
use Coro::Signal;

#############################################################################

sub new_signal {
   new Coro::Signal;
}

1;

