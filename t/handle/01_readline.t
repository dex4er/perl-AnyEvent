#!perl

use strict;

use AnyEvent::Impl::Perl;
use AnyEvent::Handle;
use Test::More tests => 3;
use Socket;

{
   my $cv = AnyEvent->condvar;

   socketpair my $rd, my $wr, AF_UNIX, SOCK_STREAM, PF_UNSPEC;

   my $rd_ae = AnyEvent::Handle->new (
      fh     => $rd,
      on_eof => sub { $cv->broadcast },
   );

   my $concat;

   $rd_ae->push_read_line (sub {
      is ($_[1], "A", 'A line was read correctly');
      my $cb; $cb = sub {
         $concat .= $_[1];
         $_[0]->push_read_line ($cb);
      };
      $_[0]->push_read_line ($cb);
   });

   syswrite $wr, "A\nBC\nDEF\nG\n" . ("X" x 113) . "\n";
   close $wr;

   $cv->wait;
   is ($concat, "BCDEFG" . ("X" x 113), 'first lines were read correctly');
}

{
   my $cv = AnyEvent->condvar;

   socketpair my $rd, my $wr, AF_UNIX, SOCK_STREAM, PF_UNSPEC;

   my $concat;

   my $rd_ae =
      AnyEvent::Handle->new (
         fh      => $rd,
         on_eof  => sub { $cv->broadcast },
         on_read => sub {
            $_[0]->push_read_line (sub {
               $concat .= "$_[1]:";
            });
         }
      );

   my $wr_ae = new AnyEvent::Handle fh  => $wr, on_eof => sub { die };

   $wr_ae->push_write ("A\nBC\nDEF\nG\n" . ("X" x 113) . "\n");
   undef $wr;
   undef $wr_ae;

   $cv->wait;

   is ($concat, "A:BC:DEF:G:" . ("X" x 113) . ":", 'second lines were read correctly');
}
