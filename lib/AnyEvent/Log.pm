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

our ($now_int, $now_str1, $now_str2);

# Format Time, not public - yet?
sub ft($) {
   my $i = int $_[0];
   my $f = sprintf "%06d", 1e6 * ($_[0] - $i);

   ($now_int, $now_str1, $now_str2) = ($i, split /\x01/, POSIX::strftime "%Y-%m-%d %H:%M:%S.\x01 %z", localtime $i)
      if $now_int != $i;

   "$now_str1$f$now_str2"
}

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

In addition, for possible future expansion, C<$msg> must not start with an
angle bracket (C<< < >>).

Whether the given message will be logged depends on the maximum log level
and the caller's package.

Note that you can (and should) call this function as C<AnyEvent::log> or
C<AE::log>, without C<use>-ing this module if possible, as those functions
will laod the logging module on demand only.

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

our @LEVEL2STR = qw(0 fatal alert crit error warn note info debug trace);

sub log($$;@) {
   my ($targ, $msg, @args) = @_;

   my $level = ref $targ ? die "Can't use reference as logging level (yet)"
             : $targ > 0 && $targ <= 9 ? $targ+0
             : $STR2LEVEL{$targ} || Carp::croak "$targ: not a valid logging level, caught";

   return if $level > $AnyEvent::VERBOSE;

   my $pkg = (caller)[0];

   $msg = sprintf $msg, @args if @args;
   $msg =~ s/\n$//;

   # now we have a message, log it
   #TODO: could do LOTS of stuff here, and should, at least in some later version

   $msg = sprintf "%5s (%s) %s", $LEVEL2STR[$level], $pkg, $msg;
   my $pfx = ft AE::now;

   for (split /\n/, $msg) {
      printf STDERR "$pfx $_\n";
      $pfx = "\t";
   }

   exit 1 if $level <= 1;
}

*AnyEvent::log = *AE::log = \&log;

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
