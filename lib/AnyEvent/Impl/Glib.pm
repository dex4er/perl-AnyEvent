package AnyEvent::Impl::Glib;

use Glib ();

my $maincontext = Glib::MainContext->default;

my %RWE = (
   in  => 'r',
   out => 'w',
   pri => 'e',
);

sub io {
   my ($class, %arg) = @_;
   
   my $self = \%arg, $class;
   my $rcb = \$self->{cb};

   my @cond;
   push @cond, "in"  if $self->{poll} =~ /r/i;
   push @cond, "out" if $self->{poll} =~ /w/i;
   push @cond, "pri" if $self->{poll} =~ /e/i;

   $self->{source} = add_watch Glib::IO fileno $self->{fh}, \@cond, sub {
      $$rcb->(join "", map $RWE{$_}, @{ $_[1] });
      ! ! $$rcb
   };

   $self
}

sub timer {
   my ($class, %arg) = @_;
   
   my $self = \%arg, $class;
   my $cb = $self->{cb};

   $self->{source} = add Glib::Timeout $self->{after} * 1000, sub {
      $cb->();
      0
   };

   $self
}

sub cancel {
   my ($self) = @_;

   return unless HASH:: eq ref $self;

   remove Glib::Source delete $self->{source} if $self->{source};
   $self->{cb} = undef;
   delete $self->{cb};
}

sub DESTROY {
   my ($self) = @_;

   $self->cancel;
}

sub condvar {
   my $class = shift;

   bless \my $x, $class;
}

sub broadcast {
   ${$_[0]}++
}

sub wait {
   $maincontext->iteration (1) while !${$_[0]};
}

$AnyEvent::MODEL = __PACKAGE__;

1;

