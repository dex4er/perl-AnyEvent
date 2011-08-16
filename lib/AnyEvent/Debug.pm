=head1 NAME

AnyEvent::Debug - debugging utilities for AnyEvent

=head1 SYNOPSIS

   use AnyEvent::Debug;

   # create an interactive shell into the program
   my $shell = AnyEvent::Debug::shell "unix/", "/home/schmorp/myshell";
   # then on the shell: "socat readline /home/schmorp/myshell"

=head1 DESCRIPTION

This module provides functionality hopefully useful for debugging.

At the moment, "only" an interactive shell is implemented. This shell
allows you to interactively "telnet into" your program and execute Perl
code, e.g. to look at global variables.

=head1 FUNCTIONS

=over 4

=cut

package AnyEvent::Debug;

use Carp ();
use Errno ();

use AnyEvent (); BEGIN { AnyEvent::common_sense }
use AnyEvent::Util ();
use AnyEvent::Socket ();
use AnyEvent::Log ();

=item $shell = AnyEvent;::Debug::shell $host, $service

This function binds on the given host and service port and returns a
shell object, which determines the lifetime of the shell. Any number
of conenctions are accepted on the port, and they will give you a very
primitive shell that simply executes every line you enter.

All commands will be executed "blockingly" with the socket C<select>ed for
output. For a less "blocking" interface see L<Coro::Debug>.

The commands will be executed in the C<AnyEvent::Debug::shell> package,
which currently has "help", "wl" and "wlv" commands, and can be freely
modified by all shells. Code is evaluated under C<use strict 'subs'>.

Consider the beneficial aspects of using more global (our) variables than
local ones (my) in package scope: Earlier all my modules tended to hide
internal variables inside C<my> variables, so users couldn't accidentally
access them. Having interactive access to your programs changed that:
having internal variables still in the global scope means you can debug
them easier.

As no authentication is done, in most cases it is best not to use a TCP
port, but a unix domain socket, whcih can be put wherever you can access
it, but not others:

   our $SHELL = AnyEvent::Debug::shell "unix/", "/home/schmorp/shell";

Then you can use a tool to connect to the shell, such as the ever
versatile C<socat>, which in addition can give you readline support:

   socat readline /home/schmorp/shell
   # or:
   cd /home/schmorp; socat readline unix:shell

Socat can even give you a persistent history:

   socat readline,history=.anyevent-history unix:shell

Binding on C<127.0.0.1> (or C<::1>) might be a less secure but sitll not
totally insecure (on single-user machines) alternative to let you use
other tools, such as telnet:

   our $SHELL = AnyEvent::Debug::shell "127.1", "1357";

And then:

   telnet localhost 1357

=cut

sub shell($$) {
   AnyEvent::Socket::tcp_server $_[0], $_[1], sub {
      my ($fh, $host, $port) = @_;

      syswrite $fh, "Welcome, $host:$port, use 'help' for more info!\015\012> ";
      my $rbuf;
      my $rw; $rw = AE::io $fh, 0, sub {
         my $len = sysread $fh, $rbuf, 1024, length $rbuf;

         if (defined $len ? $len == 0 : $! != Errno::EAGAIN) {
            undef $rw;
         } else {
            while ($rbuf =~ s/^(.*)\015?\012//) {
               my $line = $1;

               AnyEvent::Util::fh_nonblocking $fh, 0;

               if ($line =~ /^\s*exit\b/) {
                  syswrite $fh, "sorry, no... if you want to execute exit, try CORE::exit.\015\012";
               } else {
                  package AnyEvent::Debug::shell;

                  no strict 'vars';
                  my $old_stdout = select $fh;
                  local $| = 1;

                  my @res = eval $line;

                  select $old_stdout;
                  syswrite $fh, "$@" if $@;
                  syswrite $fh, "\015\012";

                  if (@res > 1) {
                     syswrite $fh, "$_: $res[$_]\015\012" for 0 .. $#res;
                  } elsif (@res == 1) {
                     syswrite $fh, "$res[0]\015\012";
                  }
               }

               syswrite $fh, "> ";
               AnyEvent::Util::fh_nonblocking $fh, 1;
            }
         }
      };
   }
}

{
   package AnyEvent::Debug::shell;

   sub help() {
      <<EOF
help         this command
wr [level]   sets wrap level to level (or toggles if missing)
v [level]    sets verbosity (or toggles if missing)
wl 'regex'   print wrapped watchers matching the regex (or all if missing)
w id,...     prints the watcher with the given ids in more detail
EOF
   }

   sub wl(;$) {
      my $re = @_ ? qr<$_[0]>i : qr<.>;

      my %res;

      while (my ($k, $v) = each %AnyEvent::Debug::Wrapped) {
         my $s = "$v";
         $res{$s} = $k . (exists $v->{error} ? "*" : " ")
            if $s =~ $re;
      }

      join "", map "$res{$_} $_\n", sort keys %res
   }

   sub w(@) {
      my $res;

      for my $id (@_) {
         if (my $w = $AnyEvent::Debug::Wrapped{$id}) {
            $res .= "$id $w\n" . $w->verbose;
         } else {
            $res .= "$id: no such wrapped watcher.\n";
         }
      }

      $res
   }

   sub wr {
      AnyEvent::Debug::wrap (@_);

      "wrap level now $AnyEvent::Debug::WRAP_LEVEL"
   }

   sub v {
      $AnyEvent::VERBOSE = @_ ? shift : $AnyEvent::VERBOSE ? 0 : 9;

      "verbosity level now $AnyEvent::VEBROSE"
   }
}

=item AnyEvent::Debug::wrap [$level]

Sets the instrumenting/wrapping level of all watchers that are being
created after this call. If no C<$level> has been specified, then it
toggles between C<0> and C<1>.

The default wrap level is C<0>, or whatever
C<$ENV{PERL_ANYEVENT_DEBUG_WRAP}> specifies.

A level of C<0> disables wrapping, i.e. AnyEvent works normally, and in
its most efficient mode.

A level of C<1> enables wrapping, which replaces all watchers by
AnyEvent::Debug::Wrapped objects, stores the location where a watcher was
created and wraps the callback so invocations of it can be traced.

A level of C<2> does everything that level C<1> does, but also stores a
full backtrace of the location the watcher was created.

Every wrapped watcher will be linked into C<%AnyEvent::Debug::Wrapped>,
with its address as key. The C<wl> command in the debug shell cna be used
to list watchers.

Instrumenting can increase the size of each watcher multiple times, and,
especially when backtraces are involved, also slows down watcher creation
a lot.

Also, enabling and disabling instrumentation will not recover the full
performance that you had before wrapping (the AE::xxx functions will stay
slower, for example).

If you are developing your program, also consider using AnyEvent::Strict
to check for common mistakes.

=cut

our $WRAP_LEVEL;
our $TRACE_LEVEL;
our $TRACE_CUR;
our $POST_DETECT;

sub wrap(;$) {
   my $PREV_LEVEL = $WRAP_LEVEL;
   $WRAP_LEVEL = @_ ? 0+shift : $WRAP_LEVEL ? 0 : 1;

   if ($AnyEvent::MODEL) {
      if ($WRAP_LEVEL && !$PREV_LEVEL) {
         AnyEvent::_isa_hook 0 => "AnyEvent::Debug::Wrap", 1;
         AnyEvent::Debug::Wrap::_reset ();
      } elsif (!$WRAP_LEVEL && $PREV_LEVEL) {
         AnyEvent::_isa_hook 0 => undef;
      }
   } else {
      $POST_DETECT ||= AnyEvent::post_detect {
         undef $POST_DETECT;
         return unless $WRAP_LEVEL;

         (my $level, $WRAP_LEVEL) = ($WRAP_LEVEL, undef);

         require AnyEvent::Strict;

         AnyEvent::post_detect { # make sure we run after AnyEvent::Strict
            wrap ($level);
         };
      };
   }
}

=item AnyEvent::Debug::path2mod $path

Tries to replace a path (e.g. the file name returned by caller)
by a module name. Returns the path unchanged if it fails.

Example:

   print AnyEvent::Debug::path2mod "/usr/lib/perl5/AnyEvent/Debug.pm";
   # might print "AnyEvent::Debug"

=cut

sub path2mod($) {
   keys %INC; # reset iterator

   while (my ($k, $v) = each %INC) {
      if ($_[0] eq $v) {
         $k =~ s%/%::%g if $k =~ s/\.pm$//;
         return $k;
      }
   }

   my $path = shift;

   $path =~ s%^\./%%;

   $path
}

=item AnyEvent::Debug::cb2str $cb

Using various gambits, tries to convert a callback (e.g. a code reference)
into a more useful string.

Very useful if you debug a program and have some callback, but you want to
know where in the program the callback is actually defined.

=cut

sub cb2str($) {
   my $cb = shift;

   require B;

   "CODE" eq ref $cb
      or return "$cb";

   my $cv = B::svref_2object ($cb);

   my $gv = $cv->GV
      or return "$cb";

   return (AnyEvent::Debug::path2mod $gv->FILE) . ":" . $gv->LINE
      if $gv->NAME eq "__ANON__";

   return $gv->STASH->NAME . "::" . $gv->NAME;
}

sub sv2str($) {
   if (ref $_[0]) {
      if (ref $_[0] eq "CODE") {
         return "$_[0]=" . cb2str $_[0];
      } else {
         return "$_[0]";
      }
   } else {
      for ("\'$_[0]\'") { # make copy
         substr $_, $Carp::MaxArgLen, length, "'..."
            if length > $Carp::MaxArgLen;
         return $_;
      }
   }
}

=item AnyEvent::Debug::backtrace [$skip]

Creates a backtrace (actually an AnyEvent::Debug::Backtrace object
that you can stringify), not unlike the Carp module would. Unlike the
Carp module it resolves some references (euch as callbacks) to more
user-friendly strings, has a more succinct output format and most
importantly: doesn't leak memory like hell.

The reason it creates an object is to save time, as formatting can be
done at a later time. Still, creating a backtrace is a relatively slow
operation.

=cut

our %PATHCACHE; # purely to save memory

sub backtrace(;$) {
   my $w = shift;

   my (@bt, @c);
   my ($modlen, $sub);

   for (;;) {
      #         0          1      2            3         4           5          6            7       8         9         10
      # ($package, $filename, $line, $subroutine, $hasargs, $wantarray, $evaltext, $is_require, $hints, $bitmask, $hinthash)
      package DB;
      @c = caller $w++
         or last;
      package AnyEvent::Debug; # no block for speed reasons

      if ($c[7]) {
         $sub = "require $c[6]";
      } elsif (defined $c[6]) {
         $sub = "eval \"\"";
      } else {
         $sub = ($c[4] ? "" : "&") . $c[3];

         $sub .= "("
                 . (join ",",
                       map sv2str $DB::args[$_],
                          0 .. (@DB::args < $Carp::MaxArgNums ? @DB::args : $Carp::MaxArgNums) - 1)
                 . ")"
            if $c[4];
      }

      push @bt, [\($PATHCACHE{$c[1]} ||= $c[1]), $c[2], $sub];
   }

   @DB::args = ();

   bless \@bt, "AnyEvent::Debug::Backtrace"
}

package AnyEvent::Debug::Wrap;

use AnyEvent (); BEGIN { AnyEvent::common_sense }
use Scalar::Util ();
use Carp ();

sub _reset {
   for my $name (qw(io timer signal child idle)) {
      my $super = "SUPER::$name";

      *$name = sub {
         my ($self, %arg) = @_;

         my $w;

         my ($pkg, $file, $line, $sub);
         
         $w = 0;
         do {
            ($pkg, $file, $line) = caller $w++;
         } while $pkg =~ /^(?:AE|AnyEvent::(?:Socket|Handle|Util|Debug|Strict|Base|CondVar|CondVar::Base|Impl::.*))$/;

         $sub = (caller $w)[3];

         my $cb = $arg{cb};
         $arg{cb} = sub {
            ++$w->{called};

            return &$cb
               unless $TRACE_LEVEL;

            local $TRACE_CUR  = "$w";
            AE::log trace => "enter $TRACE_CUR";
            eval {
               local $SIG{__DIE__} = sub { die $_[0] . AnyEvent::Debug::backtrace };
               &$cb;
            };
            if ($@) {
               push @{ $w->{error} }, [AE::now, $@]
                  if @{ $w->{error} } < 10;
               AE::log error => "$TRACE_CUR $@";
            }
            AE::log trace => "leave $TRACE_CUR";
         };

         $self = bless {
            type   => $name,
            w      => $self->$super (%arg),
            file   => $file,
            line   => $line,
            sub    => $sub,
            cur    => $TRACE_CUR,
            now    => AE::now,
            arg    => \%arg,
            cb     => $cb,
            called => 0,
         }, "AnyEvent::Debug::Wrapped";

         delete $arg{cb};

         $self->{bt} = AnyEvent::Debug::backtrace 1
            if $WRAP_LEVEL >= 2;

         Scalar::Util::weaken ($w = $self);
         Scalar::Util::weaken ($AnyEvent::Debug::Wrapped{Scalar::Util::refaddr $self} = $self);

         AE::log trace => "creat $w";

         $self
      };
   }
}

package AnyEvent::Debug::Wrapped;

use AnyEvent (); BEGIN { AnyEvent::common_sense }

use overload
   '""'     => sub {
      $_[0]{str} ||= do {
         my ($pkg, $line) = @{ $_[0]{caller} };

         my $mod = AnyEvent::Debug::path2mod $_[0]{file};
         my $sub = $_[0]{sub};

         if (defined $sub) {
            $sub =~ s/^\Q$mod\E:://;
            $sub = "($sub)";
         }

         "$mod:$_[0]{line}$sub>$_[0]{type}>"
         . (AnyEvent::Debug::cb2str $_[0]{cb})
      };
   },
   fallback => 1,
;

sub verbose {
   my ($self) = @_;

   my $res = "type:    $self->{type} watcher\n"
           . "args:    " . (join " ", %{ $self->{arg} }) . "\n" # TODO: decode fh?
           . "created: " . (AnyEvent::Log::ft $self->{now}) . " ($self->{now})\n"
           . "file:    $self->{file}\n"
           . "line:    $self->{line}\n"
           . "subname: $self->{sub}\n"
           . "context: $self->{cur}\n"
           . "cb:      $self->{cb} (" . (AnyEvent::Debug::cb2str $self->{cb}) . ")\n"
           . "invoked: $self->{called} times\n";

   if (exists $self->{bt}) {
      $res .= "created$self->{bt}";
   }

   if (exists $self->{error}) {
      $res .= "errors:   " . @{$self->{error}} . "\n";

      $res .= "error: " . (AnyEvent::Log::ft $_->[0]) . " ($_->[0]) $_->[1]\n"
         for @{$self->{error}};
   }

   $res
}

sub DESTROY {
   AE::log trace => "dstry $_[0]";

   delete $AnyEvent::Debug::Wrapped{Scalar::Util::refaddr $_[0]};
}

package AnyEvent::Debug::Backtrace;

use AnyEvent (); BEGIN { AnyEvent::common_sense }

sub as_string {
   my ($self) = @_;

   my @bt;
   my $modlen;

   for (@$self) {
      my ($rpath, $line, $sub) = @$_;

      $rpath = (AnyEvent::Debug::path2mod $$rpath) . " line $line";
      $modlen = length $rpath if $modlen < length $rpath;

      push @bt, [$rpath, $sub];
   }

   join "",
      map { sprintf "%*s %s\n", -$modlen, $_->[0], $_->[1] }
         @bt
}

use overload
   '""'     => \&as_string,
   fallback => 1,
;

1;

=back

=head1 AUTHOR

 Marc Lehmann <schmorp@schmorp.de>
 http://home.schmorp.de/

=cut

