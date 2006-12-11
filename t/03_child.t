$|=1;
BEGIN { print "1..4\n" }

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

print "ok 4\n";




