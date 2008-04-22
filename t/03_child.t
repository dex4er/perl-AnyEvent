$|=1;
BEGIN {
   print "1..7\n"
}

use AnyEvent;
use AnyEvent::Impl::Perl;

print STDERR <<EOF;

If the following test hangs for a long time you either found a bug in
AnyEvent or, more likely, you have a defective perl (most windows perl
distros are broken, cygwin perl works). If you do not rely on child
handlers you can force the installation of this module and the rest will
likely work. Otherwise upgrading to a working perl is recommended.
EOF

print "ok 1\n";

my $pid = fork;

defined $pid or die "unable to fork";

# work around Tk bug until it has been fixed.
#my $timer = AnyEvent->timer (after => 2, cb => sub { });

my $cv = AnyEvent->condvar;

unless ($pid) {
   print "ok 2\n";
   exit 3;
}

my $w = AnyEvent->child (pid => $pid, cb => sub {
   print $pid == $_[0] ? "" : "not ", "ok 3\ # $pid == $_[0]\n";
   print 3 == ($_[1] >> 8) ? "" : "not ", "ok 4 # 3 == $_[1] >> 8 ($_[1])\n";
   $cv->broadcast;
});

$cv->wait;

my $pid2 = fork || exit 7;

my $cv2 = AnyEvent->condvar;

my $w2 = AnyEvent->child (pid => 0, cb => sub {
   print $pid2 == $_[0] ? "" : "not ", "ok 5 # $pid2 == $_[0]\n";
   print 7 == ($_[1] >> 8) ? "" : "not ", "ok 6 # 7 == $_[1] >> 8 ($_[1])\n";
   $cv2->broadcast;
});

my $error = AnyEvent->timer (after => 5, cb => sub {
   print <<EOF;
Bail out! No child exit detected. This is either a bug in AnyEvent or a bug in your Perl (mostly some windows distributions suffer from that): child watchers might not work properly on this platform. You can force installation of this module if you do not rely on child watchers, or you could upgrade to a working version of Perl for your platform.\n";
EOF
   exit 0;
});

$cv2->wait;

print "ok 7\n";




