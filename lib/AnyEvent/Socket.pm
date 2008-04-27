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

=head1 METHODS

=over 4

=item B<new (%args)>

The constructor gets the same arguments as the L<IO::Socket::INET> constructor.
Except that blocking will always be disabled and the hostname lookup is done by
L<AnyEvent::Util::inet_aton> before the L<IO::Socket::INET> instance is created.

  AnyEvent::Socket->new (
     PeerAddr   => "www.google.de:80",
     on_connect => sub {
        my ($aesock, $error) = @_;
        if ($error) { die "couldn't connect: $!" }
     }
  );

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
