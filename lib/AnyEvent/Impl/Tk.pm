package AnyEvent::Impl::Tk;

use Tk ();

my $mw = new MainWindow;
$mw->withdraw;

sub io {
   my ($class, %arg) = @_;
   
   my $self = \%arg, $class;
   my $rcb = \$self->{cb};

   $mw->fileevent ($self->{fh}, readable => sub { $$rcb->("r") })
      if $self->{poll} =~ /r/i;
   $mw->fileevent ($self->{fh}, writable => sub { $$rcb->("w") })
      if $self->{poll} =~ /w/i;

   $self
}

sub timer {
   my ($class, %arg) = @_;
   
   my $self = \%arg, $class;
   my $rcb = \$self->{cb};

   $mw->after ($self->{after} * 1000, sub {
      $$rcb->() if $$rcb;
   });

   $self
}

sub cancel {
   my ($self) = @_;

   return unless HASH:: eq ref $self;

   $mw->fileevent ($self->{fh}, readable => "")
      if $self->{poll} =~ /r/i;
   $mw->fileevent ($self->{fh}, writable => "")
      if $self->{poll} =~ /w/i;

   undef $self->{cb};
   delete $self->{cb};
}

sub DESTROY {
   my ($self) = @_;

   $self->cancel;
}

sub condvar {
   my $class = shift;

   bless \my $x, $class
}

sub broadcast {
   ${$_[0]}++
}

sub wait {
   Tk::DoOneEvent (0) while !${$_[0]};
}

$AnyEvent::MODEL = __PACKAGE__;

1

