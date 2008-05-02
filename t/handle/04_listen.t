#!/opt/perl/bin/perl

use strict;
use Test::More tests => 2;
use AnyEvent::Impl::Perl;
use AnyEvent;
use AnyEvent::Socket;

my $lbytes;
my $rbytes;

my $cv = AnyEvent->condvar;

my $lsock =
   AnyEvent::Socket->new (
      Listen => 1,
      LocalPort => 32391,
      ReuseAddr => 1,
   );

my $ae_sock =
   AnyEvent::Socket->new (
      PeerAddr => "127.0.0.1:32391",
      on_connect => sub {
         my ($ae_sock, $error) = @_;
         if ($error) { diag "connection failed: $!"; $cv->broadcast; return }

         print "connected to ".$ae_sock->fh->peerhost.":".$ae_sock->fh->peerport."\n";

         $ae_sock->on_read (sub {
            my ($ae_sock) = @_;
            $rbytes = $ae_sock->rbuf;
         });

         $ae_sock->write ("TEST\015\012");
      }
   );

$ae_sock->on_eof (sub { $cv->broadcast });

$lsock->on_accept (sub {
   my ($lsock, $cl, $paddr) = @_;

   unless (defined $cl) {
      diag "accept failed: $!";
      return;
   }

   $cl->read (6, sub {
      my ($cl, $data) = @_;
      $lbytes = $data;
      $cl->write ("BLABLABLA\015\012");
   });
});

$cv->wait;

is ($lbytes, "TEST\015\012", 'listening end received data');
is ($rbytes, "BLABLABLA\015\012", 'connecting received response');

