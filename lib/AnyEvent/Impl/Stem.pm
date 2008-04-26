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

   my $stem = new Stem::Event::Timer
      object => (bless \\$arg{cb}),
      method => "timeout",
      delay  => $arg{after};

   bless \\$stem
}

sub io {
   my ($class, %arg) = @_;

   my $stem = $arg{poll} eq "r"
      ? new Stem::Event::Read
         object => (bless \\$arg{cb}),
         method => "invoke",
         fh     => $arg{fh},
      : new Stem::Event::Write
         object => (bless \\$arg{cb}),
         method => "invoke",
         fh     => $arg{fh};

   bless \\$stem
}

sub signal {
   my ($class, %arg) = @_;

   my $stem = new Stem::Event::Signal
         object => (bless \\$arg{cb}),
         method => "invoke",
         signal => $arg{signal};

   bless \\$stem
}

sub DESTROY {
   warn "xcandel <@_>\n";#d#
   ${${$_[0]}}->cancel;
}

sub invoke {
   warn "invoke <@_>\n";#d#
   ${${$_[0]}}->();
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

sub stopbusywaiting {
   Stem::Event::stop_loop;
}

sub one_event {
   # busy waiting... good design...
   my $stopper = new Stem::Event::Timer
      object => __PACKAGE__,
      method => "stopbusywaiting",
      delay  => 0.05;

   Stem::Event::start_loop;
   
   $stopper->cancel;
}

sub wait {
   one_event
      while !${$_[0]};
}

1;

=head1 SEE ALSO

L<AnyEvent>, L<Stem>.

=head1 AUTHOR

 Marc Lehmann <schmorp@schmorp.de>
 http://home.schmorp.de/

=cut

