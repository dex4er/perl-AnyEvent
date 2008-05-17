=head1 NAME

AnyEvent::Util - various utility functions.

=head1 SYNOPSIS

 use AnyEvent::Util;

 inet_aton $name, $cb->($ipn || undef);

=head1 DESCRIPTION

This module implements various utility functions, mostly replacing
well-known functions by event-ised counterparts.

=over 4

=cut

package AnyEvent::Util;

use strict;

no warnings "uninitialized";

use Errno;
use Socket ();
use IO::Socket::INET ();

use AnyEvent;

use base 'Exporter';

#our @EXPORT = qw(gethostbyname gethostbyaddr);
our @EXPORT_OK = qw(inet_aton);

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

=item AnyEvent::Util::inet_aton $name_or_address, $cb->($binary_address_or_undef)

Works almost exactly like its Socket counterpart, except that it uses a
callback.

=cut

sub inet_aton {
   my ($name, $cb) = @_;

   if (&dotted_quad) {
      $cb->(Socket::inet_aton $name);
   } elsif ($name eq "localhost") { # rfc2606 et al.
      $cb->(v127.0.0.1);
   } elsif (&has_ev_adns) {
      EV::ADNS::submit ($name, &EV::ADNS::r_addr, 0, sub {
         my (undef, undef, @a) = @_;
         $cb->(@a ? Socket::inet_aton $a[0] : undef);
      });
   } else {
      _do_asy $cb, sub { Socket::inet_aton $_[0] }, @_;
   }
}

=item AnyEvent::Util::fh_nonblocking $fh, $nonblocking

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

sub AnyEvent::Util::Guard::DESTROY {
   ${$_[0]}->();
}

=item $guard = AnyEvent::Util::guard { CODE }

This function creates a special object that, when called, will execute the
code block.

This is often handy in continuation-passing style code to clean up some
resource regardless of where you break out of a process.

=cut

sub guard(&) {
   bless \(my $cb = shift), AnyEvent::Util::Guard::
}

=item my $guard = AnyEvent::Util::tcp_connect $host, $port, $connect_cb[, $prepare_cb]

This is a convenience function that creates a tcp socket and makes a 100%
non-blocking connect to the given C<$host> (which can be a hostname or a
textual IP address) and C<$port>.

Unless called in void context, it returns a guard object that will
automatically abort connecting when it gets destroyed (it does not do
anything to the socket after the conenct was successful).

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

   AnyEvent::Util::tcp_connect "www.google.com", 80,
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

   my $state = {};

   # name resolution
   inet_aton $host, sub {
      return unless $state;

      my $ipn = shift
         or do {
            undef $state;
            $! = &Errno::ENXIO;
            return $connect->();
         };

      # socket creation
      socket $state->{fh}, &Socket::AF_INET, &Socket::SOCK_STREAM, 0
         or do {
            undef $state;
            return $connect->();
         };

      fh_nonblocking $state->{fh}, 1;
      
      # prepare and optional timeout
      if ($prepare) {
         my $timeout = $prepare->($state->{fh});

         $state->{to} = AnyEvent->timer (after => $timeout, cb => sub {
            undef $state;
            $! = &Errno::ETIMEDOUT;
            $connect->();
         }) if $timeout;
      }

      # called when the connect was successful, which,
      # in theory, could be the case immediately (but never is in practise)
      my $connected = sub {
         my $fh = delete $state->{fh};
         undef $state;

         # we are connected, or maybe there was an error
         if (my $sin = getpeername $fh) {
            my ($port, $host) = Socket::unpack_sockaddr_in $sin;
            $connect->($fh, (Socket::inet_ntoa $host), $port);
         } else {
            # dummy read to fetch real error code
            sysread $fh, my $buf, 1;
            $connect->();
         }
      };

      # now connect       
      if (connect $state->{fh}, Socket::pack_sockaddr_in $port, $ipn) {
         $connected->();
      } elsif ($! == &Errno::EINPROGRESS || $! == &Errno::EWOULDBLOCK) { # EINPROGRESS is POSIX
         $state->{ww} = AnyEvent->io (fh => $state->{fh}, poll => 'w', cb => $connected);
      } else {
         undef $state;
         $connect->();
      }
   };

   defined wantarray
      ? guard { undef $state }
      : ()
}

=item AnyEvent::Util::tcp_server $host, $port, $accept_cb[, $prepare_cb]

#TODO#

This will listen and accept new connections on the C<$socket> in a non-blocking
way. The callback C<$client_cb> will be called when a new client connection
was accepted and the callback C<$error_cb> will be called in case of an error.
C<$!> will be set to an approriate error number.

The blocking state of C<$socket> will be set to nonblocking via C<fh_nonblocking> (see
above).

The first argument to C<$client_cb> will be the socket of the accepted client
and the second argument the peer address.

The return value is a guard object that you have to keep referenced as long as you
want to accept new connections.

Here is an example usage:

   my $sock = IO::Socket::INET->new (
       Listen => 5
   ) or die "Couldn't make socket: $!\n";

   my $watchobj = AnyEvent::Util::listen ($sock, sub {
      my ($cl_sock, $cl_addr) = @_;

      my ($port, $addr) = sockaddr_in ($cl_addr);
      $addr = inet_ntoa ($addr);
      print "Client connected: $addr:$port\n";

      # ...

   }, sub {
      warn "Error on accept: $!"
   });

=cut

sub listen {
   my ($socket, $c_cb, $e_cb) = @_;

   fh_nonblocking ($socket, 1);

   my $o =
      AnyEvent::Util::SocketHandle->new (
         fh => $socket,
         client_cb => $c_cb,
         error_cb => $e_cb
      );

   $o->listen;

   $o
}

package AnyEvent::Util::SocketHandle;
use Errno qw/ETIMEDOUT/;
use Socket;
use Scalar::Util qw/weaken/;

sub new {
   my $this  = shift;
   my $class = ref($this) || $this;
   my $self  = { @_ };
   bless $self, $class;

   return $self
}

sub error {
   my ($self) = @_;
   delete $self->{con_w};
   delete $self->{list_w};
   delete $self->{tmout};
   $self->{error_cb}->();
}

sub listen {
   my ($self) = @_;

   weaken $self;

   $self->{list_w} =
      AnyEvent->io (poll => 'r', fh => $self->{fh}, cb => sub {
         my ($new_sock, $paddr) = $self->{fh}->accept ();

         unless (defined $new_sock) {
            $self->error;
            return;
         }

         $self->{client_cb}->($new_sock, $paddr);
      });
}

sub start_timeout {
   my ($self) = @_;

   if (defined $self->{timeout}) {
      $self->{tmout} =
         AnyEvent->timer (after => $self->{timeout}, cb => sub {
            delete $self->{tmout};
            $! = ETIMEDOUT;
            $self->error;
            $self->{timed_out} = 1;
         });
   }
}

sub connect {
   my ($self) = @_;

   weaken $self;

   $self->start_timeout;

   $self->{con_w} =
      AnyEvent->io (poll => 'w', fh => $self->{fh}, cb => sub {
         delete $self->{con_w};
         delete $self->{tmout};

         if ($! = $self->{fh}->sockopt (SO_ERROR)) {
            $self->error;

         } else {
            $self->{connect_cb}->($self->{fh});
         }
      });
}

1;

=back

=head1 AUTHOR

 Marc Lehmann <schmorp@schmorp.de>
 http://home.schmorp.de/

=cut

