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

use Errno qw/ENXIO/;
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

=item AnyEvent::Util::connect ($socket, $connect_cb->($socket), $error_cb->()[, $timeout])

Connects the socket C<$socket> non-blocking. C<$connect_cb> will be
called when the socket was successfully connected and became writable,
the first argument to the C<$connect_cb> callback will be the C<$socket>
itself.

The blocking state of C<$socket> will be set to nonblocking via C<fh_nonblocking> (see
above).

C<$error_cb> will be called when any error happened while connecting
the socket. C<$!> will be set to an appropriate error number.

If C<$timeout> is given a timeout will be installed for the connect. If the
timeout was reached the C<$error_cb> callback will be called and C<$!> is set to
C<ETIMEDOUT>.

The return value of C<connect> will be a guard object that you have to keep
referenced until you are done with the connect or received an error.
If you let the object's reference drop to zero the internal connect and timeout
watchers will be removed.

Here is a short example, which creates a socket and does a blocking DNS lookup via
L<IO::Socket::INET>:

   my $sock = IO::Socket::INET->new (
       PeerAddr => "www.google.com:80",
       Blocking => 0,
   ) or die "Couldn't make socket: $!\n";

   my $hdl;

   my $watchobj = AnyEvent::Util::connect ($sock, sub {
      my ($sock) = @_;

      $hdl =
         AnyEvent::Handle->new (
            fh => $sock,
            on_eof => sub {
               print "received eof\n";
               undef $hdl
            }
         );

      $hdl->push_write ("GET / HTTP/1.0\015\012\015\012");

      $hdl->push_read_line (sub {
         my ($hdl, $line) = @_;
         print "Yay, got line: $line\n";
      });

   }, sub {
      warn "Got error on connect: $!\n";
   }, 10);

=cut

sub connect {
   my ($socket, $c_cb, $e_cb, $tout) = @_;

   fh_nonblocking ($socket, 1);

   my $o = AnyEvent::Util::SocketHandle->new (
      fh         => $socket,
      connect_cb => $c_cb,
      error_cb   => $e_cb,
      timeout    => $tout,
   );

   $o->connect;

   $o
}

=item AnyEvent::Util::tcp_connect ($host, $port, $connect_cb->($socket), $error_cb->()[, $timeout])

This is a shortcut function which behaves similar to the C<connect> function
described above, except that it does a C<AnyEvent::Util::inet_aton> on C<$host>
and creates a L<IO::Socket::INET> TCP connection for you, which will be
passed as C<$socket> argument to the C<$connect_cb> callback above.

In case the hostname couldn't be resolved C<$error_cb> will be called and C<$!>
will be set to C<ENXIO>.

For more details about the return value and the arguments see the C<connect>
function above.

Here is a short example:


   my $hdl;
   my $watchobj = AnyEvent::Util::tcp_connect ("www.google.com", 80, sub {
      my ($sock) = @_;

      $hdl =
         AnyEvent::Handle->new (
            fh => $sock,
            on_eof => sub {
               print "received eof\n";
               undef $hdl
            }
         );

      $hdl->push_write ("GET / HTTP/1.0\015\012\015\012");

      $hdl->push_read_line (sub {
         my ($hdl, $line) = @_;
         print "Yay, got line: $line\n";
      });

   }, sub {
      warn "Got error on connect: $!\n";
   }, 10);

=cut

sub tcp_connect {
   my ($host, $port, $c_cb, $e_cb, $tout, %sockargs) = @_;

   my $o = AnyEvent::Util::SocketHandle->new (
      connect_cb => $c_cb,
      error_cb   => $e_cb,
      timeout    => $tout,
   );

   $o->start_timeout;

   AnyEvent::Util::inet_aton ($host, sub {
      my ($addr) = @_;

      return if $o->{timed_out};

      if ($addr) {
         my $sock =
            IO::Socket::INET->new (
               PeerHost => Socket::inet_ntoa ($addr),
               PeerPort => $port,
               Blocking => 0,
               %sockargs
            );

         unless ($sock) {
            $o->error;
         }

         fh_nonblocking ($sock, 1);

         $o->{fh} = $sock;

         $o->connect;

      } else {
         $! = ENXIO;
         $o->error;
      }
   });

   $o
}

=item AnyEvent::Util::listen ($socket, $client_cb->($new_socket, $peer_ad), $error_cb->())

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

