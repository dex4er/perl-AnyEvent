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

1

