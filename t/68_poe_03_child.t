BEGIN {
   # check for broken perls
   if ($^O =~ /mswin32/i) {
      my $ok;
      local $SIG{CHLD} = sub { $ok = 1 };
      kill 'CHLD', 0;

      unless ($ok) {
         print <<EOF;
1..0 # Your perl interpreter is badly BROKEN. Child watchers will not work, ever. Try upgrading to a newer perl or a working perl (cygwin's perl is known to work). If that is not an option, you should be able to use the remaining functionality of AnyEvent, but child watchers WILL NOT WORK.
EOF
         exit 0;
      }
   }
}

BEGIN {
   $|=1;
   print "1..7\n"
}

use POSIX ();

use AnyEvent;
use AnyEvent::Impl::POE; $^W = 0;

$AnyEvent::MAX_SIGNAL_LATENCY = 1;

print "ok 1\n";

AnyEvent::detect; # force-load event model

my $pid = fork;

defined $pid or die "unable to fork";

# work around Tk bug until it has been fixed.
#my $timer = AnyEvent->timer (after => 2, cb => sub { });

my $cv = AnyEvent->condvar;

unless ($pid) {
   print "ok 2\n";
   POSIX::_exit 3;
}

my $w = AnyEvent->child (pid => $pid, cb => sub {
   print $pid == $_[0] ? "" : "not ", "ok 3\ # $pid == $_[0]\n";
   print 3 == ($_[1] >> 8) ? "" : "not ", "ok 4 # 3 == $_[1] >> 8 ($_[1])\n";
   $cv->broadcast;
});

$cv->wait;

my $pid2 = fork || POSIX::_exit 7;

my $cv2 = AnyEvent->condvar;

my $w2 = AnyEvent->child (pid => 0, cb => sub {
   print $pid2 == $_[0] ? "" : "not ", "ok 5 # $pid2 == $_[0]\n";
   print 7 == ($_[1] >> 8) ? "" : "not ", "ok 6 # 7 == $_[1] >> 8 ($_[1])\n";
   $cv2->broadcast;
});

my $error = AnyEvent->timer (after => 15, cb => sub {
   print <<EOF;
Bail out! No child exit detected. This is either a bug in AnyEvent or a bug in your Perl (mostly some windows distributions suffer from that): child watchers might not work properly on this platform. You can force installation of this module if you do not rely on child watchers, or you could upgrade to a working version of Perl for your platform.\n";
EOF
   exit 0;
});

my $inter = AnyEvent->timer (after => 14, cb => sub {
   print "not ok 5 # inter\n";
   print "not ok 6 # inter\n";
   $cv2->send;
});

$cv2->wait;

print "ok 7\n";




