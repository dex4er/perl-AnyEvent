$| = 1;

print "1..20\n";

my $i = 0;
for (qw(
   AnyEvent
   AnyEvent::Util
   AnyEvent::DNS
   AnyEvent::Socket
   AnyEvent::Loop
   AnyEvent::Strict
   AnyEvent::Debug
   AnyEvent::Handle
   AnyEvent::Log
   AnyEvent::Impl::Perl
)) {
   print +(eval "require $_"  ) ? "" : "not ", "ok ", ++$i, " # $_ require $@\n";
   print +(eval "import $_; 1") ? "" : "not ", "ok ", ++$i, " # $_ import  $@\n";
}
