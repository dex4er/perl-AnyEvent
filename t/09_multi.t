use AnyEvent;
use AnyEvent::Util;
BEGIN { require AnyEvent::Impl::Perl unless $ENV{PERL_ANYEVENT_MODEL} }

$| = 1; print "1..14\n";

print "ok 1\n";

my ($a, $b) = AnyEvent::Util::portable_socketpair;

# I/O write
{
   my $cv = AE::cv;
   my $wt = AE::timer 0.1, 0, $cv;
   my $s = 0;

   $cv->begin; my $wa = AE::io $a, 1, sub { $cv->end; $s |= 1 };
   $cv->begin; my $wb = AE::io $a, 1, sub { $cv->end; $s |= 2 };

   $cv->recv;

   print $s == 3 ? "" : "not ", "ok 2 # $s\n";
}

# I/O read
{
   my $cv = AE::cv;
   my $wt = AE::timer 0.1, 0, $cv;
   my $s = 0;

   $cv->begin; my $wa = AE::io $a, 0, sub { $cv->end; $s |= 1 };
   $cv->begin; my $wb = AE::io $a, 0, sub { $cv->end; $s |= 2 };

   $cv->recv;

   print $s == 0 ? "" : "not ", "ok 3 # $s\n";

   syswrite $b, "x";

   $cv = AE::cv;
   $wt = AE::timer 0.1, 0, $cv;

   $s = 0;
   $cv->recv;

   print $s == 3 ? "" : "not ", "ok 4 # $s\n";

   sysread $a, my $dummy, 1;

   $cv = AE::cv;
   $wt = AE::timer 0.1, 0, $cv;

   $s = 0;
   $cv->recv;

   print $s == 0 ? "" : "not ", "ok 5 # $s\n";
}

# signal
{
   my $cv = AE::cv;
   my $wt = AE::timer 0.1, 0, $cv;
   my $s = 0;

   $cv->begin; my $wa = AE::signal INT => sub { $cv->end; $s |= 1 };
   $cv->begin; my $wb = AE::signal INT => sub { $cv->end; $s |= 2 };

   $cv->recv;

   print $s == 0 ? "" : "not ", "ok 6 # $s\n";

   kill INT => $$;

   $cv = AE::cv;
   $wt = AE::timer 0.1, 0, $cv;

   $s = 0;
   $cv->recv;

   print $s == 3 ? "" : "not ", "ok 7 # $s\n";

   $cv = AE::cv;
   $wt = AE::timer 0.1, 0, $cv;

   $s = 0;
   $cv->recv;

   print $s == 0 ? "" : "not ", "ok 8 # $s\n";
}

$AnyEvent::MAX_SIGNAL_LATENCY = 0.2;

# child
{
   my $cv = AE::cv;
   my $wt = AE::timer 0.1, 0, $cv;
   my $s = 0;

   my $pid = fork;

   unless ($pid) {
      sleep 2;
      exit 1;
   }

   my ($apid, $bpid, $astatus, $bstatus);

   $cv->begin; my $wa = AE::child $pid, sub { ($apid, $astatus) = @_; $cv->end; $s |= 1 };
   $cv->begin; my $wb = AE::child $pid, sub { ($bpid, $bstatus) = @_; $cv->end; $s |= 2 };

   $cv->recv;

   print $s == 0 ? "" : "not ", "ok 9 # $s\n";

   kill 9, $pid;

   $cv = AE::cv;
   $wt = AE::timer 0.1, 0, $cv;

   $s = 0;
   $cv->recv;

   print $s == 3 ? "" : "not ", "ok 10 # $s\n";
   print $apid == $pid && $bpid == $pid ? "" : "not ", "ok 11 # $apid == $bpid == $pid\n";
   print $astatus == 9 && $bstatus == 9 ? "" : "not ", "ok 12 # $astatus == $bstatus == 9\n";

   $cv = AE::cv;
   $wt = AE::timer 0.1, 0, $cv;

   $s = 0;
   $cv->recv;

   print $s == 0 ? "" : "not ", "ok 13 # $s\n";
}

print "ok 14\n";

exit 0;

