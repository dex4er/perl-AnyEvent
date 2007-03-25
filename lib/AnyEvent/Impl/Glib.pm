package AnyEvent::Impl::Glib;

no warnings;
use strict;

use Glib ();

my $maincontext = Glib::MainContext->default;

sub io {
   my ($class, %arg) = @_;
   
   my $self = bless \%arg, $class;
   my $rcb = \$self->{cb};

   # some glibs need hup, others error with it, YMMV
   push @cond, "in",  "hup" if $self->{poll} eq "r";
   push @cond, "out", "hup" if $self->{poll} eq "w";

   $self->{source} = add_watch Glib::IO fileno $self->{fh}, \@cond, sub {
      $$rcb->();
      ! ! $$rcb
   };

   $self
}

sub timer {
   my ($class, %arg) = @_;
   
   my $self = bless \%arg, $class;
   my $cb = $self->{cb};

   $self->{source} = add Glib::Timeout $self->{after} * 1000, sub {
      $cb->();
      0
   };

   $self
}

sub DESTROY {
   my ($self) = @_;

   remove Glib::Source delete $self->{source} if $self->{source};
   # need to undef $cb because we hold references to it
   $self->{cb} = undef;
   %$self = ();
}

sub one_event {
   $maincontext->iteration (1);
}

1

