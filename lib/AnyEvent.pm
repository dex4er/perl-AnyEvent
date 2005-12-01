=head1 NAME

AnyEvent - provide framework for multiple event loops

Event, Coro, Glib, Tk - various supported event loops

=head1 SYNOPSIS

use AnyEvent;

   my $w = AnyEvent->timer (fh => ..., poll => "[rw]+", cb => sub {
      my ($poll_got) = @_;
      ...
   });
   my $w = AnyEvent->io (after => $seconds, cb => sub {
      ...
   });

   # watchers get canceled whenever $w is destroyed
   # only one watcher per $fh and $poll type is allowed
   # (i.e. on a socket you cna have one r + one w or one rw
   # watcher, not any more.
   # timers can only be used once

   my $w = AnyEvent->condvar; # kind of main loop replacement
   # can only be used once
   $w->wait; # enters main loop till $condvar gets ->send
   $w->broadcast; # wake up waiting and future wait's

=head1 DESCRIPTION

L<AnyEvent> provides an identical interface to multiple event loops. This
allows module authors to utilizy an event loop without forcing module
users to use the same event loop (as only a single event loop can coexist
peacefully at any one time).

The interface itself is vaguely similar but not identical to the Event
module.

On the first call of any method, the module tries to detect the currently
loaded event loop by probing wether any of the following modules is
loaded: L<Coro::Event>, L<Event>, L<Glib>, L<Tk>. The first one found is
used. If none is found, the module tries to load these modules in the
order given. The first one that could be successfully loaded will be
used. If still none could be found, it will issue an error.

=over 4

=cut

package AnyEvent;

no warnings;
use strict 'vars';
use Carp;

our $VERSION = 0.2;
our $MODEL;

our $AUTOLOAD;
our @ISA;

my @models = (
      [Coro  => Coro::Event::],
      [Event => Event::],
      [Glib  => Glib::],
      [Tk    => Tk::],
);

our %method = map +($_ => 1), qw(io timer condvar broadcast wait cancel DESTROY);

sub AUTOLOAD {
   $AUTOLOAD =~ s/.*://;

   $method{$AUTOLOAD}
      or croak "$AUTOLOAD: not a valid method for AnyEvent objects";

   unless ($MODEL) {
      # check for already loaded models
      for (@models) {
         my ($model, $package) = @$_;
         if (scalar keys %{ *{"$package\::"} }) {
            eval "require AnyEvent::Impl::$model";
            last if $MODEL;
         }
      }

      unless ($MODEL) {
         # try to load a model

         for (@models) {
            my ($model, $package) = @$_;
            eval "require AnyEvent::Impl::$model";
            last if $MODEL;
         }

         $MODEL
           or die "No event module selected for AnyEvent and autodetect failed. Install any one of these modules: Coro, Event, Glib or Tk.";
      }
   }

   @ISA = $MODEL;

   my $class = shift;
   $class->$AUTOLOAD (@_);
}

=back

=head1 EXAMPLE

The following program uses an io watcher to read data from stdin, a timer
to display a message once per second, and a condvar to exit the program
when the user enters quit:

   use AnyEvent;

   my $cv = AnyEvent->condvar;

   my $io_watcher = AnyEvent->io (fh => \*STDIN, poll => 'r', cb => sub {
      warn "io event <$_[0]>\n";   # will always output <r>
      chomp (my $input = <STDIN>); # read a line
      warn "read: $input\n";       # output what has been read
      $cv->broadcast if $input =~ /^q/i; # quit program if /^q/i
   });

   my $time_watcher; # can only be used once

   sub new_timer {
      $timer = AnyEvent->timer (after => 1, cb => sub {
         warn "timeout\n"; # print 'timeout' about every second
         &new_timer; # and restart the time
      });
   }

   new_timer; # create first timer

   $cv->wait; # wait until user enters /^q/i

=head1 SEE ALSO

L<Coro::Event>, L<Coro>, L<Event>, L<Glib::Event>, L<Glib>,
L<AnyEvent::Impl::Coro>,
L<AnyEvent::Impl::Event>,
L<AnyEvent::Impl::Glib>,
L<AnyEvent::Impl::Tk>.

=head1

=cut

1

