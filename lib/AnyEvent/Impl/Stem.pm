=head1 NAME

AnyEvent::Impl::Stem - AnyEvent adaptor for Stem

=head1 SYNOPSIS

  use AnyEvent;
  use Stem;

  # this module gets loaded automatically as required

=head1 DESCRIPTION

This module provides transparent support for AnyEvent. You don't have to
do anything to make Stem work with AnyEvent except by loading Stem before
creating the first AnyEvent watcher.

=cut

package AnyEvent::Impl::Stem;

use strict;

BEGIN { $Stem::Vars::Env{ 'event_loop' } = "xxx" } #d#

use Stem::Event;
use Stem::Class; #???

sub timer {
   my ($class, %arg) = @_;

   #TODO: when the returned object goes out of scope the timer needs to be canceled
   new Stem::Event::Timer
      object => (bless \\$arg{cb}),
      method => "timeout",
      delay  => $arg{after},
}

sub io {
   my ($class, %arg) = @_;

   # likewise here, likely we must wrap and bless and call stop in DESTROY
   if ($arg{poll} eq "r") {
      new Stem::Event::Read
         object => (bless \\$arg{cb}),
         method => "invoke",
         fh     => $arg{fh},
   } else {
      new Stem::Event::Write
         object => (bless \\$arg{cb}),
         method => "invoke",
         fh     => $arg{fh},
   }
}

sub signal {
   my ($class, %arg) = @_;

   # liekwise here, no clue how to cancel this
   new Stem::Event::Signal
         object => (bless \\$arg{cb}),
         method => "invoke",
         signal => $arg{signal},
}

sub invoke {
   ${${$_[0]}}();
}

sub child {
   my ($class, %arg) = @_;

   die;

#   # seems there is special sigchld support in stem, this needs to be used
#   EV::child $arg{pid}, 0, sub {
#      $cb->($_[0]->rpid, $_[0]->rstatus);
#   }
}

sub condvar {
   bless \my $flag, AnyEvent::Impl::Stem::
}

sub broadcast {
   ++${$_[0]};
}

sub wait {
   one_event
      while !${$_[0]};
}

sub one_event {
   Stem::Event::start_loop;
}

1;

=head1 SEE ALSO

L<AnyEvent>, L<Stem>.

=head1 AUTHOR

 Marc Lehmann <schmorp@schmorp.de>
 http://home.schmorp.de/

=cut

