$|=1;
BEGIN { unless (eval "require EV") { print "1..0 # skip because EV isn't installed"; exit } }
BEGIN { print "1..5\n" }

# we avoid complicated tests here because some systems will
# not have working DNS

use AnyEvent::Impl::EV;
use AnyEvent::DNS;

print "ok 1\n";

AnyEvent::DNS::resolver;

print "ok 2\n";

# make sure we timeout faster
AnyEvent::DNS::resolver->{timeout} = [0.5];
AnyEvent::DNS::resolver->_compile;

print "ok 3\n";

my $cv = AnyEvent->condvar;

AnyEvent::DNS::a "www.google.de", sub {
   print "ok 4 # www.google.de => @_\n";
   $cv->send;
};

$cv->recv;

print "ok 5\n";

