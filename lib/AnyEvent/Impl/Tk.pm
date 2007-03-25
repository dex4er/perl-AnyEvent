package AnyEvent::Impl::Tk;

no warnings;
use strict;

use Tk ();

my $mw = new MainWindow;
$mw->withdraw;

sub io {
   my ($class, %arg) = @_;
   
   my $self = bless \%arg, $class;
   my $cb = $self->{cb};

   $mw->fileevent ($self->{fh}, readable => sub { $cb->() })
      if $self->{poll} eq "r";
   $mw->fileevent ($self->{fh}, writable => sub { $cb->() })
      if $self->{poll} eq "w";

   $self
}

sub timer {
   my ($class, %arg) = @_;
   
   my $self = bless \%arg, $class;
   my $rcb = \$self->{cb};

   $mw->after ($self->{after} * 1000, sub {
      $$rcb->() if $$rcb;
   });

   $self
}

sub cancel {
   my ($self) = @_;

   $mw->fileevent ($self->{fh}, readable => "")
      if $self->{poll} eq "r";
   $mw->fileevent ($self->{fh}, writable => "")
      if $self->{poll} eq "w";

   undef $self->{cb};
   delete $self->{cb};
}

sub DESTROY {
   my ($self) = @_;

   $self->cancel;
}

sub one_event {
   Tk::DoOneEvent (0);
}

1

