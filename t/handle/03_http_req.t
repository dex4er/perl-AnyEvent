#!/opt/perl/bin/perl
use strict;
use Test::More tests => 2;
use AnyEvent;
use AnyEvent::Socket;

my $cv = AnyEvent->condvar;

my $fbytes;
my $rbytes;

my $ae_sock =
   AnyEvent::Socket->new (
      PeerAddr => "www.google.de:80",
      on_eof   => sub { $cv->broadcast },
      on_error => sub {
         my ($ae_sock) = @_;
         diag "error: $!";
         $cv->broadcast
      },
      on_connect => sub {
         my ($ae_sock, $error) = @_;
         if ($error) { diag ("connect error: $!"); return }

         $ae_sock->read (10, sub {
            my ($ae_sock, $data) = @_;
            $fbytes = $data;

            $ae_sock->on_read (sub {
               my ($ae_sock) = @_;
               $rbytes = $ae_sock->rbuf;
            });
         });

         $ae_sock->write ("GET http://www.google.de/ HTTP/1.0\015\012\015\012");
      }
   );

$cv->wait;

is (substr ($fbytes, 0, 4), 'HTTP', 'first bytes began with HTTP');
ok ($rbytes =~ /google.*<\/html>\s*$/i, 'content was retrieved successfully');
