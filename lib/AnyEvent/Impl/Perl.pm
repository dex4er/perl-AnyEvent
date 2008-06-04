=head1 NAME

AnyEvent::Impl::Perl - Pure-Perl event loop and AnyEvent adaptor for itself

=head1 SYNOPSIS

   use AnyEvent;
   # use AnyEvent::Impl::Perl;
  
   # this module gets loaded automatically as required

=head1 DESCRIPTION

This module provides transparent support for AnyEvent in case no other
event loop could be found or loaded. You don't have to do anything to make
it work with AnyEvent except by possibly loading it before creating the
first AnyEvent watcher.

If you want to use this module instead of autoloading another event loop
you can simply load it before creating the first watcher.

As for performance, this module is on par with (and usually faster than)
most select/poll-based C event modules such as Event or Glib (it does
not come close to EV, though), with respect to I/O watchers. Timers are
handled less optimally.

This event loop has been optimised for the following cases:

=over 4

=item monotonic clock is available

This module will use the POSIX monotonic clock option if it can be
detected at runtime, in which case it will not suffer adversely from time
jumps.

If no monotonic clock is available, this module will not attempt to
correct for time jumps in any way.

The clock chosen will be reported if the environment variable
C<$PERL_ANYEVENT_VERBOSE> is set to 8 or higher.

=item lots of watchers on one fd

This is purely a dirty benchmark optimisation not relevant in practise.
The more common case of having one watcher per fd/poll combo is
special-cased and still fast.

=item relatively few active fds per select call

This module expects that only a tiny amount of fds is active at any one
time. This is relatively typical of larger servers (but not the case where
select traditionally is fast), at the expense of the "dense activity case"
where most of fds are active (which suits select and poll). The optimal
implementation of the "dense" case is not much faster, though, so the
module should behave very well in most cases.

=item lots of timer changes/iteration, or none at all

This module sorts the timer list again on each iteration, if timers have
been created. If you add lots of timers, this is pretty efficient, but the
common case of only adding a few timers is not handled very efficiently.

This should not have much of an impact unless you have hundreds of timers,
though.

=back

=cut

package AnyEvent::Impl::Perl;

no warnings;
use strict;

use Time::HiRes ();
use Scalar::Util ();

use AnyEvent ();
use AnyEvent::Util ();

our $VERSION = 4.13;

our ($NOW, $MNOW);

BEGIN {
   local $SIG{__DIE__};

   if (0 < eval "&Time::HiRes::clock_gettime (&Time::HiRes::CLOCK_MONOTONIC)") {
      *_update_clock = sub {
         $NOW  = Time::HiRes::time;
         $MNOW = Time::HiRes::clock_gettime (&Time::HiRes::CLOCK_MONOTONIC);
      };
      warn "AnyEvent::Impl::Perl using CLOCK_MONOTONIC as timebase.\n" if $AnyEvent::verbose >= 8;
   } else {
      *_update_clock = sub {
         $NOW = $MNOW = Time::HiRes::time;
      };
      warn "AnyEvent::Impl::Perl using default (non-monotonic) clock as timebase.\n" if $AnyEvent::verbose >= 8;
   }
}

_update_clock;

sub now { $NOW }

# fds[0] is for read, fds[1] is for write watchers
# fds[poll]{v} is the bitmask for select
# fds[poll]{w}[fd] contains a list of i/o watchers
# an I/O watcher is a blessed arrayref containing [fh, poll(0/1), callback, queue-index]
# the queue-index is simply the index in the {w} array, which is only used to improve
# benchmark results in the synthetic "many watchers on one fd" benchmark.
my @fds = ({}, {});

my $need_sort = 1e300; # when to re-sort timer list
my @timer; # list of [ abs-timeout, Timer::[callback] ]

# the pure perl mainloop
sub one_event {
   _update_clock;

   # first sort timers if required (slow)
   if ($MNOW >= $need_sort) {
      $need_sort = 1e300;
      @timer = sort { $a->[0] <=> $b->[0] } @timer;
   }

   # handle all pending timers
   if (@timer && $timer[0][0] <= $MNOW) {
      do {
         my $timer = shift @timer;
         $timer->[1][0]() if $timer->[1];
      } while @timer && $timer[0][0] <= $MNOW;

   } else {
      # poll for I/O events, we do not do this when there
      # were any pending timers to ensure that one_event returns
      # quickly when some timers have been handled
      my (@vec, $fds);

      if ($fds = select
            $vec[0] = $fds[0]{v},
            $vec[1] = $fds[1]{v},
            AnyEvent::WIN32 ? $vec[2] = $fds[1]{v} : undef,
            @timer ? $timer[0][0] - $MNOW  + 0.0009 : 3600
      ) {
         _update_clock;

         # buggy microshit windows errornously sets exceptfds instead of writefds
         $vec[1] |= $vec[2] if AnyEvent::WIN32;

         # prefer write watchers, because they usually reduce
         # memory pressure.
         for (1, 0) {
            my $fds = $fds[$_];

            # we parse the bitmask by first expanding it into
            # a string of bits
            for (unpack "b*", $vec[$_]) {
               # and then repeatedly match a regex skipping the 0's
               while (/\G0*1/g) {
                  # and using the resulting string position as fd
                  $_ && $_->[2]()
                     for @{ $fds->{w}[-1 + pos] || [] };
               }
            }
         }
      } elsif (AnyEvent::WIN32 && $! == AnyEvent::Util::WSAEINVAL) {
         # buggy microshit windoze asks us to route around it
         select undef, undef, undef, @timer ? $timer[0][0] - $MNOW  + 0.0009 : 3600;
      }
   }
}

sub io {
   my ($class, %arg) = @_;

   my $self = bless [
      $arg{fh},
      $arg{poll} eq "w",
      $arg{cb},
      # q-idx
   ], AnyEvent::Impl::Perl::Io::;

   my $fds = $fds[$self->[1]];

   # add watcher to fds structure
   my $fd = fileno $self->[0];
   my $q = $fds->{w}[$fd] ||= [];

   (vec $fds->{v}, $fd, 1) = 1;

   $self->[3] = @$q;
   push @$q, $self;
   Scalar::Util::weaken $q->[-1];

   $self
}

sub AnyEvent::Impl::Perl::Io::DESTROY {
   my ($self) = @_;

   my $fds = $fds[$self->[1]];

   # remove watcher from fds structure
   my $fd = fileno $self->[0];

   if (@{ $fds->{w}[$fd] } == 1) {
      delete $fds->{w}[$fd];
      (vec $fds->{v}, $fd, 1) = 0;
   } else {
      my $q = $fds->{w}[$fd];
      my $last = pop @$q;

      if ($last != $self) {
         $q->[$self->[3]] = $last;
         $last->[3] = $self->[3];
      }
   }
}

sub timer {
   my ($class, %arg) = @_;
   
   my $self = bless [$arg{cb}], AnyEvent::Impl::Perl::Timer::;
   my $time = $MNOW + $arg{after};

   push @timer, [$time, $self];
   Scalar::Util::weaken $timer[-1][1];
   $need_sort = $time if $time < $need_sort;

   $self
}

1;

=head1 SEE ALSO

L<AnyEvent>.

=head1 AUTHOR

   Marc Lehmann <schmorp@schmorp.de>
   http://home.schmorp.de/

=cut


