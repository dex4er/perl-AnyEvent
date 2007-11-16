$|=1;
BEGIN { print "1..6\n" }

use AnyEvent;
use AnyEvent::Impl::Perl;

print "ok 1\n";

my $cv = AnyEvent->condvar;

my $sw = AnyEvent->signal (signal => 'CHLD', cb => sub {
  print "ok 3\n";
  $cv->broadcast;
});

print "ok 2\n";
kill 'CHLD', 0;
$cv->wait;

print "ok 4\n";

undef $sw;

print "ok 5\n";

kill 'CHLD', 0;

print "ok 6\n";
