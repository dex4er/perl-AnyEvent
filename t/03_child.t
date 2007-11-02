$|=1;
BEGIN { print "1..5\n" }

use AnyEvent;

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
   print 3 == ($? >> 8) ? "" : "not ", "ok 3\n";
   $cv->broadcast;
});

$cv->wait;

fork || exit 7;

my $cv2 = AnyEvent->condvar;

my $w2 = AnyEvent->child (pid => 0, cb => sub {
   print 7 == ($? >> 8) ? "" : "not ", "ok 4\n";
   $cv2->broadcast;
});

$cv2->wait;

print "ok 5\n";




