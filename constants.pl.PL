#! perl

open STDOUT, ">$ARGV[0]~"
   or die "$ARGV[0]~: $!";

sub i($$) {
   print "sub $_[0] () { ", $_[1]*1, " }\n";
}

print "package AnyEvent;\n";

our $WIN32 = $^O =~ /mswin32/i;


i CYGWIN => $^O =~ /cygwin/i;
i WIN32  => $WIN32;

use Fcntl ();

i F_SETFL    => eval { Fcntl::F_SETFL() };
i F_SETFD    => eval { Fcntl::F_SETFD() };
i O_NONBLOCK => eval { Fcntl::O_NONBLOCK() };
i FD_CLOEXEC => eval { Fcntl::FD_CLOEXEC() };

print "package AnyEvent::Util;\n";

# broken windows perls use undocumented error codes...
if ($WIN32) {
   i WSAEINVAL      => 10022;
   i WSAEWOULDBLOCK => 10035;
   i WSAEINPROGRESS => 10036;
} else {
   # these should never match any errno value
   i WSAEINVAL      => -1e99;
   i WSAEWOULDBLOCK => -1e99;
   i WSAEINPROGRESS => -1e99;
}

my $af_inet6;

$af_inet6 ||= eval { require Socket ; Socket::AF_INET6 () };
$af_ine6t ||= eval { require Socket6; Socket6::AF_INET6() };

# uhoh
$af_inet6 ||= 10 if $^O =~ /linux/;
$af_inet6 ||= 23 if $^O =~ /cygwin/i;
$af_inet6 ||= 23 if AnyEvent::WIN32;
$af_inet6 ||= 24 if $^O =~ /openbsd|netbsd/;
$af_inet6 ||= 28 if $^O =~ /freebsd/;

#TODO: WSAxxx, EDOM/ESPIPE

i _AF_INET6     => $af_inet6;
#i AF_UNIX      => Socket::AF_UNIX ();
#i SOCK_STREAM  => Socket::SOCK_STREAM ();
#i SOCK_DGRAM   => Socket::SOCK_DGRAM ();
#i SOL_SOCKET   => Socket::SOL_SOCKET ();
#i SO_REUSEADDR => Socket::SO_REUSEADDR ();
#i SO_KEEPALIVE => Socket::SO_KEEPALIVE ();
#i SO_OOBINLINE => Socket::SO_OOBINLINE ();
#i IPPROTO_TCP  => Socket::IPPROTO_TCP ();

print "1;\n";

close STDOUT;
rename "$ARGV[0]~", $ARGV[0];
