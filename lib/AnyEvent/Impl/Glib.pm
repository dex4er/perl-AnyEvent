package AnyEvent::Impl::Glib;

use Glib ();

my $maincontext = Glib::MainContext->default;

my %RWE = (
   hup => 'rw',
   in  => 'r',
   out => 'w',
   pri => 'e',
);

sub io {
   my ($class, %arg) = @_;
   
   my $self = bless \%arg, $class;
   my $rcb = \$self->{cb};

   # some glibs need hup, others error with it, YMMV
   push @cond, "in",  "hup" if $self->{poll} =~ /r/i;
   push @cond, "out", "hup" if $self->{poll} =~ /w/i;
   push @cond, "pri"        if $self->{poll} =~ /e/i;

   $self->{source} = add_watch Glib::IO fileno $self->{fh}, \@cond, sub {
      $$rcb->(join "", map $RWE{$_}, @{ $_[1] });
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

sub cancel {
   my ($self) = @_;

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

   bless \my $x, AnyEvent::Impl::Glib::CondVar::
}

sub AnyEvent::Impl::Glib::CondVar::broadcast {
   ${$_[0]}++;
}

sub AnyEvent::Impl::Glib::CondVar::wait {
   $maincontext->iteration (1) while !${$_[0]};
}

1

