=head1 NAME

AnyEvent::Log - simple logging "framework"

=head1 SYNOPSIS

   # simple use
   use AnyEvent;

   AE::log debug => "hit my knee";
   AE::log warn  => "it's a bit too hot";
   AE::log error => "the flag was false!";
   AE::log fatal => "the bit toggled! run!";

   # "complex" use
   use AnyEvent::Log;

   my $tracer = AnyEvent::Log::logger trace => \$my $trace;

   $tracer->("i am here") if $trace;
   $tracer->(sub { "lots of data: " . Dumper $self }) if $trace;

   # configuration

   # set logging for the current package to errors and higher only
   AnyEvent::Log::ctx->level ("error");

   # set logging globally to anything below debug
   $AnyEvent::Log::FILTER->level ("notice");

   # see also EXAMPLES, below

=head1 DESCRIPTION

This module implements a relatively simple "logging framework". It doesn't
attempt to be "the" logging solution or even "a" logging solution for
AnyEvent - AnyEvent simply creates logging messages internally, and this
module more or less exposes the mechanism, with some extra spiff to allow
using it from other modules as well.

Remember that the default verbosity level is C<0> (C<off>), so nothing
will be logged, unless you set C<PERL_ANYEVENT_VERBOSE> to a higher number
before starting your program, or change the logging level at runtime with
something like:

   use AnyEvent::Log;
   AnyEvent::Log::FILTER->level ("info");

The design goal behind this module was to keep it simple (and small),
but make it powerful enough to be potentially useful for any module, and
extensive enough for the most common tasks, such as logging to multiple
targets, or being able to log into a database.

The amount of documentation might indicate otherwise, but the module is
still just below 300 lines of code.

=head1 LOGGING LEVELS

Logging levels in this module range from C<1> (highest priority) to C<9>
(lowest priority). Note that the lowest numerical value is the highest
priority, so when this document says "higher priority" it means "lower
numerical value".

Instead of specifying levels by name you can also specify them by aliases:

   LVL NAME      SYSLOG   PERL  NOTE
   1   fatal     emerg    exit  aborts program!
   2   alert
   3   critical  crit     
   4   error     err      die
   5   warn      warning  
   6   note      notice   
   7   info
   8   debug
   9   trace

As you can see, some logging levels have multiple aliases - the first one
is the "official" name, the second one the "syslog" name (if it differs)
and the third one the "perl" name, suggesting that you log C<die> messages
at C<error> priority.

You can normally only log a single message at highest priority level
(C<1>, C<fatal>), because logging a fatal message will also quit the
program - so use it sparingly :)

Some methods also offer some extra levels, such as C<0>, C<off>, C<none>
or C<all> - these are only valid in the methods they are documented for.

=head1 LOGGING FUNCTIONS

These functions allow you to log messages. They always use the caller's
package as a "logging context". Also, the main logging function C<log> is
callable as C<AnyEvent::log> or C<AE::log> when the C<AnyEvent> module is
loaded.

=over 4

=cut

package AnyEvent::Log;

use Carp ();
use POSIX ();

use AnyEvent (); BEGIN { AnyEvent::common_sense }
use AnyEvent::Util ();

our $VERSION = $AnyEvent::VERSION;

our ($COLLECT, $FILTER, $LOG);

our ($now_int, $now_str1, $now_str2);

# Format Time, not public - yet?
sub ft($) {
   my $i = int $_[0];
   my $f = sprintf "%06d", 1e6 * ($_[0] - $i);

   ($now_int, $now_str1, $now_str2) = ($i, split /\x01/, POSIX::strftime "%Y-%m-%d %H:%M:%S.\x01 %z", localtime $i)
      if $now_int != $i;

   "$now_str1$f$now_str2"
}

our %CTX; # all package contexts

# creates a default package context object for the given package
sub _pkg_ctx($) {
   my $ctx = bless [$_[0], (1 << 10) - 1 - 1, {}], "AnyEvent::Log::Ctx";

   # link "parent" package
   my $parent = $_[0] =~ /^(.+)::/
      ? $CTX{$1} ||= &_pkg_ctx ("$1")
      : $COLLECT;

   $ctx->[2]{$parent+0} = $parent;

   $ctx
}

=item AnyEvent::Log::log $level, $msg[, @args]

Requests logging of the given C<$msg> with the given log level.

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
C<AE::log>, without C<use>-ing this module if possible (i.e. you don't
need any additional functionality), as those functions will load the
logging module on demand only. They are also much shorter to write.

Also, if you optionally generate a lot of debug messages (such as when
tracing some code), you should look into using a logger callback and a
boolean enabler (see C<logger>, below).

Example: log something at error level.

   AE::log error => "something";

Example: use printf-formatting.

   AE::log info => "%5d %-10.10s %s", $index, $category, $msg;

Example: only generate a costly dump when the message is actually being logged.

   AE::log debug => sub { require Data::Dump; Data::Dump::dump \%cache };

=cut

# also allow syslog equivalent names
our %STR2LEVEL = (
   fatal    => 1, emerg    => 1, exit => 1,
   alert    => 2,
   critical => 3, crit     => 3,
   error    => 4, err      => 4, die  => 4,
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

# time, ctx, level, msg
sub _format($$$$) {
   my $ts = ft $_[0];
   my $ct = " ";

   my @res;

   for (split /\n/, sprintf "%-5s %s: %s", $LEVEL2STR[$_[2]], $_[1][0], $_[3]) {
      push @res, "$ts$ct$_\n";
      $ct = " + ";
   }

   join "", @res
}

sub _log {
   my ($ctx, $level, $format, @args) = @_;

   $level = $level > 0 && $level <= 9
            ? $level+0
            : $STR2LEVEL{$level} || Carp::croak "$level: not a valid logging level, caught";

   my $mask = 1 << $level;

   my (%seen, @ctx, $now, $fmt);

   do
      {
         # skip if masked
         if ($ctx->[1] & $mask && !$seen{$ctx+0}++) {
            if ($ctx->[3]) {
               # logging target found

               # now get raw message, unless we have it already
               unless ($now) {
                  $format = $format->() if ref $format;
                  $format = sprintf $format, @args if @args;
                  $format =~ s/\n$//;
                  $now = AE::now;
               };

               # format msg
               my $str = $ctx->[4]
                  ? $ctx->[4]($now, $_[0], $level, $format)
                  : ($fmt ||= _format $now, $_[0], $level, $format);

               $ctx->[3]($str, $_[0], $level)
                  or push @ctx, values %{ $ctx->[2] }; # not consumed - propagate
            } else {
               push @ctx, values %{ $ctx->[2] }; # not masked - propagate
            }
         }
      }
   while $ctx = pop @ctx;

   exit 1 if $level <= 1;
}

sub log($$;@) {
   _log
      $CTX{ (caller)[0] } ||= _pkg_ctx +(caller)[0],
      @_;
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

=cut

our %LOGGER;

# re-assess logging status for all loggers
sub _reassess {
   local $SIG{__DIE__};
   my $die = sub { die };

   for (@_ ? $LOGGER{$_[0]} : values %LOGGER) {
      my ($ctx, $level, $renabled) = @$_;

      # to detect whether a message would be logged, we actually
      # try to log one and die. this isn't fast, but we can be
      # sure that the logging decision is correct :)

      $$renabled = !eval {
         _log $ctx, $level, $die;

         1
      };
   }
}

sub _logger {
   my ($ctx, $level, $renabled) = @_;

   $$renabled = 1;

   my $logger = [$ctx, $level, $renabled];

   $LOGGER{$logger+0} = $logger;

   _reassess $logger+0;

   my $guard = AnyEvent::Util::guard {
      # "clean up"
      delete $LOGGER{$logger+0};
   };

   sub {
      $guard if 0; # keep guard alive, but don't cause runtime overhead

      _log $ctx, $level, @_
         if $$renabled;
   }
}

sub logger($;$) {
   _logger
      $CTX{ (caller)[0] } ||= _pkg_ctx +(caller)[0],
      @_
}

=back

=head1 LOGGING CONTEXTS

This module associates every log message with a so-called I<logging
context>, based on the package of the caller. Every perl package has its
own logging context.

A logging context has three major responsibilities: filtering, logging and
propagating the message.

For the first purpose, filtering, each context has a set of logging
levels, called the log level mask. Messages not in the set will be ignored
by this context (masked).

For logging, the context stores a formatting callback (which takes the
timestamp, context, level and string message and formats it in the way
it should be logged) and a logging callback (which is responsible for
actually logging the formatted message and telling C<AnyEvent::Log>
whether it has consumed the message, or whether it should be propagated).

For propagation, a context can have any number of attached I<slave
contexts>. Any message that is neither masked by the logging mask nor
masked by the logging callback returning true will be passed to all slave
contexts.

Each call to a logging function will log the message at most once per
context, so it does not matter (much) if there are cycles or if the
message can arrive at the same context via multiple paths.

=head2 DEFAULTS

By default, all logging contexts have an full set of log levels ("all"), a
disabled logging callback and the default formatting callback.

Package contexts have the package name as logging title by default.

They have exactly one slave - the context of the "parent" package. The
parent package is simply defined to be the package name without the last
component, i.e. C<AnyEvent::Debug::Wrapped> becomes C<AnyEvent::Debug>,
and C<AnyEvent> becomes ... C<$AnyEvent::Log::COLLECT> which is the
exception of the rule - just like the "parent" of any single-component
package name in Perl is C<main>, the default slave of any top-level
package context is C<$AnyEvent::Log::COLLECT>.

Since perl packages form only an approximate hierarchy, this slave
context can of course be removed.

All other (anonymous) contexts have no slaves and an empty title by
default.

When the module is loaded it creates the C<$AnyEvent::Log::LOG> logging
context that simply logs everything via C<warn>, without propagating
anything anywhere by default.  The purpose of this context is to provide
a convenient place to override the global logging target or to attach
additional log targets. It's not meant for filtering.

It then creates the C<$AnyEvent::Log::FILTER> context whose
purpose is to suppress all messages with priority higher
than C<$ENV{PERL_ANYEVENT_VERBOSE}>. It then attached the
C<$AnyEvent::Log::LOG> context to it. The purpose of the filter context
is to simply provide filtering according to some global log level.

Finally it creates the top-level package context C<$AnyEvent::Log::COLLECT>
and attaches the C<$AnyEvent::Log::FILTER> context to it, but otherwise
leaves it at default config. Its purpose is simply to collect all log
messages system-wide.

The hierarchy is then:

   any package, eventually -> $COLLECT -> $FILTER -> $LOG

The effect of all this is that log messages, by default, wander up to the
C<$AnyEvent::Log::COLLECT> context where all messages normally end up,
from there to C<$AnyEvent::Log::FILTER> where log messages with lower
priority then C<$ENV{PERL_ANYEVENT_VERBOSE}> will be filtered out and then
to the C<$AnyEvent::Log::LOG> context to be passed to C<warn>.

This makes it easy to set a global logging level (by modifying $FILTER),
but still allow other contexts to send, for example, their debug and trace
messages to the $LOG target despite the global logging level, or to attach
additional log targets that log messages, regardless of the global logging
level.

It also makes it easy to modify the default warn-logger ($LOG) to
something that logs to a file, or to attach additional logging targets
(such as loggign to a file) by attaching it to $FILTER.

=head2 CREATING/FINDING/DESTROYING CONTEXTS

=over 4

=item $ctx = AnyEvent::Log::ctx [$pkg]

This function creates or returns a logging context (which is an object).

If a package name is given, then the context for that packlage is
returned. If it is called without any arguments, then the context for the
callers package is returned (i.e. the same context as a C<AE::log> call
would use).

If C<undef> is given, then it creates a new anonymous context that is not
tied to any package and is destroyed when no longer referenced.

=cut

sub ctx(;$) {
   my $pkg = @_ ? shift : (caller)[0];

   ref $pkg
      ? $pkg
      : defined $pkg
         ? $CTX{$pkg} ||= AnyEvent::Log::_pkg_ctx $pkg
         : bless [undef, (1 << 10) - 1 - 1], "AnyEvent::Log::Ctx"
}

=item AnyEvent::Log::reset

Resets all package contexts and recreates the default hierarchy if
necessary, i.e. resets the logging subsystem to defaults, as much as
possible. This process keeps references to contexts held by other parts of
the program intact.

This can be used to implement config-file (re-)loading: before loading a
configuration, reset all contexts.

=cut

sub reset {
   # hard to kill complex data structures
   # we "recreate" all package loggers and reset the hierarchy
   while (my ($k, $v) = each %CTX) {
      @$v = ($k, (1 << 10) - 1 - 1, { });

      $v->attach ($k =~ /^(.+)::/ ? $CTX{$1} : $AnyEvent::Log::COLLECT);
   }

   @$_ = ($_->[0], (1 << 10) - 1 - 1)
      for $LOG, $FILTER, $COLLECT;

   $LOG->slaves;
   $LOG->title ('$AnyEvent::Log::LOG');
   $LOG->log_cb (sub {
      warn shift;
      0
   });

   $FILTER->slaves ($LOG);
   $FILTER->title ('$AnyEvent::Log::FILTER');
   $FILTER->level ($AnyEvent::VERBOSE);

   $COLLECT->slaves ($FILTER);
   $COLLECT->title ('$AnyEvent::Log::COLLECT');

   _reassess;
}

# create the default logger contexts
$LOG     = ctx undef;
$FILTER  = ctx undef;
$COLLECT = ctx undef;

AnyEvent::Log::reset;

# hello, CPAN, please catch me
package AnyEvent::Log::LOG;
package AE::Log::LOG;
package AnyEvent::Log::FILTER;
package AE::Log::FILTER;
package AnyEvent::Log::COLLECT;
package AE::Log::COLLECT;

package AnyEvent::Log::Ctx;

#       0       1         2        3        4
# [$title, $level, %$slaves, &$logcb, &$fmtcb]

=item $ctx = new AnyEvent::Log::Ctx methodname => param...

This is a convenience constructor that makes it simpler to construct
anonymous logging contexts.

Each key-value pair results in an invocation of the method of the same
name as the key with the value as parameter, unless the value is an
arrayref, in which case it calls the method with the contents of the
array. The methods are called in the same order as specified.

Example: create a new logging context and set both the default logging
level, some slave contexts and a logging callback.

   $ctx = new AnyEvent::Log::Ctx
      title   => "dubious messages",
      level   => "error",
      log_cb  => sub { print STDOUT shift; 0 },
      slaves  => [$ctx1, $ctx, $ctx2],
   ;

=back

=cut

sub new {
   my $class = shift;

   my $ctx = AnyEvent::Log::ctx undef;

   while (@_) {
      my ($k, $v) = splice @_, 0, 2;
      $ctx->$k (ref $v eq "ARRAY" ? @$v : $v);
   }

   bless $ctx, $class # do we really support subclassing, hmm?
}


=head2 CONFIGURING A LOG CONTEXT

The following methods can be used to configure the logging context.

=over 4

=item $ctx->title ([$new_title])

Returns the title of the logging context - this is the package name, for
package contexts, and a user defined string for all others.

If C<$new_title> is given, then it replaces the package name or title.

=cut

sub title {
   $_[0][0] = $_[1] if @_ > 1;
   $_[0][0]
}

=back

=head3 LOGGING LEVELS

The following methods deal with the logging level set associated with the
log context.

The most common method to use is probably C<< $ctx->level ($level) >>,
which configures the specified and any higher priority levels.

All functions which accept a list of levels also accept the special string
C<all> which expands to all logging levels.

=over 4

=item $ctx->levels ($level[, $level...)

Enables logging for the given levels and disables it for all others.

=item $ctx->level ($level)

Enables logging for the given level and all lower level (higher priority)
ones. In addition to normal logging levels, specifying a level of C<0> or
C<off> disables all logging for this level.

Example: log warnings, errors and higher priority messages.

   $ctx->level ("warn");
   $ctx->level (5); # same thing, just numeric

=item $ctx->enable ($level[, $level...])

Enables logging for the given levels, leaving all others unchanged.

=item $ctx->disable ($level[, $level...])

Disables logging for the given levels, leaving all others unchanged.

=cut

sub _lvl_lst {
   map {
      $_ > 0 && $_ <= 9 ? $_+0
      : $_ eq "all"     ? (1 .. 9)
      : $STR2LEVEL{$_} || Carp::croak "$_: not a valid logging level, caught"
   } @_
}

our $NOP_CB = sub { 0 };

sub levels {
   my $ctx = shift;
   $ctx->[1] = 0;
   $ctx->[1] |= 1 << $_
      for &_lvl_lst;
   AnyEvent::Log::_reassess;
}

sub level {
   my $ctx = shift;
   my $lvl = $_[0] =~ /^(?:0|off|none)$/ ? 0 : (_lvl_lst $_[0])[-1];

   $ctx->[1] =  ((1 << $lvl) - 1) << 1;
   AnyEvent::Log::_reassess;
}

sub enable {
   my $ctx = shift;
   $ctx->[1] |= 1 << $_
      for &_lvl_lst;
   AnyEvent::Log::_reassess;
}

sub disable {
   my $ctx = shift;
   $ctx->[1] &= ~(1 << $_)
      for &_lvl_lst;
   AnyEvent::Log::_reassess;
}

=back

=head3 SLAVE CONTEXTS

The following methods attach and detach another logging context to a
logging context.

Log messages are propagated to all slave contexts, unless the logging
callback consumes the message.

=over 4

=item $ctx->attach ($ctx2[, $ctx3...])

Attaches the given contexts as slaves to this context. It is not an error
to add a context twice (the second add will be ignored).

A context can be specified either as package name or as a context object.

=item $ctx->detach ($ctx2[, $ctx3...])

Removes the given slaves from this context - it's not an error to attempt
to remove a context that hasn't been added.

A context can be specified either as package name or as a context object.

=item $ctx->slaves ($ctx2[, $ctx3...])

Replaces all slaves attached to this context by the ones given.

=cut

sub attach {
   my $ctx = shift;

   $ctx->[2]{$_+0} = $_
      for map { AnyEvent::Log::ctx $_ } @_;
}

sub detach {
   my $ctx = shift;

   delete $ctx->[2]{$_+0}
      for map { AnyEvent::Log::ctx $_ } @_;
}

sub slaves {
   undef $_[0][2];
   &attach;
}

=back

=head3 LOG TARGETS

The following methods configure how the logging context actually does
the logging (which consists of formatting the message and printing it or
whatever it wants to do with it).

=over 4

=item $ctx->log_cb ($cb->($str, $orig_ctx, $level))

Replaces the logging callback on the context (C<undef> disables the
logging callback).

The logging callback is responsible for handling formatted log messages
(see C<fmt_cb> below) - normally simple text strings that end with a
newline (and are possibly multiline themselves). In addition to the
message, which is often the only argument you need to look at, it is
passed the numeric log level and originating context.

It also has to return true iff it has consumed the log message, and false
if it hasn't. Consuming a message means that it will not be sent to any
slave context. When in doubt, return C<0> from your logging callback.

Example: a very simple logging callback, simply dump the message to STDOUT
and do not consume it.

   $ctx->log_cb (sub { print STDERR shift; 0 });

You can filter messages by having a log callback that simply returns C<1>
and does not do anything with the message, but this counts as "message
being logged" and might not be very efficient.

Example: propagate all messages except for log levels "debug" and
"trace". The messages will still be generated, though, which can slow down
your program.

   $ctx->levels ("debug", "trace");
   $ctx->log_cb (sub { 1 }); # do not log, but eat debug and trace messages

=item $ctx->log_to_file ($path)

Sets the C<log_cb> to log to a file (by appending), unbuffered.

=item $ctx->log_to_path ($path)

Same as C<< ->log_to_file >>, but opens the file for each message. This
is much slower, but allows you to change/move/rename/delete the file at
basically any time.

=item $ctx->log_to_syslog ([$log_flags])

Logs all messages via L<Sys::Syslog>, mapping C<trace> to C<debug> and all
the others in the obvious way. If specified, then the C<$log_flags> are
simply or'ed onto the priority argument and can contain any C<LOG_xxx>
flags valid for Sys::Syslog::syslog, except for the priority levels.

Note that the default logging format includes a verbose timestamp, which
is not so suited for syslog, so a simpler C<fmt_cb> might be useful:

   $ctx->log_to_syslog;
   $ctx->fmt_cb (sub { "($_[1][0]) $_[3]" });

=item $ctx->fmt_cb ($fmt_cb->($timestamp, $orig_ctx, $level, $message))

Replaces the formatting callback on the context (C<undef> restores the
default formatter).

The callback is passed the (possibly fractional) timestamp, the original
logging context, the (numeric) logging level and the raw message string
and needs to return a formatted log message. In most cases this will be a
string, but it could just as well be an array reference that just stores
the values.

If, for some reaosn, you want to use C<caller> to find out more baout the
logger then you should walk up the call stack until you are no longer
inside the C<AnyEvent::Log> package.

Example: format just the raw message, with numeric log level in angle
brackets.

   $ctx->fmt_cb (sub {
      my ($time, $ctx, $lvl, $msg) = @_;

      "<$lvl>$msg\n"
   });

Example: return an array reference with just the log values, and use
C<PApp::SQL::sql_exec> to store the emssage in a database.

   $ctx->fmt_cb (sub { \@_ });
   $ctx->log_cb (sub {
      my ($msg) = @_;

      sql_exec "insert into log (when, subsys, prio, msg) values (?, ?, ?, ?)",
               $msg->[0] + 0,
               "$msg->[1]",
               $msg->[2] + 0,
               "$msg->[3]";

      0
   });

=cut

sub log_cb {
   my ($ctx, $cb) = @_;

   $ctx->[3] = $cb;
}

sub fmt_cb {
   my ($ctx, $cb) = @_;

   $ctx->[4] = $cb;
}

sub log_to_file {
   my ($ctx, $path) = @_;

   open my $fh, ">>", $path
      or die "$path: $!";

   $ctx->log_cb (sub {
      syswrite $fh, shift;
      0
   });
}

sub log_to_file {
   my ($ctx, $path) = @_;

   $ctx->log_cb (sub {
      open my $fh, ">>", $path
         or die "$path: $!";

      syswrite $fh, shift;
      0
   });
}

sub log_to_syslog {
   my ($ctx, $flags) = @_;

   require Sys::Syslog;

   $ctx->log_cb (sub {
      my $lvl = $_[2] < 9 ? $_[2] : 8;

      Sys::Syslog::syslog ($flags | ($lvl - 1), $_)
         for split /\n/, shift;

      0
   });
}

=back

=head3 MESSAGE LOGGING

These methods allow you to log messages directly to a context, without
going via your package context.

=over 4

=item $ctx->log ($level, $msg[, @params])

Same as C<AnyEvent::Log::log>, but uses the given context as log context.

=item $logger = $ctx->logger ($level[, \$enabled])

Same as C<AnyEvent::Log::logger>, but uses the given context as log
context.

=cut

*log    = \&AnyEvent::Log::_log;
*logger = \&AnyEvent::Log::_logger;

1;

=back

=head1 EXAMPLES

This section shows some common configurations.

=over 4

=item Setting the global logging level.

Either put PERL_ANYEVENT_VERBOSE=<number> into your environment before
running your program, or modify the log level of the root context:

   PERL_ANYEVENT_VERBOSE=5 ./myprog

   $AnyEvent::Log::FILTER->level ("warn");

=item Append all messages to a file instead of sending them to STDERR.

This is affected by the global logging level.

   $AnyEvent::Log::LOG->log_to_file ($path); (sub {

=item Write all messages with priority C<error> and higher to a file.

This writes them only when the global logging level allows it, because
it is attached to the default context which is invoked I<after> global
filtering.

   $AnyEvent::Log::FILTER->attach 
      new AnyEvent::Log::Ctx log_to_file => $path);

This writes them regardless of the global logging level, because it is
attached to the toplevel context, which receives all messages I<before>
the global filtering.

   $AnyEvent::Log::COLLECT->attach (
      new AnyEvent::Log::Ctx log_to_file => $path);

In both cases, messages are still written to STDERR.

=item Write trace messages (only) from L<AnyEvent::Debug> to the default logging target(s).

Attach the C<$AnyEvent::Log::LOG> context to the C<AnyEvent::Debug>
context - this simply circumvents the global filtering for trace messages.

   my $debug = AnyEvent::Debug->AnyEvent::Log::ctx;
   $debug->attach ($AnyEvent::Log::LOG);

This of course works for any package, not just L<AnyEvent::Debug>, but
assumes the log level for AnyEvent::Debug hasn't been changed from the
default.

=back

=head1 AUTHOR

 Marc Lehmann <schmorp@schmorp.de>
 http://home.schmorp.de/

=cut
