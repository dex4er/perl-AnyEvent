#!/opt/perl/bin/perl
use strict;
use AnyEvent::Impl::Perl;
use AnyEvent::Handle;
use AnyEvent::Util;
use IO::Socket::INET;

my $lbytes;
my $rbytes;

print "1..2\n";

my $cv = AnyEvent->condvar;

my $sock = IO::Socket::INET->new (
    Listen => 5, ReuseAddr => 1, LocalAddr => 'localhost',
) or die "Couldn't make socket: $!\n";

my $hdl;

my $w = AnyEvent::Util::listen ($sock, sub {
   my ($cl, $claddr) = @_;
   $hdl = AnyEvent::Handle->new (fh => $cl, on_eof => sub { $cv->broadcast });

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
   warn "error on accept: $!";
   $cv->broadcast;
});

my $clhdl;
my $wc = AnyEvent::Util::tcp_connect ($sock->sockhost, $sock->sockport, sub {
   my ($clsock) = @_;
   $clhdl = AnyEvent::Handle->new (fh => $clsock, on_eof => sub { $cv->broadcast });

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
}, sub {
   warn "couldn't connect: $!";
   $cv->broadcast;
}, 10);

$cv->wait;
