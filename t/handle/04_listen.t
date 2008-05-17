#!/opt/perl/bin/perl

use strict;

use AnyEvent::Impl::Perl;
use AnyEvent::Handle;
use AnyEvent::Util;

my $lbytes;
my $rbytes;

print "1..2\n";

my $cv = AnyEvent->condvar;

my $hdl;
my $port;

my $w = AnyEvent::Util::tcp_server undef, undef,
   sub {
      my ($fh, $host, $port) = @_;

      $hdl = AnyEvent::Handle->new (fh => $fh, on_eof => sub { $cv->broadcast });

      $hdl->push_read_chunk (6, sub {
         my ($hdl, $data) = @_;

         if ($data eq "TEST\015\012") {
            print "ok 1 - server received client data\n";
         } else {
            print "not ok 1 - server received bad client data\n";
         }

         $hdl->push_write ("BLABLABLA\015\012");
      });
   }, sub {
      ($port) = Socket::unpack_sockaddr_in getsockname $_[0];

      0
   };


my $clhdl;
my $wc = AnyEvent::Util::tcp_connect localhost => $port, sub {
   my ($fh) = @_;

   $clhdl = AnyEvent::Handle->new (fh => $fh, on_eof => sub { $cv->broadcast });

   $clhdl->push_write ("TEST\015\012");
   $clhdl->push_read_line (sub {
      my ($clhdl, $line) = @_;

      if ($line eq 'BLABLABLA') {
         print "ok 2 - client received response\n";
      } else {
         print "not ok 2 - client received bad response\n";
      }

      $cv->broadcast;
   });
};

$cv->wait;
