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
use IO::Socket::INET ();

use AnyEvent;

use base 'Exporter';

BEGIN {
   *socket_inet_aton = \&Socket::inet_aton; # take a copy, in case Coro::LWP overrides it
}

our @EXPORT = qw(inet_aton fh_nonblocking guard tcp_server tcp_connect);

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

sub dotted_quad($) {
   $_[0] =~ /^(?:25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[0-9][0-9]?)
            \.(?:25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[0-9][0-9]?)
            \.(?:25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[0-9][0-9]?)
            \.(?:25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[0-9][0-9]?)$/x
}

my $has_ev_adns;

sub has_ev_adns {
   ($has_ev_adns ||= do {
      my $model = AnyEvent::detect;
      ($model eq "AnyEvent::Impl::EV" && eval { local $SIG{__DIE__}; require EV::ADNS })
         ? 2 : 1 # so that || always detects as true
   }) - 1  # 2 => true, 1 => false
}

=item inet_aton $name_or_address, $cb->(@addresses)

Works similarly to its Socket counterpart, except that it uses a
callback. Also, if a host has only an IPv6 address, this might be passed
to the callback instead (use the length to detect this - 4 for IPv4, 16
for IPv6).

This function uses various shortcuts and will fall back to either
L<EV::ADNS> or your systems C<inet_aton>.

Unlike the L<Socket> function, you can get multiple IP addresses as result
(currently only when EV::ADNS is being used).

=cut

sub inet_aton {
   my ($name, $cb) = @_;

   if (&dotted_quad) {
      $cb->(socket_inet_aton $name);
   } elsif ($name eq "localhost") { # rfc2606 et al.
      $cb->(v127.0.0.1);
   } elsif (&has_ev_adns) {
      # work around some idiotic adns rfc interpretations
      # rather hackish support for AAAA records (should
      # wait for adns_getaddrinfo...)

      my $loop = 10; # follow cname chains up to this length
      my $qt;
      my $acb; $acb = sub {
         my ($status, undef, @a) = @_;

         if ($status == &EV::ADNS::s_ok) {
            if ($qt eq "a") {
               return $cb->(map +(socket_inet_aton $_), @a);
            } elsif ($qt eq "aaaa") {
               return $cb->(@a);
            } elsif ($qt eq "cname") {
               $name = $a[0]; # there can only be one :)
               $qt = "a";
               return EV::ADNS::submit ($name, &EV::ADNS::r_a, 0, $acb);
            }
         } elsif ($status == &EV::ADNS::s_prohibitedcname) {
            # follow cname chains
            if ($loop--) {
               $qt = "cname";
               return EV::ADNS::submit ($name, &EV::ADNS::r_cname, 0, $acb);
            }
         } elsif ($status == &EV::ADNS::s_nodata) {
            if ($qt eq "a") {
               # ask for raw AAAA (might not be a good method, but adns is too broken...)
               $qt = "aaaa";
               return EV::ADNS::submit ($name, &EV::ADNS::r_unknown | 28, 0, $acb);
            }
         }

         $cb->();
      };
 
      $qt = "a";
      EV::ADNS::submit ($name, &EV::ADNS::r_a, 0, $acb);
   } else {
      _do_asy $cb, sub {
         my $ipn = socket_inet_aton $_[0];
         $ipn ? ($ipn) : ()
      }, @_;
   }
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

=cut

sub AnyEvent::Util::Guard::DESTROY {
   ${$_[0]}->();
}

sub guard(&) {
   bless \(my $cb = shift), AnyEvent::Util::Guard::
}

sub _tcp_port($) {
   $_[0] =~ /^(\d*)$/ and return $1*1;

   (getservbyname $_[0], "tcp")[2]
      or Carp::croak "$_[0]: service unknown"
}

=item my $guard = AnyEvent::Util::tcp_connect $host, $port, $connect_cb[, $prepare_cb]

This function is experimental.

This is a convenience function that creates a tcp socket and makes a 100%
non-blocking connect to the given C<$host> (which can be a hostname or a
textual IP address) and C<$port> (which can be a numeric port number or a
service name).

Unless called in void context, it returns a guard object that will
automatically abort connecting when it gets destroyed (it does not do
anything to the socket after the connect was successful).

If the connect is successful, then the C<$connect_cb> will be invoked with
the socket filehandle (in non-blocking mode) as first and the peer host
(as a textual IP address) and peer port as second and third arguments,
respectively.

If the connect is unsuccessful, then the C<$connect_cb> will be invoked
without any arguments and C<$!> will be set appropriately (with C<ENXIO>
indicating a dns resolution failure).

The filehandle is suitable to be plugged into L<AnyEvent::Handle>, but can
be used as a normal perl file handle as well.

Sometimes you need to "prepare" the socket before connecting, for example,
to C<bind> it to some port, or you want a specific connect timeout that
is lower than your kernel's default timeout. In this case you can specify
a second callback, C<$prepare_cb>. It will be called with the file handle
in not-yet-connected state as only argument and must return the connection
timeout value (or C<0>, C<undef> or the empty list to indicate the default
timeout is to be used).

Note that the socket could be either a IPv4 TCP socket or an IPv6 tcp
socket (although only IPv4 is currently supported by this module).

Simple Example: connect to localhost on port 22.

  AnyEvent::Util::tcp_connect localhost => 22, sub {
     my $fh = shift
        or die "unable to connect: $!";
     # do something
  };

Complex Example: connect to www.google.com on port 80 and make a simple
GET request without much error handling. Also limit the connection timeout
to 15 seconds.

   AnyEvent::Util::tcp_connect "www.google.com", "http",
      sub {
         my ($fh) = @_
            or die "unable to connect: $!";

         my $handle; # avoid direct assignment so on_eof has it in scope.
         $handle = new AnyEvent::Handle
            fh     => $fh,
            on_eof => sub {
               undef $handle; # keep it alive till eof
               warn "done.\n";
            };

         $handle->push_write ("GET / HTTP/1.0\015\012\015\012");

         $handle->push_read_line ("\015\012\015\012", sub {
            my ($handle, $line) = @_;

            # print response header
            print "HEADER\n$line\n\nBODY\n";

            $handle->on_read (sub {
               # print response body
               print $_[0]->rbuf;
               $_[0]->rbuf = "";
            });
         });
      }, sub {
         my ($fh) = @_;
         # could call $fh->bind etc. here

         15
      };

=cut

sub tcp_connect($$$;$) {
   my ($host, $port, $connect, $prepare) = @_;

   # see http://cr.yp.to/docs/connect.html for some background

   my %state = ( fh => undef );

   # name resolution
   inet_aton $host, sub {
      return unless exists $state{fh};

      my $ipn = shift;

      4 == length $ipn
         or do {
            %state = ();
            $! = &Errno::ENXIO;
            return $connect->();
         };

      # socket creation
      socket $state{fh}, &Socket::AF_INET, &Socket::SOCK_STREAM, 0
         or do {
            %state = ();
            return $connect->();
         };

      fh_nonblocking $state{fh}, 1;
      
      # prepare and optional timeout
      if ($prepare) {
         my $timeout = $prepare->($state{fh});

         $state{to} = AnyEvent->timer (after => $timeout, cb => sub {
            %state = ();
            $! = &Errno::ETIMEDOUT;
            $connect->();
         }) if $timeout;
      }

      # called when the connect was successful, which,
      # in theory, could be the case immediately (but never is in practise)
      my $connected = sub {
         my $fh = delete $state{fh};
         %state = ();

         # we are connected, or maybe there was an error
         if (my $sin = getpeername $fh) {
            my ($port, $host) = Socket::unpack_sockaddr_in $sin;
            $connect->($fh, (Socket::inet_ntoa $host), $port);
         } else {
            # dummy read to fetch real error code
            sysread $fh, my $buf, 1 if $! == &Errno::ENOTCONN;
            $connect->();
         }
      };

      # now connect       
      if (connect $state{fh}, Socket::pack_sockaddr_in _tcp_port $port, $ipn) {
         $connected->();
      } elsif ($! == &Errno::EINPROGRESS || $! == &Errno::EWOULDBLOCK) { # EINPROGRESS is POSIX
         $state{ww} = AnyEvent->io (fh => $state{fh}, poll => 'w', cb => $connected);
      } else {
         %state = ();
         $connect->();
      }
   };

   defined wantarray
      ? guard { %state = () } # break any circular dependencies and unregister watchers
      : ()
}

=item $guard = AnyEvent::Util::tcp_server $host, $port, $accept_cb[, $prepare_cb]

This function is experimental.

Create and bind a tcp socket to the given host (any IPv4 host if undef,
otherwise it must be an IPv4 or IPv6 address) and port (service name or
numeric port number, or an ephemeral port if given as zero or undef), set
the SO_REUSEADDR flag and call C<listen>.

For each new connection that could be C<accept>ed, call the C<$accept_cb>
with the filehandle (in non-blocking mode) as first and the peer host and
port as second and third arguments (see C<tcp_connect> for details).

Croaks on any errors.

If called in non-void context, then this function returns a guard object
whose lifetime it tied to the tcp server: If the object gets destroyed,
the server will be stopped (but existing accepted connections will
continue).

If you need more control over the listening socket, you can provide a
C<$prepare_cb>, which is called just before the C<listen ()> call, with
the listen file handle as first argument.

It should return the length of the listen queue (or C<0> for the default).

Example: bind on tcp port 8888 on the local machine and tell each client
to go away.

   AnyEvent::Util::tcp_server undef, 8888, sub {
      my ($fh, $host, $port) = @_;

      syswrite $fh, "The internet is full, $host:$port. Go away!\015\012";
   };

=cut

sub tcp_server($$$;$) {
   my ($host, $port, $accept, $prepare) = @_;

   my %state;

   socket $state{fh}, &Socket::AF_INET, &Socket::SOCK_STREAM, 0
      or Carp::croak "socket: $!";

   setsockopt $state{fh}, &Socket::SOL_SOCKET, &Socket::SO_REUSEADDR, 1
      or Carp::croak "so_reuseaddr: $!";

   bind $state{fh}, Socket::pack_sockaddr_in _tcp_port $port, socket_inet_aton ($host || "0.0.0.0")
      or Carp::croak "bind: $!";

   fh_nonblocking $state{fh}, 1;

   my $len = ($prepare && $prepare->($state{fh})) || 128;

   listen $state{fh}, $len
      or Carp::croak "listen: $!";

   $state{aw} = AnyEvent->io (fh => $state{fh}, poll => 'r', cb => sub {
      # this closure keeps $state alive
      while (my $peer = accept my $fh, $state{fh}) {
         fh_nonblocking $fh, 1; # POSIX requires inheritance, the outside world does not
         my ($port, $host) = Socket::unpack_sockaddr_in $peer;
         $accept->($fh, (Socket::inet_ntoa $host), $port);
      }
   });

   defined wantarray
      ? guard { %state = () } # clear fh and watcher, which breaks the circular dependency
      : ()
}

1;

=back

=head1 AUTHOR

 Marc Lehmann <schmorp@schmorp.de>
 http://home.schmorp.de/

=cut

