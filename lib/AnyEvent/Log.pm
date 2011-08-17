=head1 NAME

AnyEvent::Log - simple logging "framework"

=head1 SYNOPSIS

   use AnyEvent::Log;

=head1 DESCRIPTION

This module implements a relatively simple "logging framework". It doesn't
attempt to be "the" logging solution or even "a" logging solution for
AnyEvent - AnyEvent simply creates logging messages internally, and this
module more or less exposes the mechanism, with some extra spiff to allow
using it from other modules as well.

Remember that the default verbosity level is C<0>, so nothing
will be logged, ever, unless you set C<$Anyvent::VERBOSE> or
C<PERL_ANYEVENT_VERBOSE> to a higher number.

Possible future extensions are to allow custom log targets (where the
level is an object), log filtering based on package, formatting, aliasing
or package groups.

=head1 LOG FUNCTIONS

These functions allow you to log messages. They always use the caller's
package as a "logging module/source". Also, The main logging function is
easily available as C<AnyEvent::log> or C<AE::log> when the C<AnyEvent>
module is loaded.

=over 4

=cut

package AnyEvent::Log;

use Carp ();
use POSIX ();

use AnyEvent (); BEGIN { AnyEvent::common_sense }
use AnyEvent::Util ();

our ($now_int, $now_str1, $now_str2);

# Format Time, not public - yet?
sub ft($) {
   my $i = int $_[0];
   my $f = sprintf "%06d", 1e6 * ($_[0] - $i);

   ($now_int, $now_str1, $now_str2) = ($i, split /\x01/, POSIX::strftime "%Y-%m-%d %H:%M:%S.\x01 %z", localtime $i)
      if $now_int != $i;

   "$now_str1$f$now_str2"
}

our %CFG; #TODO

=item AnyEvent::Log::log $level, $msg[, @args]

Requests logging of the given C<$msg> with the given log level (1..9).
You can also use the following strings as log level: C<fatal> (1),
C<alert> (2), C<critical> (3), C<error> (4), C<warn> (5), C<note> (6),
C<info> (7), C<debug> (8), C<trace> (9).

For C<fatal> log levels, the program will abort.

If only a C<$msg> is given, it is logged as-is. With extra C<@args>, the
C<$msg> is interpreted as an sprintf format string.

The C<$msg> should not end with C<\n>, but may if that is convenient for
you. Also, multiline messages are handled properly.

Last not least, C<$msg> might be a code reference, in which case it is
supposed to return the message. It will be called only then the message
actually gets logged, which is useful if it is costly to create the
message in the first place.

Whether the given message will be logged depends on the maximum log level
and the caller's package.

Note that you can (and should) call this function as C<AnyEvent::log> or
C<AE::log>, without C<use>-ing this module if possible, as those functions
will laod the logging module on demand only.

Example: log something at error level.

   AE::log error => "something";

Example: use printf-formatting.

   AE::log info => "%5d %-10.10s %s", $index, $category, $msg;

Example: only generate a costly dump when the message is actually being logged.

   AE::log debug => sub { require Data::Dump; Data::Dump::dump \%cache };

=cut

# also allow syslog equivalent names
our %STR2LEVEL = (
   fatal    => 1, emerg    => 1,
   alert    => 2,
   critical => 3, crit     => 3,
   error    => 4, err      => 4,
   warn     => 5, warning  => 5,
   note     => 6, notice   => 6,
   info     => 7,
   debug    => 8,
   trace    => 9,
);

sub now () { time }
AnyEvent::post_detect {
   *now = \&AE::now;
};

our @LEVEL2STR = qw(0 fatal alert crit error warn note info debug trace);

sub _log {
   my ($pkg, $targ, $msg, @args) = @_;

   my $level = ref $targ ? die "Can't use reference as logging level (yet)"
             : $targ > 0 && $targ <= 9 ? $targ+0
             : $STR2LEVEL{$targ} || Carp::croak "$targ: not a valid logging level, caught";

   #TODO: find actual targets, see if we even have to log

   return unless $level <= $AnyEvent::VERBOSE;

   $msg = $msg->() if ref $msg;
   $msg = sprintf $msg, @args if @args;
   $msg =~ s/\n$//;

   # now we have a message, log it

   # TODO: writers/processors/filters/formatters?

   $msg = sprintf "%-5s %s: %s", $LEVEL2STR[$level], $pkg, $msg;
   my $pfx = ft now;

   for (split /\n/, $msg) {
      printf STDERR "$pfx $_\n";
      $pfx = "\t";
   }

   exit 1 if $level <= 1;
}

sub log($$;@) {
   _log +(caller)[0], @_;
}

*AnyEvent::log = *AE::log = \&log;

=item $logger = AnyEvent::Log::logger $level[, \$enabled]

Creates a code reference that, when called, acts as if the
C<AnyEvent::Log::log> function was called at this point with the givne
level. C<$logger> is passed a C<$msg> and optional C<@args>, just as with
the C<AnyEvent::Log::log> function:

   my $debug_log = AnyEvent::Log::logger "debug";

   $debug_log->("debug here");
   $debug_log->("%06d emails processed", 12345);
   $debug_log->(sub { $obj->as_string });

The idea behind this function is to decide whether to log before actually
logging - when the C<logger> function is called once, but the returned
logger callback often, then this can be a tremendous speed win.

Despite this speed advantage, changes in logging configuration will
still be reflected by the logger callback, even if configuration changes
I<after> it was created.

To further speed up logging, you can bind a scalar variable to the logger,
which contains true if the logger should be called or not - if it is
false, calling the logger can be safely skipped. This variable will be
updated as long as C<$logger> is alive.

Full example:

   # near the init section
   use AnyEvent::Log;

   my $debug_log = AnyEvent:Log::logger debug => \my $debug;

   # and later in your program
   $debug_log->("yo, stuff here") if $debug;

   $debug and $debug_log->("123");

Note: currently the enabled var is always true - that will be fixed in a
future version :)

=cut

our %LOGGER;

# re-assess logging status for all loggers
sub _reassess {
   for (@_ ? $LOGGER{$_[0]} : values %LOGGER) {
      my ($pkg, $level, $renabled) = @$_;

      # to detetc whether a message would be logged, we # actually
      # try to log one and die. this isn't # fast, but we can be
      # sure that the logging decision is correct :)

      $$renabled = !eval {
         local $SIG{__DIE__};

         _log $pkg, $level, sub { die };

         1
      };

      $$renabled = 1; # TODO
   }
}

sub logger($;$) {
   my ($level, $renabled) = @_;

   $renabled ||= \my $enabled;
   my $pkg = (caller)[0];

   $$renabled = 1;

   my $logger = [$pkg, $level, $renabled];

   $LOGGER{$logger+0} = $logger;

   _reassess $logger+0;

   my $guard = AnyEvent::Util::guard {
      # "clean up"
      delete $LOGGER{$logger+0};
   };

   sub {
      $guard if 0; # keep guard alive, but don't cause runtime overhead

      _log $pkg, $level, @_
         if $$renabled;
   }
}

#TODO

=back

=head1 CONFIGURATION FUNCTIONALITY

None, yet, except for C<PERL_ANYEVENT_VERBOSE>, described in the L<AnyEvent> manpage.

=over 4

=cut

1;

=back

=head1 AUTHOR

 Marc Lehmann <schmorp@schmorp.de>
 http://home.schmorp.de/

=cut
