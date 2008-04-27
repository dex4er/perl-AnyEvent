package AnyEvent::Socket;

use warnings;
use strict;

use Carp;
use Errno qw/ENXIO ETIMEDOUT/;
use Socket;
use IO::Socket::INET;
use AnyEvent;
use AnyEvent::Util;
use AnyEvent::Handle;

our @ISA = qw/AnyEvent::Handle/;

=head1 NAME

AnyEvent::Socket - Connecting sockets for non-blocking I/O

=head1 SYNOPSIS

   use AnyEvent;
   use AnyEvent::Socket;

   my $cv = AnyEvent->condvar;

   my $ae_sock =
      AnyEvent::Socket->new (
         PeerAddr   => "www.google.de:80",
         on_eof     => sub { $cv->broadcast },
         on_connect => sub {
            my ($ae_sock, $error) = @_;
            if ($error) {
               warn "couldn't connect: $!";
               return;
            } else {
               print "connected to ".$ae_sock->fh->peerhost.":".$ae_sock->fh->peerport."\n";
            }

            $ae_sock->on_read (sub {
               my ($ae_sock) = @_;
               print "got data: [".${$ae_sock->rbuf}."]\n";
               $ae_sock->rbuf = '';
            });

            $ae_sock->write ("GET / HTTP/1.0\015\012\015\012");
         }
      );

   $cv->wait;

=head1 DESCRIPTION

L<AnyEvent::Socket> provides method to connect sockets and accept clients
on listening sockets.

=head1 EXAMPLES

See the C<samples/> directory of the L<AnyEvent>
distribution for examples and also the tests in C<t/handle/> can be helpful.

=head1 METHODS

=over 4

=item B<new (%args)>

The constructor gets the same arguments as the L<IO::Socket::INET> constructor.
Except that blocking will always be disabled and the hostname lookup is done by
L<AnyEvent::Util::inet_aton> before the socket (currently a L<IO::Socket::INET> instance)
is created.

Additionally you can set the callbacks that can be set in the L<AnyEvent::Handle>
constructor and these:

=over 4

=item on_connect => $cb

Installs a connect callback, that will be called when the name was successfully
resolved and the connection was successfully established or an error occured in
the lookup or connect.

The first argument to the callback C<$cb> will be the L<AnyEvent::Socket> itself
and the second is either a true value in case an error occured or undef.
The variable C<$!> will be set to one of these values:

=over 4

=item ENXIO

When the DNS lookup failed.

=item ETIMEDOUT

When the connect timed out.

=item *

Or any other errno as set by L<IO::Socket::INET> when it's constructor
failed or the connection couldn't be established for any other reason.

=back

=item on_accept

This sets the C<on_accept> callback by calling the C<on_accept> method.
See also below.

=back

=cut

sub new {
   my $this  = shift;
   my $class = ref($this) || $this;
   my %args  = @_;
   my %self_args;

   $self_args{$_} = delete $args{$_}
      for grep { /^on_/ } keys %args;

   my $self  = $class->SUPER::new (%self_args);
   $self->{sock_args} = \%args;

   if (exists $args{PeerAddr} || exists $args{PeerHost}) {
      $self->{on_connect} ||= sub {
         Carp::croak "Couldn't connect to $args{PeerHost}:$args{PeerPort}: $!"
            if $_[1];
      };
      $self->_connect;
   }

   if ($self->{on_accept}) {
      $self->on_accept ($self->{on_accept});
   }
   
   return $self
}

sub _connect {
   my ($self) = @_;

   if (defined $self->{sock_args}->{Listen}) {
      Carp::croak "connect can be done on a socket that has 'Listen' set!";
   }

   if ($self->{sock_args}->{PeerAddr} =~ /^([^:]+)(?::(\d+))?$/) {
      $self->{sock_args}->{PeerHost} = $1;
      $self->{sock_args}->{PeerPort} = $2 if defined $2;
      delete $self->{sock_args}->{PeerAddr};

      $self->_lookup ($1);
      return;

   } elsif (my $h = $self->{sock_args}->{PeerHost}) {
      $self->_lookup ($h);
      return;

   } else {
      Carp::croak "no PeerAddr or PeerHost provided!";
   }
}

=item B<on_accept ($cb)>

When the socket is run in listening mode (the C<Listen> argument of the socket
is set) this callback will be called when a new client connected.
The first argument to the callback will be the L<AnyEvent::Socket> object itself,
the second the L<AnyEvent::Handle> of the client socket and the third
is the peer address (depending on what C<accept> of L<IO::Socket> gives you>).

=cut

sub on_accept {
   my ($self, $cb) = @_;

   unless (defined $self->{sock_args}->{Listen}) {
      $self->{sock_args}->{Listen} = 10;
   }

   $self->{fh} =
      IO::Socket::INET->new (%{$self->{sock_args}}, Blocking => 0)
         or Carp::croak ("couldn't create listening socket: $!");

   $self->{list_w} =
      AnyEvent->io (poll => 'r', fh => $self->{fh}, cb => sub {
         my ($new_sock, $paddr) = $self->{fh}->accept ();
         unless ($new_sock) {
            $cb->($self);
            delete $self->{list_w};
            return;
         }
         my $ae_hdl = AnyEvent::Handle->new (fh => $new_sock);
         $cb->($self, $ae_hdl, $paddr);
      });
}

sub _lookup {
   my ($self, $host) = @_;

   AnyEvent::Util::inet_aton ($host, sub {
      my ($addr) = @_;

      if ($addr) {
         $self->{sock_args}->{PeerHost} = inet_ntoa $addr;
         $self->_real_connect;

      } else {
         $! = ENXIO;
         $self->{on_connect}->($self, 1);
      }
   });
}

sub _real_connect {
   my ($self) = @_;

   if (defined $self->{sock_args}->{Timeout}) {
      $self->{dns_tmout} =
         AnyEvent->timer (after => $self->{sock_args}->{Timeout}, cb => sub {
            $! = ETIMEDOUT;
            $self->{on_connect}->($self, 1);
         });
   }

   $self->{fh} = IO::Socket::INET->new (%{$self->{sock_args}}, Blocking => 0);
   unless ($self->{fh}) {
      $self->{on_connect}->($self, 1);
      return;
   }

   $self->{con_w} =
      AnyEvent->io (poll => 'w', fh => $self->{fh}, cb => sub {
         delete $self->{con_w};

         if ($! = $self->{fh}->sockopt (SO_ERROR)) {
            $self->{on_connect}->($self, 1);

         } else {
            $self->{on_connect}->($self);
         }
      });
}

=back

=head1 AUTHOR

Robin Redeker, C<< <elmex at ta-sa.org> >>

=head1 COPYRIGHT & LICENSE

Copyright 2008 Robin Redeker, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1; # End of AnyEvent
