package AnyEvent::Impl::Event;

use Event ();

sub io {
   my ($class, %arg) = @_;
   $arg{fd} = delete $arg{fh};
   my $rcb = \$arg{cb};
   bless \(my $x = Event->io (
      %arg,
      cb => sub {
         $$rcb->($_[0]->got . "")
      },
   )), $class
}

sub timer {
   my ($class, %arg) = @_;
   my $rcb = \$arg{cb};
   bless \(my $x = Event->timer (
      %arg,
      cb => sub {
         $$rcb->();
      },
   )), $class
}

sub cancel {
   my ($self) = @_;

   return unless HASH:: eq ref $self;

   $$self->cancel;
}

sub DESTROY {
   my ($self) = @_;

   $$self->cancel;
}

sub condvar {
   my $class = shift;

   bless \my $x, $class
}

sub broadcast {
   ${$_[0]}++
}

sub wait {
   Event::one_event() while !${$_[0]};
}

$AnyEvent::MODEL = __PACKAGE__;

1

