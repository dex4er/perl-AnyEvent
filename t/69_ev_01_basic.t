$|=1;
BEGIN { unless (eval "require EV") { print "1..0 # skip because EV isn't installed"; exit } }
BEGIN { print "1..6\n" }

use AnyEvent;
use AnyEvent::Impl::EV;

print "ok 1\n";

my $cv = AnyEvent->condvar;

print "ok 2\n";

my $timer1 = AnyEvent->timer (after => 0.1, cb => sub { print "ok 5\n"; $cv->broadcast });

print "ok 3\n";

AnyEvent->timer (after => 0.01, cb => sub { print "not ok 5\n" });

print "ok 4\n";

$cv->wait;

print "ok 6\n";

