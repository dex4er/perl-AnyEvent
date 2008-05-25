=head1 NAME

AnyEvent::Socket - useful IPv4 and IPv6 stuff.

=head1 SYNOPSIS

 use AnyEvent::Socket;

 tcp_connect "gameserver.deliantra.net", 13327, sub {
    my ($fh) = @_
       or die "gameserver.deliantra.net connect failed: $!";

    # enjoy your filehandle
 };

 # a simple tcp server
 tcp_server undef, 8888, sub {
    my ($fh, $host, $port) = @_;

    syswrite $fh, "The internet is full, $host:$port. Go away!\015\012";
 };

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
use Socket qw(AF_INET SOCK_STREAM SOCK_DGRAM SOL_SOCKET SO_REUSEADDR);

use AnyEvent ();
use AnyEvent::Util qw(guard fh_nonblocking AF_INET6);
use AnyEvent::DNS ();

use base 'Exporter';

our @EXPORT = qw(parse_ipv4 parse_ipv6 parse_ip format_ip inet_aton tcp_server tcp_connect);

our $VERSION = '1.0';

=item $ipn = parse_ipv4 $dotted_quad

Tries to parse the given dotted quad IPv4 address and return it in
octet form (or undef when it isn't in a parsable format). Supports all
forms specified by POSIX (e.g. C<10.0.0.1>, C<10.1>, C<10.0x020304>,
C<0x12345678> or C<0377.0377.0377.0377>).

=cut

sub parse_ipv4($) {
   $_[0] =~ /^      (?: 0x[0-9a-fA-F]+ | 0[0-7]* | [1-9][0-9]* )
              (?:\. (?: 0x[0-9a-fA-F]+ | 0[0-7]* | [1-9][0-9]* ) ){0,3}$/x
      or return undef;

   @_ = map /^0/ ? oct : $_, split /\./, $_[0];

   # check leading parts against range
   return undef if grep $_ >= 256, @_[0 .. @_ - 2];

   # check trailing part against range
   return undef if $_[-1] >= 1 << (8 * (4 - $#_));

   pack "N", (pop)
             + ($_[0] << 24)
             + ($_[1] << 16)
             + ($_[2] <<  8);
}

=item $ipn = parse_ipv6 $textual_ipv6_address

Tries to parse the given IPv6 address and return it in
octet form (or undef when it isn't in a parsable format).

Should support all forms specified by RFC 2373 (and additionally all IPv4
forms supported by parse_ipv4).

This function works similarly to C<inet_pton AF_INET6, ...>.

=cut

sub parse_ipv6($) {
   # quick test to avoid longer processing
   my $n = $_[0] =~ y/://;
   return undef if $n < 2 || $n > 8;

   my ($h, $t) = split /::/, $_[0], 2;

   unless (defined $t) {
      ($h, $t) = (undef, $h);
   }

   my @h = split /:/, $h;
   my @t = split /:/, $t;

   # check for ipv4 tail
   if (@t && $t[-1]=~ /\./) {
      return undef if $n > 6;

      my $ipn = parse_ipv4 pop @t
         or return undef;

      push @t, map +(sprintf "%x", $_), unpack "nn", $ipn;
   }

   # no :: then we need to have exactly 8 components
   return undef unless @h + @t == 8 || $_[0] =~ /::/;

   # now check all parts for validity
   return undef if grep !/^[0-9a-fA-F]{1,4}$/, @h, @t;

   # now pad...
   push @h, 0 while @h + @t < 8;

   # and done
   pack "n*", map hex, @h, @t
}

=item $ipn = parse_ip $text

Combines C<parse_ipv4> and C<parse_ipv6> in one function.

=cut

sub parse_ip($) {
   &parse_ipv4 || &parse_ipv6
}

=item $text = format_ip $ipn

Takes either an IPv4 address (4 octets) or and IPv6 address (16 octets)
and converts it into textual form.

This function works similarly to C<inet_ntop AF_INET || AF_INET6, ...>,
except it automatically detects the address type.

=cut

sub format_ip;
sub format_ip($) {
   if (4 == length $_[0]) {
      return join ".", unpack "C4", $_[0]
   } elsif (16 == length $_[0]) {
      if (v0.0.0.0.0.0.0.0.0.0.255.255 eq substr $_[0], 0, 12) {
         # v4mapped
         return "::ffff:" . format_ip substr $_[0], 12;
      } else {
         my $ip = sprintf "%x:%x:%x:%x:%x:%x:%x:%x", unpack "n8", $_[0];

         $ip =~ s/^0:(?:0:)*(0$)?/::/
            or $ip =~ s/(:0)+$/::/
            or $ip =~ s/(:0)+/:/;
         return $ip
      }
   } else {
      return undef
   }
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

   if (my $ipn = &parse_ipv4) {
      $cb->($ipn);
   } elsif (my $ipn = &parse_ipv6) {
      $cb->($ipn);
   } elsif ($name eq "localhost") { # rfc2606 et al.
      $cb->(v127.0.0.1, v0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.1);
   } else {
      require AnyEvent::DNS;

      # simple, bad suboptimal algorithm
      AnyEvent::DNS::a ($name, sub {
         if (@_) {
            $cb->(map +(parse_ipv4 $_), @_);
         } else {
            $cb->();
            #AnyEvent::DNS::aaaa ($name, $cb); need inet_pton
         }
      });
   }
}

=item $sa = AnyEvent::Socket::pack_sockaddr $port, $host

Pack the given port/host combination into a binary sockaddr structure. Handles
both IPv4 and IPv6 host addresses.

=cut

sub pack_sockaddr($$) {
   if (4 == length $_[1]) {
      Socket::pack_sockaddr_in $_[0], $_[1]
   } elsif (16 == length $_[1]) {
      pack "SnL a16 L",
         AF_INET6,
         $_[0], # port
         0,     # flowinfo
         $_[1], # addr
         0      # scope id
   } else {
      Carp::croak "pack_sockaddr: invalid host";
   }
}

=item ($port, $host) = AnyEvent::Socket::unpack_sockaddr $sa

Unpack the given binary sockaddr structure (as used by bind, getpeername
etc.) into a C<$port, $host> combination.

Handles both IPv4 and IPv6 sockaddr structures.

=cut

sub unpack_sockaddr($) {
   my $af = unpack "S", $_[0];

   if ($af == AF_INET) {
      Socket::unpack_sockaddr_in $_[0]
   } elsif ($af == AF_INET6) {
      unpack "x2 n x4 a16", $_[0]
   } else {
      Carp::croak "unpack_sockaddr: unsupported protocol family $af";
   }
}

sub _tcp_port($) {
   $_[0] =~ /^(\d*)$/ and return $1*1;

   (getservbyname $_[0], "tcp")[2]
      or Carp::croak "$_[0]: service unknown"
}

=item $guard = tcp_connect $host, $service, $connect_cb[, $prepare_cb]

This is a convenience function that creates a TCP socket and makes a 100%
non-blocking connect to the given C<$host> (which can be a hostname or a
textual IP address) and C<$service> (which can be a numeric port number or
a service name, or a C<servicename=portnumber> string).

If both C<$host> and C<$port> are names, then this function will use SRV
records to locate the real target(s).

In either case, it will create a list of target hosts (e.g. for multihomed
hosts or hosts with both IPv4 and IPv6 addresses) and try to connect to
each in turn.

If the connect is successful, then the C<$connect_cb> will be invoked with
the socket file handle (in non-blocking mode) as first and the peer host
(as a textual IP address) and peer port as second and third arguments,
respectively. The fourth argument is a code reference that you can call
if, for some reason, you don't like this connection, which will cause
C<tcp_connect> to try the next one (or call your callback without any
arguments if there are no more connections). In most cases, you can simply
ignore this argument.

   $cb->($filehandle, $host, $port, $retry)

If the connect is unsuccessful, then the C<$connect_cb> will be invoked
without any arguments and C<$!> will be set appropriately (with C<ENXIO>
indicating a DNS resolution failure).

The file handle is perfect for being plugged into L<AnyEvent::Handle>, but
can be used as a normal perl file handle as well.

Unless called in void context, C<tcp_connect> returns a guard object that
will automatically abort connecting when it gets destroyed (it does not do
anything to the socket after the connect was successful).

Sometimes you need to "prepare" the socket before connecting, for example,
to C<bind> it to some port, or you want a specific connect timeout that
is lower than your kernel's default timeout. In this case you can specify
a second callback, C<$prepare_cb>. It will be called with the file handle
in not-yet-connected state as only argument and must return the connection
timeout value (or C<0>, C<undef> or the empty list to indicate the default
timeout is to be used).

Note that the socket could be either a IPv4 TCP socket or an IPv6 TCP
socket (although only IPv4 is currently supported by this module).

Simple Example: connect to localhost on port 22.

  tcp_connect localhost => 22, sub {
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
   AnyEvent::DNS::addr $host, $port, 0, 0, 0, sub {
      my @target = @_;

      $state{next} = sub {
         return unless exists $state{fh};

         my $target = shift @target
            or do {
               %state = ();
               return $connect->();
            };

         my ($domain, $type, $proto, $sockaddr) = @$target;

         # socket creation
         socket $state{fh}, $domain, $type, $proto
            or return $state{next}();

         fh_nonblocking $state{fh}, 1;
         
         # prepare and optional timeout
         if ($prepare) {
            my $timeout = $prepare->($state{fh});

            $state{to} = AnyEvent->timer (after => $timeout, cb => sub {
               $! = &Errno::ETIMEDOUT;
               $state{next}();
            }) if $timeout;
         }

         # called when the connect was successful, which,
         # in theory, could be the case immediately (but never is in practise)
         my $connected = sub {
            delete $state{ww};
            delete $state{to};

            # we are connected, or maybe there was an error
            if (my $sin = getpeername $state{fh}) {
               my ($port, $host) = unpack_sockaddr $sin;

               my $guard = guard {
                  %state = ();
               };

               $connect->($state{fh}, format_ip $host, $port, sub {
                  $guard->cancel;
                  $state{next}();
               });
            } else {
               # dummy read to fetch real error code
               sysread $state{fh}, my $buf, 1 if $! == &Errno::ENOTCONN;
               $state{next}();
            }
         };

         # now connect       
         if (connect $state{fh}, $sockaddr) {
            $connected->();
         } elsif ($! == &Errno::EINPROGRESS || $! == &Errno::EWOULDBLOCK) { # EINPROGRESS is POSIX
            $state{ww} = AnyEvent->io (fh => $state{fh}, poll => 'w', cb => $connected);
         } else {
            %state = ();
            $connect->();
         }
      };

      $! = &Errno::ENXIO;
      $state{next}();
   };

   defined wantarray && guard { %state = () }
}

=item $guard = tcp_server $host, $port, $accept_cb[, $prepare_cb]

Create and bind a TCP socket to the given host, and port, set the
SO_REUSEADDR flag and call C<listen>.

C<$host> must be an IPv4 or IPv6 address (or C<undef>, in which case it
binds either to C<0> or to C<::>, depending on whether IPv4 or IPv6 is the
preferred protocol).

To bind to the IPv4 wildcard address, use C<0>, to bind to the IPv6
wildcard address, use C<::>.

The port is specified by C<$port>, which must be either a service name or
a numeric port number (or C<0> or C<undef>, in which case an ephemeral
port will be used).

For each new connection that could be C<accept>ed, call the C<<
$accept_cb->($fh, $host, $port) >> with the file handle (in non-blocking
mode) as first and the peer host and port as second and third arguments
(see C<tcp_connect> for details).

Croaks on any errors it can detect before the listen.

If called in non-void context, then this function returns a guard object
whose lifetime it tied to the TCP server: If the object gets destroyed,
the server will be stopped (but existing accepted connections will
continue).

If you need more control over the listening socket, you can provide a
C<< $prepare_cb->($fh, $host, $port) >>, which is called just before the
C<listen ()> call, with the listen file handle as first argument, and IP
address and port number of the local socket endpoint as second and third
arguments.

It should return the length of the listen queue (or C<0> for the default).

Example: bind on TCP port 8888 on the local machine and tell each client
to go away.

   tcp_server undef, 8888, sub {
      my ($fh, $host, $port) = @_;

      syswrite $fh, "The internet is full, $host:$port. Go away!\015\012";
   };

=cut

sub tcp_server($$$;$) {
   my ($host, $port, $accept, $prepare) = @_;

   $host = $AnyEvent::PROTOCOL{ipv4} > $AnyEvent::PROTOCOL{ipv6} && AF_INET6
           ? "::" : "0"
      unless defined $host;

   my $ipn = parse_ip $host
      or Carp::croak "AnyEvent::Socket::tcp_server: cannot parse '$host' as IPv4 or IPv6 address";

   my $domain = 4 == length $ipn ? AF_INET : AF_INET6;

   my %state;

   socket $state{fh}, $domain, SOCK_STREAM, 0
      or Carp::croak "socket: $!";

   setsockopt $state{fh}, SOL_SOCKET, SO_REUSEADDR, 1
      or Carp::croak "so_reuseaddr: $!";

   bind $state{fh}, pack_sockaddr _tcp_port $port, $ipn
      or Carp::croak "bind: $!";

   fh_nonblocking $state{fh}, 1;

   my $len;

   if ($prepare) {
      my ($port, $host) = unpack_sockaddr getsockname $state{fh};
      $len = $prepare && $prepare->($state{fh}, format_ip $host, $port);
   }
   
   $len ||= 128;

   listen $state{fh}, $len
      or Carp::croak "listen: $!";

   $state{aw} = AnyEvent->io (fh => $state{fh}, poll => 'r', cb => sub {
      # this closure keeps $state alive
      while (my $peer = accept my $fh, $state{fh}) {
         fh_nonblocking $fh, 1; # POSIX requires inheritance, the outside world does not
         my ($port, $host) = unpack_sockaddr $peer;
         $accept->($fh, format_ip $host, $port);
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

