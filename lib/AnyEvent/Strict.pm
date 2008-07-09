package AnyEvent::Strict;

# supply checks for argument validity for many functions
# this is an internal module. although it could be loaded
# at any time, this is not really documented.

use Carp qw(croak);
use AnyEvent ();

AnyEvent::post_detect {
   # assume the first ISA member is the implementation
   # # and link us in before it in the chain.
   my $MODEL = shift @AnyEvent::ISA;
   unshift @ISA, $MODEL;
   unshift @AnyEvent::ISA, AnyEvent::Strict::
};

sub io {
   my $class = shift;
   my %arg = @_;

   ref $arg{cb}
      or croak "AnyEvent->io called with illegal cb argument '$arg{cb}'";
   delete $arg{cb};
 
   fileno $arg{fh}
      or croak "AnyEvent->io called with illegal fh argument '$arg{fh}'";
   delete $arg{fh};
 
   $arg{poll} =~ /^[rw]$/
      or croak "AnyEvent->io called with illegal poll argument '$arg{poll}'";
   delete $arg{poll};
 
   croak "AnyEvent->io called with unsupported parameter(s) " . join ", ", keys %arg
      if keys %arg;

   $class->SUPER::io (@_)
}

sub timer {
   my $class = shift;
   my %arg = @_;

   ref $arg{cb}
      or croak "AnyEvent->timer called with illegal cb argument '$arg{cb}'";
   delete $arg{cb};
 
   exists $arg{after}
      or croak "AnyEvent->timer called without mandatory 'after' parameter";
   delete $arg{after};
 
   !$arg{interval} or $arg{interval} > 0
      or croak "AnyEvent->timer called with illegal interval argument '$arg{interval}'";
   delete $arg{interval};
 
   croak "AnyEvent->timer called with unsupported parameter(s) " . join ", ", keys %arg
      if keys %arg;

   $class->SUPER::timer (@_)
}

sub signal {
   my $class = shift;
   my %arg = @_;

   ref $arg{cb}
      or croak "AnyEvent->signal called with illegal cb argument '$arg{cb}'";
   delete $arg{cb};
 
   eval "require POSIX; 0 < &POSIX::SIG$arg{signal}"
      or croak "AnyEvent->signal called with illegal signal name '$arg{signal}'";
   delete $arg{signal};
 
   croak "AnyEvent->signal called with unsupported parameter(s) " . join ", ", keys %arg
      if keys %arg;

   $class->SUPER::signal (@_)
}

sub child {
   my $class = shift;
   my %arg = @_;

   ref $arg{cb}
      or croak "AnyEvent->signal called with illegal cb argument '$arg{cb}'";
   delete $arg{cb};
 
   $arg{pid} =~ /^-?\d+$/
      or croak "AnyEvent->signal called with illegal pid value '$arg{pid}'";
   delete $arg{pid};
 
   croak "AnyEvent->signal called with unsupported parameter(s) " . join ", ", keys %arg
      if keys %arg;

   $class->SUPER::child (@_)
}

sub condvar {
   my $class = shift;
   my %arg = @_;

   !exists $arg{cb} or ref $arg{cb}
      or croak "AnyEvent->condvar called with illegal cb argument '$arg{cb}'";
   delete $arg{cb};
 
   croak "AnyEvent->condvar called with unsupported parameter(s) " . join ", ", keys %arg
      if keys %arg;

   $class->SUPER::condvar (@_)
}

sub time {
   my $class = shift;

   @_
      and croak "AnyEvent->time wrongly called with paramaters";

   $class->SUPER::time (@_)
}

sub now {
   my $class = shift;

   @_
      and croak "AnyEvent->now wrongly called with paramaters";

   $class->SUPER::now (@_)
}

1
