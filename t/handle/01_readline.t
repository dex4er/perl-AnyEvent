#!perl
use strict;
use AnyEvent::Handle;
use Test::More tests => 2;
use Socket;


{
   my $cv = AnyEvent->condvar;

   socketpair my $rd, my $wr, AF_UNIX, SOCK_STREAM, PF_UNSPEC;

   my $rd_ae = AnyEvent::Handle->new (fh => $rd);
   my $concat;

   $rd_ae->on_eof (sub { $cv->broadcast });
   $rd_ae->readlines (sub {
      my ($rd_ae, @lines) = @_;
      for (@lines) {
         chomp;
         $concat .= $_;
      }
   });

   $wr->syswrite ("A\nBC\nDEF\nG\n");
   $wr->syswrite (("X" x 113) . "\n");
   $wr->close;

   $cv->wait;

   is ($concat, "ABCDEFG".("X"x113), 'lines were read correctly');
}

{
   my $cv = AnyEvent->condvar;

   socketpair my $rd, my $wr, AF_UNIX, SOCK_STREAM, PF_UNSPEC;

   my $concat;

   my $rd_ae =
      AnyEvent::Handle->new (
         fh => $rd,
         on_eof => sub { $cv->broadcast },
         on_readline => sub {
            my ($rd_ae, @lines) = @_;
            for (@lines) {
               chomp;
               $concat .= $_;
            }
         }
      );

   $wr->syswrite ("A\nBC\nDEF\nG\n");
   $wr->syswrite (("X" x 113) . "\n");
   $wr->close;

   $cv->wait;

   is ($concat, "ABCDEFG".("X"x113), 'second lines were read correctly');
}
