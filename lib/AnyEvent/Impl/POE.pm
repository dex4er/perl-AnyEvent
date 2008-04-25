=head1 NAME

AnyEvent::Impl::POE - AnyEvent adaptor for POE

=head1 SYNOPSIS

  use AnyEvent;
  use EV;

  # this module gets loaded automatically as required

=head1 DESCRIPTION

This module provides transparent support for AnyEvent. You don't have to
do anything to make POE work with AnyEvent except by loading POE before
creating the first AnyEvent watcher.

- one session per event
- messages output
- time vs. gettimeofday
- bad documentation, missing etc.
- timeout order
- no support for child watchers

       Terminal signals will kill sessions if they are not handled by a "sig_handled"() call.  The OS signals that usually kill or dump a process are con‐
              sidered terminal in POE, but they never trigger a coredump.  These are: HUP, INT, QUIT and TERM.


=cut

package AnyEvent::Impl::POE;

no warnings;
use strict;

use POE;

# have to do this to keep POE from spilling ugly messages
POE::Session->create (inline_states => { _start => sub { @_[KERNEL]->stop } });
POE::Kernel->run;

sub io {
   my ($class, %arg) = @_;
   my $poll = delete $arg{poll};
   my $cb   = delete $arg{cb};
   my $fh   = delete $arg{fh};
   my $id;
   my $session = POE::Session->create (
      inline_states => {
         _start => sub {
            $poll eq "r" ? $_[KERNEL]->select_read  ($fh => "ready")
                         : $_[KERNEL]->select_write ($fh => "ready")
         },
         ready => sub {
            $cb->();
         },
         stop => sub {
            $poll eq "r" ? $_[KERNEL]->select_read  ($fh)
                         : $_[KERNEL]->select_read  ($fh)
         },
      },
   );
   bless \\$session, AnyEvent::Impl::POE::
}

sub timer {
   my ($class, %arg) = @_;
   my $after = delete $arg{after};
   my $cb   = delete $arg{cb};
   my $session = POE::Session->create (
      inline_states => {
         _start => sub {
            $_[KERNEL]->delay_set (timeout => $after);
         },
         timeout => sub {
            $cb->();
         },
         stop => sub {
            $_[KERNEL]->alarm_remove_all;
         },
      },
   );
   bless \\$session, AnyEvent::Impl::POE::
}

sub signal {
   my ($class, %arg) = @_;
   my $signal = delete $arg{signal};
   my $cb     = delete $arg{cb};
   my $session = POE::Session->create (
      inline_states => {
         _start => sub {
            $_[KERNEL]->sig ($signal => "catch");
            $_[KERNEL]->refcount_increment ($_[SESSION]->ID => "poe");
         },
         catch => sub {
            $cb->();
            $_[KERNEL]->sig_handled;
         },
         stop => sub {
            $_[KERNEL]->refcount_decrement ($_[SESSION]->ID => "poe");
            $_[KERNEL]->sig ($signal);
         },
      },
   );
   bless \\$session, AnyEvent::Impl::POE::
}

sub DESTROY {
   POE::Kernel->post (${${$_[0]}}, "stop");
}

sub one_event {
   POE::Kernel->loop_do_timeslice;
}

1;

=head1 SEE ALSO

L<AnyEvent>, L<POE>.

=head1 AUTHOR

 Marc Lehmann <schmorp@schmorp.de>
 http://home.schmorp.de/

=cut

