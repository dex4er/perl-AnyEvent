#!/usr/bin/perl

use Test::More qw(no_plan);

use strict qw(vars subs);

use AnyEvent::Socket;
use AnyEvent::Handle;

{
   my $ctx = AnyEvent::Handle::TLS_CTX;
   Net::SSLeay::CTX_use_certificate_chain_file ($ctx, $0)
      or die "unable to set certificate chain file";
   Net::SSLeay::CTX_use_PrivateKey_file ($ctx, $0, Net::SSLeay::FILETYPE_PEM ())
      or die "unable to set private key file";
}

for my $mode (1..5) {
   my $server_done = AnyEvent->condvar;
   my $client_done = AnyEvent->condvar;

   my $server_port = AnyEvent->condvar;

   tcp_server "127.0.0.1", undef, sub {
      my ($fh, $host, $port) = @_;

      die unless $host eq "127.0.0.1";

      ok (1, "server_connect $mode");

      my $hd; $hd = new AnyEvent::Handle
         tls      => "accept",
         fh       => $fh,
         timeout  => 8,
         on_error => sub {
            ok (0, "server_error <$!>");
            $server_done->send; undef $hd;
         },
         on_eof   => sub {
            ok (1, "server_eof");
            $server_done->send; undef $hd;
         };

      if ($mode == 1) {
         $hd->push_read (line => sub {
            ok ($_[1] eq "1", "line 1 <$_[1]>");
         });
      } elsif ($mode == 2) {
         $hd->push_write ("2\n");
         $hd->on_drain (sub {
            ok (1, "server_drain");
            $server_done->send; undef $hd;
         });
      } elsif ($mode == 3) {
         $hd->push_read (line => sub {
            ok ($_[1] eq "3", "line 3 <$_[1]>");
            $hd->push_write ("4\n");
            $hd->on_drain (sub {
               ok (1, "server_drain");
               $server_done->send; undef $hd;
            });
         });
      } elsif ($mode == 4) {
         $hd->push_write ("5\n");
         $hd->push_read (line => sub {
            ok ($_[1] eq "6", "line 6 <$_[1]>");
         });
      } elsif ($mode == 5) {
         $hd->on_read (sub {
            ok (1, "on_read");
            $hd->push_read (line => sub {
               my $len = $_[1];
               ok (1, "push_read $len");
               $hd->push_read (packstring => "N", sub {
                  ok ($len == length $_[1], "block server $len");
                  $hd->push_write ("$len\n");
                  $hd->push_write (packstring => "N", $_[1]);
               });
            });
         });
      }

   }, sub {
      $server_port->send ($_[2]);
   };

   tcp_connect "localhost", $server_port->recv, sub {
      my ($fh) = @_;

      ok (1, "client_connect $mode");

      my $hd; $hd = new AnyEvent::Handle
         tls      => "connect",
         fh       => $fh,
         timeout  => 8,
         on_error => sub {
            ok (0, "client_error <$!>");
            $client_done->send; undef $hd;
         },
         on_eof   => sub {
            ok (1, "client_eof");
            $client_done->send; undef $hd;
         };

      if ($mode == 1) {
         $hd->push_write ("1\n");
         $hd->on_drain (sub {
            ok (1, "client_drain");
            $client_done->send; undef $hd;
         });
      } elsif ($mode == 2) {
         $hd->push_read (line => sub {
            ok ($_[1] eq "2", "line 2 <$_[1]>");
         });
      } elsif ($mode == 3) {
         $hd->push_write ("3\n");
         $hd->push_read (line => sub {
            ok ($_[1] eq "4", "line 4 <$_[1]>");
         });
      } elsif ($mode == 4) {
         $hd->push_read (line => sub {
            ok ($_[1] eq "5", "line 5 <$_[1]>");
            $hd->push_write ("6\n");
            $hd->on_drain (sub {
               ok (1, "client_drain");
               $client_done->send; undef $hd;
            });
         });
      } elsif ($mode == 5) {
         # some randomly-sized blocks
         srand 0;
         my $cnt = 64;
         my $block; $block = sub {
            my $len = (16 << int rand 14) - 16 + int rand 32;
            ok (1, "write $len");
            $hd->push_write ("$len\n");
            $hd->push_write (packstring => "N", "\x00" x $len);
         };

         for my $i (1..$cnt) {
            $hd->push_read (line => sub {
               my $len = $_[1];
               ok (1, "client block $len/1");
               $hd->unshift_read (packstring => "N", sub {
                  ok ($len == length $_[1], "client block $len/2");

                  if ($i != $cnt) {
                     $block->();
                  } else {
                     ok (1, "client_drain");
                     $client_done->send; undef $hd;
                  }
               });
            });
         }

         $block->();
      }
   };

   $server_done->recv;
   $client_done->recv;
}

__END__
-----BEGIN CERTIFICATE-----
MIIDJjCCAtCgAwIBAgIJAJ3NPnD6z5+2MA0GCSqGSIb3DQEBBQUAMIGWMQswCQYD
VQQGEwJYTjETMBEGA1UECBMKU29tZS1TdGF0ZTESMBAGA1UEBxMJU29tZS1DaXR5
MRUwEwYDVQQKEwxTb21lLUNvbXBhbnkxEjAQBgNVBAsTCVNvbWUtVW5pdDEQMA4G
A1UEAxMHU29tZS1DTjEhMB8GCSqGSIb3DQEJARYSc29tZUBlbWFpbC5pbnZhbGlk
MB4XDTA4MTAwMTA3NDk1OFoXDTM5MDMwODA3NDk1OFowgZYxCzAJBgNVBAYTAlhO
MRMwEQYDVQQIEwpTb21lLVN0YXRlMRIwEAYDVQQHEwlTb21lLUNpdHkxFTATBgNV
BAoTDFNvbWUtQ29tcGFueTESMBAGA1UECxMJU29tZS1Vbml0MRAwDgYDVQQDEwdT
b21lLUNOMSEwHwYJKoZIhvcNAQkBFhJzb21lQGVtYWlsLmludmFsaWQwXDANBgkq
hkiG9w0BAQEFAANLADBIAkEAvdBuyGvUQ2YDMfEhEi9Rogbz48KNzvF1csGb5qwE
8y7QA9BVBclFMvcO55FQHnWECBI+DNKeP6vJlXN1wMRH5QIDAQABo4H+MIH7MB0G
A1UdDgQWBBScspJuXxPCTlFAyiMeXa6j/zW8ATCBywYDVR0jBIHDMIHAgBScspJu
XxPCTlFAyiMeXa6j/zW8AaGBnKSBmTCBljELMAkGA1UEBhMCWE4xEzARBgNVBAgT
ClNvbWUtU3RhdGUxEjAQBgNVBAcTCVNvbWUtQ2l0eTEVMBMGA1UEChMMU29tZS1D
b21wYW55MRIwEAYDVQQLEwlTb21lLVVuaXQxEDAOBgNVBAMTB1NvbWUtQ04xITAf
BgkqhkiG9w0BCQEWEnNvbWVAZW1haWwuaW52YWxpZIIJAJ3NPnD6z5+2MAwGA1Ud
EwQFMAMBAf8wDQYJKoZIhvcNAQEFBQADQQA48HjY23liyBMmh3cNo9TC+/bu/G3E
oT5npm3+Lh6VA/4kKMyMu2mP31BToTZfl7vUcBJCQBhPFYOiPd/HnwzW
-----END CERTIFICATE-----
-----BEGIN RSA PRIVATE KEY-----
MIIBOwIBAAJBAL3Qbshr1ENmAzHxIRIvUaIG8+PCjc7xdXLBm+asBPMu0APQVQXJ
RTL3DueRUB51hAgSPgzSnj+ryZVzdcDER+UCAwEAAQJAGRftDWHz9dUOpxORo63N
xPXWWE3oIWuac0lVKvGi1eMoI4UCW/Y7qM4rXsUXqasUo3mxV24+QqJHDQid1qi6
AQIhAN5BtiqfjFjb97uUbdE6aiqE+nSG0eXlkeHKNpBNtiUxAiEA2qHNZ5fcQTqT
4qlnYhbI+g6bTwuR7QnzzGTlHUGxsPUCIQDLfvTw37Zb4cNYb1WBPW/ZUHoU2SAz
01cXmdMNmumL8QIhAJMGTENl9FBJPDopAcUM3YqLWBYICdIF51WEZC8QhpYhAiBe
KcoNT51hv3pKK8oZtPJGsKFjmGVVnZeNNzyQmt/YWw==
-----END RSA PRIVATE KEY-----



