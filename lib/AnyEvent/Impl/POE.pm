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

Unfortunately, POE isn't generic enough to implement a fully working
AnyEvent backend: POE is too badly designed, too badly documented and too
badly implemented.

Here are the details, and what it means to you if you want to be
interoperable with POE:

=over 4

=item Weird messages

If you only use C<run_one_timeslice> (as AnyEvent has to for it's
condition variables), POE will print an ugly, unsupressable, message at
program exit:

   Sessions were started, but POE::Kernel's run() method was never...

The message is correct, the question is why POE prints it in the first
place in a correct program (this is not a singular case though).

The only way I found to work around this bug was to call C<<
->run >> at AnyEvent loading time and stop the kernel immediately
again. Unfortunately, due to another design bug in POE, this cannot be
done (by documented means at least) without throwing away events in the
event queue.

This means that you will either have to live with lost events or you have
to make sure to load AnyEvent early enough (this is usually not that
difficult in a main program, but hard in a module).

=item One session per Event

AnyEvent has to create one POE::Session per event watcher, which is
immensely slow and makes watchers very large. The reason for this is
lacking lifetime management (mostly undocumented, too). Without one
session/watcher it is not possible to easily keep the kernel from running
endlessly.

=item One watcher per fd/event combo

POE, of course, suffers from the same bug as Tk and some other badly
designed event models in that it doesn't support multiple watchers per
fd/poll combo. The workaround is the same as with Tk: AnyEvent::Impl::POE
creates a separate file descriptor to hand to POE, which isn't fast and
certainly not nice to your resources.

=item Timing Deficiencies

POE manages to not have a function that returns the current time. This is
extremely problematic, as POE can use different time functions, which can
differ by more than a second. In addition, most timer functions in POE
want an absoltue timestamp, which is hard to create if all you have is a
relative time and no function to return the "current time".

AnyEvent works around this by using relative timer fucntions, in the hope
that POE gets it right at least internally.

=item Event Non-Ordering

POE cannot guarentee the order of callback invocation for timers, and
usually gets it wrong. That is, if you have two timers, one timing out
after another, the callbacks might be called in reverse order.

How one manages to even implement stuff that way escapes me.

=item Child Watchers

POE offers child watchers - which is a laudable thing, few event loops
do. Unfortunately, they cannot even implement AnyEvent's simple child
watchers: they are not generic enough.

Therefore, AnyEvent has to resort to it's own SIGCHLD management, which
may interfere with POE.

=item Documentation Quality

At the time of this writing, POE was in its tenth year. Still, its
documentation is extremely lacking, making it impossible to implement
stuff as trivial as AnyEvent watchers without havign to resort to
undocumented behaviour or features.

For example, the POE::Kernel manpage has nice occurances of the word TODO
with an explanation of whats missing. Some other gems:

   This allows many object methods to also be package methods.

This is nice, but since it doesn't document I<which> methods these are,
this is utterly useless information.

   Terminal signals will kill sessions if they are not handled by a
   "sig_handled"() call.  The OS signals that usually kill or dump a
   process are con‐ sidered terminal in POE, but they never trigger a
   coredump. These are: HUP, INT, QUIT and TERM.

Although AnyEvent calls sig_handled, removing it has no apparent effects
on POE handling SIGINT.

   Furthermore, since the Kernel keeps track of everything sessions do, it
   knows when a session has run out of tasks to perform.

This is impossible - how does the kernel now that a session is no longer
watching for some (external) event (e.g. by some other session)? It
cannot, and therefore this is wrong.

It gets worse, though - the notion of "task" or "resource", although used
throughout the documentation, is not defined in a usable way. For example,
waiting for a timeout is considered to be a task, waiting for a signal is
not. The user is left guessing when waiting for an event counts as task
and when not.

One could go on endlessly - ten years, no usable docs.

It is likely that difefrences between documentation, or the one or two
things I had to guess, cause unanticipated problems with the backend.

=item Bad API

The POE API is extremely inconsistent - sometimes you have to pass a
session argument, sometimes it gets ignored, sometimes a session-specific
method must not use a session argument.

Sometimes registering a handler uses "eventname, parameter" (timeouts),
sometimes it is "parameter, eventname" (signals). There is little
consistency.

=back

On the good side, AnyEvent allows you to write your modules in a 99%
POE-compatible way (conflicting child watchers), without forcing your
module to use POE - it is still open to better event models, of which
there are plenty.

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

