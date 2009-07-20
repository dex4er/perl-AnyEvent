use AnyEvent;
BEGIN { eval q{use AnyEvent::Impl::EV;1} or ((print qq{1..0 # SKIP AnyEvent::Impl::EV not loadable}), exit 0) } 

$| = 1; print "1..5\n";

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

