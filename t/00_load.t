$|=1;
BEGIN { print "1..5\n" }

require AnyEvent; print "ok 1\n";
require AnyEvent::Impl::Perl; print "ok 2\n";
require AnyEvent::Util; print "ok 3\n";
require AnyEvent::Handle; print "ok 4\n";
require AnyEvent::DNS; print "ok 5\n";



