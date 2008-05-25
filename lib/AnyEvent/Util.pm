=head1 NAME

AnyEvent::Util - various utility functions.

=head1 SYNOPSIS

 use AnyEvent::Util;

=head1 DESCRIPTION

This module implements various utility functions, mostly replacing
well-known functions by event-ised counterparts.

All functions documented without C<AnyEvent::Util::> prefix are exported
by default.

=over 4

=cut

package AnyEvent::Util;

no warnings;
use strict;

use Carp ();
use Errno ();
use Socket ();

use AnyEvent ();

use base 'Exporter';

BEGIN {
   *socket_inet_aton = \&Socket::inet_aton; # take a copy, in case Coro::LWP overrides it
}

BEGIN {
   my $af_inet6 = eval { &Socket::AF_INET6 };
   eval "sub AF_INET6() { $af_inet6 }"; die if $@;

   delete $AnyEvent::PROTOCOL{ipv6} unless $af_inet6;
}

BEGIN {
   # broken windows perls use undocumented error codes...
   if ($^O =~ /mswin32/i) {
      eval "sub WSAEAGAIN() { 10035 }";
   } else {
      eval "sub WSAEAGAIN() { -1e99 }"; # should never match any errno value
   }
}

our @EXPORT = qw(fh_nonblocking guard);
our @EXPORT_OK = qw(AF_INET6 WSAEAGAIN);

our $VERSION = '1.0';

our $MAXPARALLEL = 16; # max. number of parallel jobs

our $running;
our @queue;

sub _schedule;
sub _schedule {
   return unless @queue;
   return if $running >= $MAXPARALLEL;

   ++$running;
   my ($cb, $sub, @args) = @{shift @queue};

   if (eval { local $SIG{__DIE__}; require POSIX }) {
      my $pid = open my $fh, "-|";

      if (!defined $pid) {
         die "fork: $!";
      } elsif (!$pid) {
         syswrite STDOUT, join "\0", map { unpack "H*", $_ } $sub->(@args);
         POSIX::_exit (0);
      }

      my $w; $w = AnyEvent->io (fh => $fh, poll => 'r', cb => sub {
         --$running;
         _schedule;
         undef $w;

         my $buf;
         sysread $fh, $buf, 16384, length $buf;
         $cb->(map { pack "H*", $_ } split /\0/, $buf);
      });
   } else {
      $cb->($sub->(@args));
   }
}

sub _do_asy {
   push @queue, [@_];
   _schedule;
}

# to be removed
sub dotted_quad($) {
   $_[0] =~ /^(?:25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[0-9][0-9]?)
            \.(?:25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[0-9][0-9]?)
            \.(?:25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[0-9][0-9]?)
            \.(?:25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[0-9][0-9]?)$/x
}

# just a forwarder
sub inet_aton {
   require AnyEvent::Socket;
   *inet_aton = \&AnyEvent::Socket::inet_aton;
   goto &inet_aton
}

=item fh_nonblocking $fh, $nonblocking

Sets the blocking state of the given filehandle (true == nonblocking,
false == blocking). Uses fcntl on anything sensible and ioctl FIONBIO on
broken (i.e. windows) platforms.

=cut

sub fh_nonblocking($$) {
   my ($fh, $nb) = @_;

   require Fcntl;

   if ($^O eq "MSWin32") {
      $nb = (! ! $nb) + 0;
      ioctl $fh, 0x8004667e, \$nb; # FIONBIO
   } else {
      fcntl $fh, &Fcntl::F_SETFL, $nb ? &Fcntl::O_NONBLOCK : 0;
   }
}

=item $guard = guard { CODE }

This function creates a special object that, when called, will execute the
code block.

This is often handy in continuation-passing style code to clean up some
resource regardless of where you break out of a process.

You can call one method on the returned object:

=item $guard->cancel

This simply causes the code block not to be invoked: it "cancels" the
guard.

=cut

sub AnyEvent::Util::Guard::DESTROY {
   ${$_[0]}->();
}

sub AnyEvent::Util::Guard::cancel($) {
   ${$_[0]} = sub { };
}

sub guard(&) {
   bless \(my $cb = shift), AnyEvent::Util::Guard::
}

1;

=back

=head1 AUTHOR

 Marc Lehmann <schmorp@schmorp.de>
 http://home.schmorp.de/

=cut

