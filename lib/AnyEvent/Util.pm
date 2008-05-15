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

use Socket ();

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

=item AnyEvent::Util::connect ($socket, $connect_cb, $error_cb[, $timeout])

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
   delete $self->{tmout};
   $self->{error_cb}->();
}

sub connect {
   my ($self) = @_;

   weaken $self;

   if (defined $self->{timeout}) {
      $self->{tmout} =
         AnyEvent->timer (after => $self->{timeout}, cb => sub {
            $! = ETIMEDOUT;
            $self->error;
         });
   }

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

