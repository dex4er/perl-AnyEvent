package AnyEvent::Impl::Event;

no warnings;

use Event ();

sub io {
   my ($class, %arg) = @_;
   $arg{fd} = delete $arg{fh};
   bless \(Event->io (%arg)), $class
}

sub timer {
   my ($class, %arg) = @_;
   my $cb = delete $arg{cb};
   bless \(Event->timer (
      %arg,
      cb => sub {
         $_[0]->w->cancel;
         $cb->();
      },
   )), $class
}

sub signal {
   my ($class, %arg) = @_;
   bless \(Event->signal (%arg)), $class
}

sub DESTROY {
   ${$_[0]}->cancel;
}

sub condvar {
   my $class = shift;

   bless \my $flag, $class
}

sub broadcast {
   ${$_[0]}++;
}

sub wait {
   Event::one_event while !${$_[0]};
}

sub one_event {
   Event::one_event;
}

1

