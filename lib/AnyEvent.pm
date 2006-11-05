=head1 NAME

AnyEvent - provide framework for multiple event loops

Event, Coro, Glib, Tk, Perl - various supported event loops

=head1 SYNOPSIS

   use AnyEvent;

   my $w = AnyEvent->io (fh => $fh, poll => "r|w", cb => sub {
      ...
   });

   my $w = AnyEvent->timer (after => $seconds, cb => sub {
      ...
   });

   my $w = AnyEvent->condvar; # stores wether a condition was flagged
   $w->wait; # enters "main loop" till $condvar gets ->broadcast
   $w->broadcast; # wake up current and all future wait's

=head1 DESCRIPTION

L<AnyEvent> provides an identical interface to multiple event loops. This
allows module authors to utilise an event loop without forcing module
users to use the same event loop (as only a single event loop can coexist
peacefully at any one time).

The interface itself is vaguely similar but not identical to the Event
module.

On the first call of any method, the module tries to detect the currently
loaded event loop by probing wether any of the following modules is
loaded: L<Coro::Event>, L<Event>, L<Glib>, L<Tk>. The first one found is
used. If none is found, the module tries to load these modules in the
order given. The first one that could be successfully loaded will be
used. If still none could be found, AnyEvent will fall back to a pure-perl
event loop, which is also not very efficient.

Because AnyEvent first checks for modules that are already loaded, loading
an Event model explicitly before first using AnyEvent will likely make
that model the default. For example:

   use Tk;
   use AnyEvent;

   # .. AnyEvent will likely default to Tk

The pure-perl implementation of AnyEvent is called
C<AnyEvent::Impl::Perl>. Like other event modules you can load it
explicitly.

=head1 WATCHERS

AnyEvent has the central concept of a I<watcher>, which is an object that
stores relevant data for each kind of event you are waiting for, such as
the callback to call, the filehandle to watch, etc.

These watchers are normal Perl objects with normal Perl lifetime. After
creating a watcher it will immediately "watch" for events and invoke
the callback. To disable the watcher you have to destroy it (e.g. by
setting the variable that stores it to C<undef> or otherwise deleting all
references to it).

All watchers are created by calling a method on the C<AnyEvent> class.

=head2 IO WATCHERS

You can create I/O watcher by calling the C<< AnyEvent->io >> method with
the following mandatory arguments:

C<fh> the Perl I<filehandle> (not filedescriptor) to watch for
events. C<poll> must be a string that is either C<r> or C<w>, that creates
a watcher waiting for "r"eadable or "w"ritable events. C<cb> teh callback
to invoke everytime the filehandle becomes ready.

Only one io watcher per C<fh> and C<poll> combination is allowed (i.e. on
a socket you can have one r + one w, not any more (limitation comes from
Tk - if you are sure you are not using Tk this limitation is gone).

Filehandles will be kept alive, so as long as the watcher exists, the
filehandle exists, too.

Example:

   # wait for readability of STDIN, then read a line and disable the watcher
   my $w; $w = AnyEvent->io (fh => \*STDIN, poll => 'r', cb => sub {
      chomp (my $input = <STDIN>);
      warn "read: $input\n";
      undef $w;
   });

=head2 TIMER WATCHERS

You can create a timer watcher by calling the C<< AnyEvent->timer >>
method with the following mandatory arguments:

C<after> after how many seconds (fractions are supported) should the timer
activate. C<cb> the callback to invoke.

The timer callback will be invoked at most once: if you want a repeating
timer you have to create a new watcher (this is a limitation by both Tk
and Glib).

Example:

   # fire an event after 7.7 seconds
   my $w = AnyEvent->timer (after => 7.7, cb => sub {
      warn "timeout\n";
   });

   # to cancel the timer:
   undef $w

=head2 CONDITION WATCHERS

Condition watchers can be created by calling the C<< AnyEvent->condvar >>
method without any arguments.

A condition watcher watches for a condition - precisely that the C<<
->broadcast >> method has been called.

The watcher has only two methods:

=over 4

=item $cv->wait

Wait (blocking if necessary) until the C<< ->broadcast >> method has been
called on c<$cv>, while servicing other watchers normally.

Not all event models support a blocking wait - some die in that case, so
if you are using this from a module, never require a blocking wait, but
let the caller decide wether the call will block or not (for example,
by coupling condition variables with some kind of request results and
supporting callbacks so the caller knows that getting the result will not
block, while still suppporting blockign waits if the caller so desires).

You can only wait once on a condition - additional calls will return
immediately.

=item $cv->broadcast

Flag the condition as ready - a running C<< ->wait >> and all further
calls to C<wait> will return after this method has been called. If nobody
is waiting the broadcast will be remembered..

Example:

   # wait till the result is ready
   my $result_ready = AnyEvent->condvar;

   # do something such as adding a timer
   # or socket watcher the calls $result_ready->broadcast
   # when the "result" is ready.

   $result_ready->wait;

=back

=head1 GLOBALS

=over 4

=item $AnyEvent::MODEL

Contains C<undef> until the first watcher is being created. Then it
contains the event model that is being used, which is the name of the
Perl class implementing the model. This class is usually one of the
C<AnyEvent::Impl:xxx> modules, but can be any other class in the case
AnyEvent has been extended at runtime (e.g. in I<rxvt-unicode>).

The known classes so far are:

   AnyEvent::Impl::Coro      based on Coro::Event, best choise.
   AnyEvent::Impl::Event     based on Event, also best choice :)
   AnyEvent::Impl::Glib      based on Glib, second-best choice.
   AnyEvent::Impl::Tk        based on Tk, very bad choice.
   AnyEvent::Impl::Perl      pure-perl implementation, inefficient.

=back

=head1 WHAT TO DO IN A MODULE

As a module author, you should "use AnyEvent" and call AnyEvent methods
freely, but you should not load a specific event module or rely on it.

Be careful when you create watchers in the module body - Anyevent will
decide which event module to use as soon as the first method is called, so
by calling AnyEvent in your module body you force the user of your module
to load the event module first.

=head1 WHAT TO DO IN THE MAIN PROGRAM

There will always be a single main program - the only place that should
dictate which event model to use.

If it doesn't care, it can just "use AnyEvent" and use it itself, or not
do anything special and let AnyEvent decide which implementation to chose.

If the main program relies on a specific event model (for example, in Gtk2
programs you have to rely on either Glib or Glib::Event), you should load
it before loading AnyEvent or any module that uses it, generally, as early
as possible. The reason is that modules might create watchers when they
are loaded, and AnyEvent will decide on the event model to use as soon as
it creates watchers, and it might chose the wrong one unless you load the
correct one yourself.

You can chose to use a rather inefficient pure-perl implementation by
loading the C<AnyEvent::Impl::Perl> module, but letting AnyEvent chose is
generally better.

=cut

package AnyEvent;

no warnings;
use strict 'vars';
use Carp;

our $VERSION = '2.0';
our $MODEL;

our $AUTOLOAD;
our @ISA;

our $verbose = $ENV{PERL_ANYEVENT_VERBOSE}*1;

our @REGISTRY;

my @models = (
      [Coro::Event::          => AnyEvent::Impl::Coro::],
      [Event::                => AnyEvent::Impl::Event::],
      [Glib::                 => AnyEvent::Impl::Glib::],
      [Tk::                   => AnyEvent::Impl::Tk::],
      [AnyEvent::Impl::Perl:: => AnyEvent::Impl::Perl::],
);

our %method = map +($_ => 1), qw(io timer condvar broadcast wait DESTROY);

sub AUTOLOAD {
   $AUTOLOAD =~ s/.*://;

   $method{$AUTOLOAD}
      or croak "$AUTOLOAD: not a valid method for AnyEvent objects";

   unless ($MODEL) {
      # check for already loaded models
      for (@REGISTRY, @models) {
         my ($package, $model) = @$_;
         if (${"$package\::VERSION"} > 0) {
            if (eval "require $model") {
               $MODEL = $model;
               warn "AnyEvent: found model '$model', using it.\n" if $verbose > 1;
               last;
            }
         }
      }

      unless ($MODEL) {
         # try to load a model

         for (@REGISTRY, @models) {
            my ($package, $model) = @$_;
            if (eval "require $model") {
               $MODEL = $model;
               warn "AnyEvent: autoprobed and loaded model '$model', using it.\n" if $verbose > 1;
               last;
            }
         }

         $MODEL
           or die "No event module selected for AnyEvent and autodetect failed. Install any one of these modules: Coro, Event, Glib or Tk.";
      }
   }

   @ISA = $MODEL;

   my $class = shift;
   $class->$AUTOLOAD (@_);
}

=head1 SUPPLYING YOUR OWN EVENT MODEL INTERFACE

If you need to support another event library which isn't directly
supported by AnyEvent, you can supply your own interface to it by
pushing, before the first watcher gets created, the package name of
the event module and the package name of the interface to use onto
C<@AnyEvent::REGISTRY>. You can do that before and even without loading
AnyEvent.

Example:

   push @AnyEvent::REGISTRY, [urxvt => urxvt::anyevent::];

This tells AnyEvent to (literally) use the C<urxvt::anyevent::>
package/class when it finds the C<urxvt> package/module is loaded. When
AnyEvent is loaded and asked to find a suitable event model, it will
first check for the presence of urxvt.

The class should prove implementations for all watcher types (see
L<AnyEvent::Impl::Event> (source code), L<AnyEvent::Impl::Glib>
(Source code) and so on for actual examples, use C<perldoc -m
AnyEvent::Impl::Glib> to see the sources).

The above isn't fictitious, the I<rxvt-unicode> (a.k.a. urxvt)
uses the above line as-is. An interface isn't included in AnyEvent
because it doesn't make sense outside the embedded interpreter inside
I<rxvt-unicode>, and it is updated and maintained as part of the
I<rxvt-unicode> distribution.

I<rxvt-unicode> also cheats a bit by not providing blocking access to
condition variables: code blocking while waiting for a condition will
C<die>. This still works with most modules/usages, and blocking calls must
not be in an interactive appliation, so it makes sense.

=head1 ENVIRONMENT VARIABLES

The following environment variables are used by this module:

C<PERL_ANYEVENT_VERBOSE> when set to C<2> or higher, reports which event
model gets used.

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

=head1 REAL-WORLD EXAMPLE

Consider the L<Net::FCP> module. It features (among others) the following
API calls, which are to freenet what HTTP GET requests are to http:

   my $data = $fcp->client_get ($url); # blocks

   my $transaction = $fcp->txn_client_get ($url); # does not block
   $transaction->cb ( sub { ... } ); # set optional result callback
   my $data = $transaction->result; # possibly blocks

The C<client_get> method works like C<LWP::Simple::get>: it requests the
given URL and waits till the data has arrived. It is defined to be:

   sub client_get { $_[0]->txn_client_get ($_[1])->result }

And in fact is automatically generated. This is the blocking API of
L<Net::FCP>, and it works as simple as in any other, similar, module.

More complicated is C<txn_client_get>: It only creates a transaction
(completion, result, ...) object and initiates the transaction.

   my $txn = bless { }, Net::FCP::Txn::;

It also creates a condition variable that is used to signal the completion
of the request:

   $txn->{finished} = AnyAvent->condvar;

It then creates a socket in non-blocking mode.

   socket $txn->{fh}, ...;
   fcntl $txn->{fh}, F_SETFL, O_NONBLOCK;
   connect $txn->{fh}, ...
      and !$!{EWOULDBLOCK}
      and !$!{EINPROGRESS}
      and Carp::croak "unable to connect: $!\n";

Then it creates a write-watcher which gets called whenever an error occurs
or the connection succeeds:

   $txn->{w} = AnyEvent->io (fh => $txn->{fh}, poll => 'w', cb => sub { $txn->fh_ready_w });

And returns this transaction object. The C<fh_ready_w> callback gets
called as soon as the event loop detects that the socket is ready for
writing.

The C<fh_ready_w> method makes the socket blocking again, writes the
request data and replaces the watcher by a read watcher (waiting for reply
data). The actual code is more complicated, but that doesn't matter for
this example:

   fcntl $txn->{fh}, F_SETFL, 0;
   syswrite $txn->{fh}, $txn->{request}
      or die "connection or write error";
   $txn->{w} = AnyEvent->io (fh => $txn->{fh}, poll => 'r', cb => sub { $txn->fh_ready_r });

Again, C<fh_ready_r> waits till all data has arrived, and then stores the
result and signals any possible waiters that the request ahs finished:

   sysread $txn->{fh}, $txn->{buf}, length $txn->{$buf};

   if (end-of-file or data complete) {
     $txn->{result} = $txn->{buf};
     $txn->{finished}->broadcast;
     $txb->{cb}->($txn) of $txn->{cb}; # also call callback
   }

The C<result> method, finally, just waits for the finished signal (if the
request was already finished, it doesn't wait, of course, and returns the
data:

   $txn->{finished}->wait;
   return $txn->{result};

The actual code goes further and collects all errors (C<die>s, exceptions)
that occured during request processing. The C<result> method detects
wether an exception as thrown (it is stored inside the $txn object)
and just throws the exception, which means connection errors and other
problems get reported tot he code that tries to use the result, not in a
random callback.

All of this enables the following usage styles:

1. Blocking:

   my $data = $fcp->client_get ($url);

2. Blocking, but parallelizing:

   my @datas = map $_->result,
                  map $fcp->txn_client_get ($_),
                     @urls;

Both blocking examples work without the module user having to know
anything about events.

3a. Event-based in a main program, using any support Event module:

   use Event;

   $fcp->txn_client_get ($url)->cb (sub {
      my $txn = shift;
      my $data = $txn->result;
      ...
   });

   Event::loop;

3b. The module user could use AnyEvent, too:

   use AnyEvent;

   my $quit = AnyEvent->condvar;

   $fcp->txn_client_get ($url)->cb (sub {
      ...
      $quit->broadcast;
   });

   $quit->wait;

=head1 SEE ALSO

Event modules: L<Coro::Event>, L<Coro>, L<Event>, L<Glib::Event>, L<Glib>.

Implementations: L<AnyEvent::Impl::Coro>, L<AnyEvent::Impl::Event>, L<AnyEvent::Impl::Glib>, L<AnyEvent::Impl::Tk>.

Nontrivial usage example: L<Net::FCP>.

=head1

=cut

1

