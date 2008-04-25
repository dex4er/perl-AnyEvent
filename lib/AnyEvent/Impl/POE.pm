=head1 NAME

AnyEvent::Impl::POE - AnyEvent adaptor for POE

=head1 SYNOPSIS

  use AnyEvent;
  use POE;

  # this module gets loaded automatically as required

=head1 DESCRIPTION

This module provides transparent support for AnyEvent. You don't have to
do anything to make POE work with AnyEvent except by loading POE before
creating the first AnyEvent watcher.

POE is badly designed, badly documented and badly implemented.

Here is why, and what it means to you if you want to be interoperable with
it:

=over 4

=item Weird messages

If you only use C<run_one_timeslice>, POE will print an ugly,
unsupressable, message at program exit:

   Sessions were started, but POE::Kernel's run() method was never...

The message is correct, the question is why POE prints it in the first
place in a correct program (this is not a singular case though).

The only way I found to work around this bug was to call C<<
->run >> at anyevent loading time and stop the kernel imemdiately
again. Unfortunately, due to another design bug in POE, this cannot be
done (by documented means at least) without throwing away events in the
event queue.

This means that you will either have to live with lost events or you have
to make sure to load AnyEvent early enough (this is usually not that
difficult in a main program, but hard in a module).

=item One session per Event

AnyEvent has to create one POE::Session per event watcher, which is
immsensely slow and makes watchers very large.

=item One watcher per fd/event combo

POE, of course, suffers from the same bug as Tk and some other badly
designed event models in that it doesn't support multiple watchers per
fd/poll combo.

=back

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

   # cygwin requires the fh mode to be matching, unix doesn't
   my ($pee, $mode) = $poll eq "r" ? ("select_read" , "<")
                    : $poll eq "w" ? ("select_write", ">")
                    : Carp::croak "AnyEvent->io requires poll set to either 'r' or 'w'";

   open my $fh, "$mode&" . fileno $arg{fh}
      or die "cannot dup() filehandle: $!";

   my $session = POE::Session->create (
      inline_states => {
         _start => sub {
            $_[KERNEL]->$pee ($fh => "ready");
         },
         ready => sub {
            $cb->();
         },
         stop => sub {
            $_[KERNEL]->$pee ($fh);
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

