package AnyEvent::Impl::Event;

use Event ();

sub io {
   my ($class, %arg) = @_;
   $arg{fd} = delete $arg{fh};
   my $cb = $arg{cb};
   bless \(my $x = Event->io (
      %arg,
      cb => $arg{cb},
   )), $class
}

sub timer {
   my ($class, %arg) = @_;
   my $cb = $arg{cb};
   bless \(my $x = Event->timer (
      %arg,
      cb => sub {
         $_[0]->w->cancel;
         $cb->();
      },
   )), $class
}

sub DESTROY {
   my ($self) = @_;

   $$self->cancel;
   %$self = ();
}

sub condvar {
   my $class = shift;

   bless \my $flag, $class
}

sub broadcast {
   ${$_[0]}++;
}

sub wait {
   Event::one_event() while !${$_[0]};
}

1

