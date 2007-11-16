$|=1;
BEGIN { print "1..7\n" }

use AnyEvent;
use AnyEvent::Impl::Perl;

print "ok 1\n";

my $pid = fork;

defined $pid or die "unable to fork";

# work around Tk bug until it has been fixed.
my $timer = AnyEvent->timer (after => 2, cb => sub { });

my $cv = AnyEvent->condvar;

unless ($pid) {
   print "ok 2\n";
   exit 3;
}

my $w = AnyEvent->child (pid => $pid, cb => sub {
   print $pid == $_[0] ? "" : "not ", "ok 3\n";
   print 3 == ($_[1] >> 8) ? "" : "not ", "ok 4\n";
   $cv->broadcast;
});

$cv->wait;

my $pid2 = fork || exit 7;

my $cv2 = AnyEvent->condvar;

my $w2 = AnyEvent->child (pid => 0, cb => sub {
   print $pid2 == $_[0] ? "" : "not ", "ok 5\n";
   print 7 == ($_[1] >> 8) ? "" : "not ", "ok 6\n";
   $cv2->broadcast;
});

$cv2->wait;

print "ok 7\n";




