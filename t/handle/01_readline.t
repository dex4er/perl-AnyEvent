#!perl

use strict;

use AnyEvent::Impl::Perl;
use AnyEvent::Handle;
use Test::More tests => 7;
use Socket;

{
   my $cv = AnyEvent->condvar;

   socketpair my $rd, my $wr, AF_UNIX, SOCK_STREAM, PF_UNSPEC;

   my $rd_ae = AnyEvent::Handle->new (
      fh       => $rd,
      on_error => sub {
         ok ($! == Errno::EPIPE);
      },
      on_eof   => sub { $cv->broadcast },
   );

   my $concat;

   $rd_ae->push_read (line => sub {
      is ($_[1], "A", 'A line was read correctly');
      my $cb; $cb = sub {
         $concat .= $_[1];
         $_[0]->push_read (line => $cb);
      };
      $_[0]->push_read (line => $cb);
   });

   syswrite $wr, "A\012BC\012DEF\012G\012" . ("X" x 113) . "\012";
   close $wr;

   $cv->wait;
   is ($concat, "BCDEFG" . ("X" x 113), 'initial lines were read correctly');
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
            $_[0]->push_read (line => sub {
               $concat .= "$_[1]:";
            });
         }
      );

   my $wr_ae = new AnyEvent::Handle fh  => $wr, on_eof => sub { die };

   undef $wr;
   undef $rd;

   $wr_ae->push_write (netstring => "0:xx,,");
   $wr_ae->push_write (netstring => "");
   $wr_ae->push_write (packstring => "w", "hallole" x 99);
   $wr_ae->push_write ("A\nBC\nDEF\nG\n" . ("X" x 113) . "\n");
   undef $wr_ae;

   $rd_ae->push_read (netstring => sub { is ($_[1], "0:xx,,"); });
   $rd_ae->push_read (netstring => sub { is ($_[1], ""); });
   $rd_ae->push_read (packstring => "w", sub { is ($_[1], "hallole" x 99); });

   $cv->wait;

   is ($concat, "A:BC:DEF:G:" . ("X" x 113) . ":", 'second lines were read correctly');
}

