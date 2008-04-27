#!perl
use strict;
use AnyEvent::Handle;
use Test::More tests => 1;
use Socket;

my $cv = AnyEvent->condvar;

socketpair my $rd, my $wr, AF_UNIX, SOCK_STREAM, PF_UNSPEC;

my $rd_ae = AnyEvent::Handle->new (fh => $rd);

my $line_cnt = 3;
my $concat;

$rd_ae->readlines (sub {
   my ($rd_ae, @lines) = @_;
   for (@lines) {
      chomp;
      $line_cnt--;
      $concat .= $_;
   }
   if ($line_cnt <= 0) { $cv->broadcast }
});

$wr->syswrite ("A\nBC\nDEF\nG\n");
$wr->syswrite (("X" x 113) . "\n");

$cv->wait;

is ($concat, "ABCDEFG".("X"x113), 'lines were read correctly');
