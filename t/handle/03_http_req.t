#!/opt/perl/bin/perl
use strict;
use AnyEvent::Impl::Perl;
use AnyEvent;
use AnyEvent::Socket;

unless ($ENV{PERL_ANYEVENT_NET_TESTS}) {
   print "1..0 # Skip PERL_ANYEVENT_NET_TESTS environment variable not set\n";
   exit 0;
}

print "1..2\n";

my $cv = AnyEvent->condvar;

my $rbytes;

my $hdl;
my $wo = AnyEvent::Util::tcp_connect ('www.google.com', 80, sub {
   my ($sock) = @_;
   $hdl =
      AnyEvent::Handle->new (
         fh => $sock,
         on_error => sub {
            warn "socket error: $!";
            $cv->broadcast;
         },
         on_eof => sub {
            my ($hdl) = @_;

            if ($rbytes !~ /<\/html>/i) {
               print "not ";
            }

            print "ok 2 - received HTML page\n";

            $cv->broadcast
         }
      );

   $hdl->push_read_chunk (10, sub {
      my ($hdl, $data) = @_;

      unless (substr ($data, 0, 4) eq 'HTTP') {
         print "not ";
      }

      print "ok 1 - received 'HTTP'\n";

      $hdl->on_read (sub {
         my ($hdl) = @_;
         $rbytes .= $hdl->rbuf;
         $hdl->rbuf = '';
         return 1;
      });
   });

   $hdl->push_write ("GET http://www.google.com/ HTTP/1.0\015\012\015\012");

}, sub {
   warn "error on connect: $!";
}, 10);

$cv->wait;
