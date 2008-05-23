=head1 NAME

AnyEvent::Socket - useful IPv4 and IPv6 stuff.

=head1 SYNOPSIS

 use AnyEvent::Socket;

=head1 DESCRIPTION

This module implements various utility functions for handling internet
protocol addresses and sockets, in an as transparent and simple way as
possible.

All functions documented without C<AnyEvent::Socket::> prefix are exported
by default.

=over 4

=cut

package AnyEvent::Socket;

no warnings;
use strict;

use Carp ();
use Errno ();
use Socket ();

use AnyEvent ();
use AnyEvent::Util qw(guard fh_nonblocking);

use base 'Exporter';

BEGIN {
   *socket_inet_aton = \&Socket::inet_aton; # take a copy, in case Coro::LWP overrides it
}

our @EXPORT = qw(inet_aton tcp_server tcp_connect);

our $VERSION = '1.0';

sub dotted_quad($) {
   $_[0] =~ /^(?:25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[0-9][0-9]?)
            \.(?:25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[0-9][0-9]?)
            \.(?:25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[0-9][0-9]?)
            \.(?:25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[0-9][0-9]?)$/x
}

=item inet_aton $name_or_address, $cb->(@addresses)

Works similarly to its Socket counterpart, except that it uses a
callback. Also, if a host has only an IPv6 address, this might be passed
to the callback instead (use the length to detect this - 4 for IPv4, 16
for IPv6).

Unlike the L<Socket> function of the same name, you can get multiple IPv4
and IPv6 addresses as result.

=cut

sub inet_aton {
   my ($name, $cb) = @_;

   if (&dotted_quad) {
      $cb->(socket_inet_aton $name);
   } elsif ($name eq "localhost") { # rfc2606 et al.
      $cb->(v127.0.0.1);
   } else {
      require AnyEvent::DNS;

      # simple, bad suboptimal algorithm
      AnyEvent::DNS::a ($name, sub {
         if (@_) {
            &$cb;
         } else {
            AnyEvent::DNS::aaaa ($name, $cb);
         }
      });
   }
}

sub _tcp_port($) {
   $_[0] =~ /^(\d*)$/ and return $1*1;

   (getservbyname $_[0], "tcp")[2]
      or Carp::croak "$_[0]: service unknown"
}

=item $guard = tcp_connect $host, $port, $connect_cb[, $prepare_cb]

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

   tcp_connect "www.google.com", "http",
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

=item $guard = tcp_server $host, $port, $accept_cb[, $prepare_cb]

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

   tcp_server undef, 8888, sub {
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

