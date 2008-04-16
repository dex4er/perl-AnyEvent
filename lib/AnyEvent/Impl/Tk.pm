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

   # cygwin requires the fh mode to be matching, unix doesn't
   my ($tk, $mode) = $self->{poll} eq "r" ? ("readable", "<")
                   : $self->{poll} eq "w" ? ("writable", ">")
                   : Carp::croak "AnyEvent->io requires poll set to either 'r' or 'w'";

   # work around these bugs in Tk:
   # - removing a callback will destroy other callbacks
   # - removing a callback might crash
   # - adding a callback might destroy other callbacks
   # - only one callback per fh
   # - only one clalback per fh/poll combination
   open $self->{fh2}, "$mode&" . fileno $self->{fh}
      or die "cannot dup() filehandle: $!";

   eval { fcntl $self->{fh2}, &Fcntl::F_SETFD, &Fcntl::FD_CLOEXEC }; # eval in case paltform doesn't support it
   
   $mw->fileevent ($self->{fh2}, $tk => $cb);

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

   if (my $fh = delete $self->{fh2}) {
      # work around another bug: watchers don't get removed when
      # the fh is closed contrary to documentation.
      $mw->fileevent ($fh, readable => "");
      $mw->fileevent ($fh, writable => "");
   }

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

