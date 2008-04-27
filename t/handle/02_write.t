#!perl
use strict;
use AnyEvent::Handle;
use Test::More tests => 2;
use Socket;

my $cv = AnyEvent->condvar;

socketpair my $rd, my $wr, AF_UNIX, SOCK_STREAM, PF_UNSPEC;

my $rd_ae = AnyEvent::Handle->new (fh => $rd);

my $dat = '';
my $write_cb_called = 0;

$rd_ae->read (5132, sub {
   my ($rd_ae, $data) = @_;
   $dat = substr $data, 0, 2;
   $dat .= substr $data, -5;
   $rd_ae->read (1, sub { $cv->broadcast });
});

my $wr_ae = AnyEvent::Handle->new (fh => $wr);

$wr_ae->write ("A" x 5000);
$wr_ae->write (("X" x 130), sub { $write_cb_called++; });
$wr_ae->write ("Y", sub { $write_cb_called++; });
$wr_ae->write ("Z");
$wr_ae->write (sub { $write_cb_called++; });
$wr_ae->write ("A" x 5000);
$wr_ae->write (sub { $write_cb_called++ });

$cv->wait;

is ($dat, "AAXXXYZ", 'lines were read and written correctly');
is ($write_cb_called, 4, 'write callbacks called correctly');
