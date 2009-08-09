# we avoid complicated tests here because some systems will
# not have working DNS

BEGIN { eval q{use AnyEvent::Impl::IOAsync;1} or ((print qq{1..0 # SKIP AnyEvent::Impl::IOAsync not loadable}), exit 0) } use IO::Async::Loop; AnyEvent::Impl::IOAsync::set_loop new IO::Async::Loop; $^W = 0;
use AnyEvent::DNS;

$| = 1; print "1..5\n";

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

