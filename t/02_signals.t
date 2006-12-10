$|=1;
BEGIN { print "1..5\n" }

use AnyEvent;

print "ok 1\n";

my $cv = AnyEvent->condvar;

my $sw = AnyEvent->signal (signal => 'CHLD', cb => sub {
  print "ok 3\n";
  $cv->broadcast;
});

print "ok 2\n";
kill 'CHLD', 0;
$cv->wait;

undef $sw;

print "ok 4\n";

kill 'CHLD', 0;

print "ok 5\n";
