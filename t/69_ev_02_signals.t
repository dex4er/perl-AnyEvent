$|=1;
BEGIN { unless (eval "require EV") { print "1..0 # skip because EV isn't installed"; exit } }
BEGIN {
   print "1..5\n";
}

use AnyEvent;
use AnyEvent::Impl::EV;

print "ok 1\n";

my $cv = AnyEvent->condvar;

my $error = AnyEvent->timer (after => 5, cb => sub {
   print <<EOF;
Bail out! No signal caught.
EOF
   exit 0;
});

my $sw = AnyEvent->signal (signal => 'INT', cb => sub {
  print "ok 3\n";
  $cv->broadcast;
});

print "ok 2\n";
kill 'INT', $$;
$cv->wait;
undef $error;

print "ok 4\n";

undef $sw;

print "ok 5\n";
