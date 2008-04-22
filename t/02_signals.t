$|=1;
BEGIN {
   print "1..5\n";
}

use AnyEvent;
use AnyEvent::Impl::Perl;

print STDERR <<EOF;

If the following test hangs for a long time or terminates with a signal
you either found a bug in AnyEvent or, more likely, you have a defective
perl (most windows perl distros are broken, cygwin perl works). If you do
not rely on signal handlers you can force the installation of this module
and the rest will likely work. Otherwise upgrading to a working perl is
recommended.
EOF

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

