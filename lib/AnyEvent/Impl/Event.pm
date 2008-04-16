=head1 NAME

AnyEvent::Impl::Event - AnyEvent adaptor for Event

=head1 SYNOPSIS

  use AnyEvent;
  use EV;

  # this module gets loaded automatically as required

=head1 DESCRIPTION

This module provides transparent support for AnyEvent. You don't have to
do anything to make Event work with AnyEvent except by loading Event before
creating the first AnyEvent watcher.

=cut

package AnyEvent::Impl::Event;

no warnings;
use strict;

use Event ();

sub io {
   my ($class, %arg) = @_;
   $arg{fd} = delete $arg{fh};
   bless \(Event->io (%arg)), $class
}

sub timer {
   my ($class, %arg) = @_;
   my $cb = delete $arg{cb};
   bless \(Event->timer (
      %arg,
      cb => sub {
         $_[0]->w->cancel;
         $cb->();
      },
   )), $class
}

sub signal {
   my ($class, %arg) = @_;
   bless \(Event->signal (%arg)), $class
}

sub DESTROY {
   ${$_[0]}->cancel;
}

sub one_event {
   Event::one_event;
}

1;

=head1 SEE ALSO

  L<AnyEvent>, L<Event>.

=head1 AUTHOR

 Marc Lehmann <schmorp@schmorp.de>
 http://home.schmorp.de/

=cut

