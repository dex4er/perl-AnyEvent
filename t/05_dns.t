$|=1;
BEGIN { print "1..2\n" }

# we avoid complicated tests here because some systems will
# not have working DNS

use AnyEvent::Impl::Perl;
use AnyEvent::DNS;

print "ok 1\n";

AnyEvent::DNS::resolver;

print "ok 2\n";

