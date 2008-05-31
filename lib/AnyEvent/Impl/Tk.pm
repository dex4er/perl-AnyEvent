=head1 NAME

AnyEvent::Impl::Tk - AnyEvent adaptor for Tk

=head1 SYNOPSIS

   use AnyEvent;
   use Tk;
  
   # this module gets loaded automatically as required

=head1 DESCRIPTION

This module provides transparent support for AnyEvent. You don't have to
do anything to make Tk work with AnyEvent except by loading Tk before
creating the first AnyEvent watcher.

Tk is buggy. Tk is extremely buggy. Tk is so unbelievably buggy that
for each bug reported and fixed, you get one new bug followed by
reintroduction of the old bug in a later revision. I regularly run out of
words to describe how bad it really is.

To work around the many, many bugs in Tk that don't get fixed, this
adaptor dup()'s all filehandles that get passed into its I/O watchers,
so if you register a read and a write watcher for one fh, AnyEvent will
create two additional file descriptors (and handles).

This creates a high overhead and is slow, but seems to work around all
known bugs in L<Tk::fileevent>.

To be able to access the Tk event loop, this module creates a main
window and withdraws it immediately. This might cause flickering on some
platforms, but Tk perversely requires a window to be able to wait for file
handle readyness notifications. This window is always created (in this
version of AnyEvent) and can be accessed as C<$AnyEvent::Impl::Tk::mw>.

=cut

package AnyEvent::Impl::Tk;

no warnings;
use strict;

use Tk ();

our $mw = new MainWindow;
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
   # - only one callback per fh/poll combination
   open $self->{fh2}, "$mode&" . fileno $self->{fh}
      or die "cannot dup() filehandle: $!";

   eval { local $SIG{__DIE__}; fcntl $self->{fh2}, &Fcntl::F_SETFD, &Fcntl::FD_CLOEXEC }; # eval in case paltform doesn't support it
   
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

1;

=head1 SEE ALSO

L<AnyEvent>, L<Tk>.

=head1 AUTHOR

 Marc Lehmann <schmorp@schmorp.de>
 http://home.schmorp.de/

=cut


