$|=1;
BEGIN { print "1..2\n" }

# we avoid complicated tests here because some systems will
# not have working DNS

use AnyEvent::DNS;

print "ok 1\n";

AnyEvent->resolver;

print "ok 2\n";

