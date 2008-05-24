=head1 NAME

AnyEvent::DNS - fully asynchronous DNS resolution

=head1 SYNOPSIS

 use AnyEvent::DNS;

=head1 DESCRIPTION

This module offers both a number of DNS convenience functions as well
as a fully asynchronous and high-performance pure-perl stub resolver.

The stub resolver supports DNS over UDP, optional EDNS0 support for up to
4kiB datagrams and automatically falls back to virtual circuit mode for
large responses.

=head2 CONVENIENCE FUNCTIONS

=over 4

=cut

package AnyEvent::DNS;

no warnings;
use strict;

use AnyEvent::Handle ();

=item AnyEvent::DNS::addr $node, $service, $proto, $family, $type, $cb->([$family, $type, $proto, $sockaddr], ...)

Tries to resolve the given nodename and service name into protocol families
and sockaddr structures usable to connect to this node and service in a
protocol-independent way. It works remotely similar to the getaddrinfo
posix function.

C<$node> is either an IPv4 or IPv6 address or a hostname, C<$service> is
either a service name (port name from F</etc/services>) or a numerical
port number. If both C<$node> and C<$service> are names, then SRV records
will be consulted to find the real service, otherwise they will be
used as-is. If you know that the service name is not in your services
database, then you can specify the service in the format C<name=port>
(e.g. C<http=80>).

C<$proto> must be a protocol name, currently C<tcp>, C<udp> or
C<sctp>. The default is C<tcp>.

C<$family> must be either C<0> (meaning any protocol is OK), C<4> (use
only IPv4) or C<6> (use only IPv6). This setting might be influenced by
C<$ENV{PERL_ANYEVENT_PROTOCOLS}>.

C<$type> must be C<SOCK_STREAM>, C<SOCK_DGRAM> or C<SOCK_SEQPACKET> (or
C<undef> in which case it gets automatically chosen).

The callback will receive zero or more array references that contain
C<$family, $type, $proto> for use in C<socket> and a binary
C<$sockaddr> for use in C<connect> (or C<bind>).

The application should try these in the order given.

Example:

   AnyEvent::DNS::addr "google.com", "http", 0, undef, undef, sub { ... };

=item AnyEvent::DNS::a $domain, $cb->(@addrs)

Tries to resolve the given domain to IPv4 address(es).

=item AnyEvent::DNS::aaaa $domain, $cb->(@addrs)

Tries to resolve the given domain to IPv6 address(es).

=item AnyEvent::DNS::mx $domain, $cb->(@hostnames)

Tries to resolve the given domain into a sorted (lower preference value
first) list of domain names.

=item AnyEvent::DNS::ns $domain, $cb->(@hostnames)

Tries to resolve the given domain name into a list of name servers.

=item AnyEvent::DNS::txt $domain, $cb->(@hostnames)

Tries to resolve the given domain name into a list of text records.

=item AnyEvent::DNS::srv $service, $proto, $domain, $cb->(@srv_rr)

Tries to resolve the given service, protocol and domain name into a list
of service records.

Each srv_rr is an array reference with the following contents: 
C<[$priority, $weight, $transport, $target]>.

They will be sorted with lowest priority, highest weight first (TODO:
should use the RFC algorithm to reorder same-priority records for weight).

Example:

   AnyEvent::DNS::srv "sip", "udp", "schmorp.de", sub { ...
   # @_ = ( [10, 10, 5060, "sip1.schmorp.de" ] )

=item AnyEvent::DNS::ptr $ipv4_or_6, $cb->(@hostnames)

Tries to reverse-resolve the given IPv4 or IPv6 address (in textual form)
into it's hostname(s).

Example:

   AnyEvent::DNS::ptr "2001:500:2f::f", sub { print shift };
   # => f.root-servers.net

=item AnyEvent::DNS::any $domain, $cb->(@rrs)

Tries to resolve the given domain and passes all resource records found to
the callback.

=cut

sub resolver;

sub a($$) {
   my ($domain, $cb) = @_;

   resolver->resolve ($domain => "a", sub {
      $cb->(map $_->[3], @_);
   });
}

sub aaaa($$) {
   my ($domain, $cb) = @_;

   resolver->resolve ($domain => "aaaa", sub {
      $cb->(map $_->[3], @_);
   });
}

sub mx($$) {
   my ($domain, $cb) = @_;

   resolver->resolve ($domain => "mx", sub {
      $cb->(map $_->[4], sort { $a->[3] <=> $b->[3] } @_);
   });
}

sub ns($$) {
   my ($domain, $cb) = @_;

   resolver->resolve ($domain => "ns", sub {
      $cb->(map $_->[3], @_);
   });
}

sub txt($$) {
   my ($domain, $cb) = @_;

   resolver->resolve ($domain => "txt", sub {
      $cb->(map $_->[3], @_);
   });
}

sub srv($$$$) {
   my ($service, $proto, $domain, $cb) = @_;

   # todo, ask for any and check glue records
   resolver->resolve ("_$service._$proto.$domain" => "srv", sub {
      $cb->(map [@$_[3,4,5,6]], sort { $a->[3] <=> $b->[3] || $b->[4] <=> $a->[4] } @_);
   });
}

sub ptr($$) {
   my ($ip, $cb) = @_;

   $ip = AnyEvent::Socket::parse_ip ($ip)
      or return $cb->();

   if (4 == length $ip) {
      $ip = join ".", (reverse split /\./, $ip), "in-addr.arpa.";
   } else {
      $ip = join ".", (reverse split //, unpack "H*", $ip), "ip6.arpa.";
   }

   resolver->resolve ($ip => "ptr", sub {
      $cb->(map $_->[3], @_);
   });
}

sub any($$) {
   my ($domain, $cb) = @_;

   resolver->resolve ($domain => "*", $cb);
}

#############################################################################

sub addr($$$$$$) {
   my ($node, $service, $proto, $family, $type, $cb) = @_;

   unless (&AnyEvent::Socket::AF_INET6) {
      $family != 6
         or return $cb->();

      $family ||= 4;
   }

   $cb->() if $family == 4 && !$AnyEvent::PROTOCOL{ipv4};
   $cb->() if $family == 6 && !$AnyEvent::PROTOCOL{ipv6};

   $family ||=4 unless $AnyEvent::PROTOCOL{ipv6};
   $family ||=6 unless $AnyEvent::PROTOCOL{ipv4};

   $proto ||= "tcp";
   $type  ||= $proto eq "udp" ? Socket::SOCK_DGRAM : Socket::SOCK_STREAM;

   my $proton = (getprotobyname $proto)[2]
      or Carp::croak "$proto: protocol unknown";

   my $port;

   if ($service =~ /^(\S+)=(\d+)$/) {
      ($service, $port) = ($1, $2);
   } elsif ($service =~ /^\d+$/) {
      ($service, $port) = (undef, $service);
   } else {
      $port = (getservbyname $service, $proto)[2]
            or Carp::croak "$service/$proto: service unknown";
   }

   my @target = [$node, $port];

   # resolve a records / provide sockaddr structures
   my $resolve = sub {
      my @res;
      my $cv = AnyEvent->condvar (cb => sub {
         $cb->(
            map $_->[1],
            sort {
               $AnyEvent::PROTOCOL{$a->[1][0]} <=> $AnyEvent::PROTOCOL{$b->[1][0]}
                  or $a->[0] <=> $b->[0]
            }
            @res
         )
      });

      $cv->begin;
      for my $idx (0 .. $#target) {
         my ($node, $port) = @{ $target[$idx] };

         if (my $noden = AnyEvent::Socket::parse_ip ($node)) {
            if (4 == length $noden && $family != 6) {
               push @res, [$idx, [Socket::AF_INET, $type, $proton,
                           AnyEvent::Socket::pack_sockaddr ($port, $noden)]]
            }

            if (16 == length $noden && $family != 4) {
               push @res, [$idx, [&AnyEvent::Socket::AF_INET6, $type, $proton,
                           AnyEvent::Socket::pack_sockaddr ( $port, $noden)]]
            }
         } else {
            # ipv4
            if ($family != 6) {
               $cv->begin;
               a $node, sub {
                  push @res, [$idx, [Socket::AF_INET, $type, $proton,
                              AnyEvent::Socket::pack_sockaddr ($port, AnyEvent::Socket::parse_ipv4 ($_))]]
                     for @_;
                  $cv->end;
               };
            }

            # ipv6
            if ($family != 4) {
               $cv->begin;
               aaaa $node, sub {
                  push @res, [$idx, [&AnyEvent::Socket::AF_INET6, $type, $proton,
                              AnyEvent::Socket::pack_sockaddr ($port, AnyEvent::Socket::parse_ipv6 ($_))]]
                     for @_;
                  $cv->end;
               };
            }
         }
      }
      $cv->end;
   };

   # try srv records, if applicable
   if ($node eq "localhost") {
      @target = (["127.0.0.1", $port], ["::1", $port]);
      &$resolve;
   } elsif (defined $service && !AnyEvent::Socket::parse_ip ($node)) {
      srv $service, $proto, $node, sub {
         my (@srv) = @_;

         # no srv records, continue traditionally
         @srv
            or return &$resolve;

         # only srv record has "." => abort
         $srv[0][2] ne "." || $#srv
            or return $cb->();

         # use srv records then
         @target = map ["$_->[3].", $_->[2]],
                      grep $_->[3] ne ".",
                         @srv;

         &$resolve;
      };
   } else {
      &$resolve;
   }
}

#############################################################################

=back

=head2 LOW-LEVEL DNS EN-/DECODING FUNCTIONS

=over 4

=item $AnyEvent::DNS::EDNS0

This variable decides whether dns_pack automatically enables EDNS0
support. By default, this is disabled (C<0>), unless overridden by
C<$ENV{PERL_ANYEVENT_EDNS0>), but when set to C<1>, AnyEvent::DNS will use
EDNS0 in all requests.

=cut

our $EDNS0 = $ENV{PERL_ANYEVENT_EDNS0} * 1; # set to 1 to enable (partial) edns0

our %opcode_id = (
   query  => 0,
   iquery => 1,
   status => 2,
   notify => 4,
   update => 5,
   map +($_ => $_), 3, 6..15
);

our %opcode_str = reverse %opcode_id;

our %rcode_id = (
   noerror  =>  0,
   formerr  =>  1,
   servfail =>  2,
   nxdomain =>  3,
   notimp   =>  4,
   refused  =>  5,
   yxdomain =>  6, # Name Exists when it should not     [RFC 2136]
   yxrrset  =>  7, # RR Set Exists when it should not   [RFC 2136]
   nxrrset  =>  8, # RR Set that should exist does not  [RFC 2136]
   notauth  =>  9, # Server Not Authoritative for zone  [RFC 2136]
   notzone  => 10, # Name not contained in zone         [RFC 2136]
# EDNS0  16    BADVERS   Bad OPT Version                    [RFC 2671]
# EDNS0  16    BADSIG    TSIG Signature Failure             [RFC 2845]
# EDNS0  17    BADKEY    Key not recognized                 [RFC 2845]
# EDNS0  18    BADTIME   Signature out of time window       [RFC 2845]
# EDNS0  19    BADMODE   Bad TKEY Mode                      [RFC 2930]
# EDNS0  20    BADNAME   Duplicate key name                 [RFC 2930]
# EDNS0  21    BADALG    Algorithm not supported            [RFC 2930]
   map +($_ => $_), 11..15
);

our %rcode_str = reverse %rcode_id;

our %type_id = (
   a     =>   1,
   ns    =>   2,
   md    =>   3,
   mf    =>   4,
   cname =>   5,
   soa   =>   6,
   mb    =>   7,
   mg    =>   8,
   mr    =>   9,
   null  =>  10,
   wks   =>  11,
   ptr   =>  12,
   hinfo =>  13,
   minfo =>  14,
   mx    =>  15,
   txt   =>  16,
   aaaa  =>  28,
   srv   =>  33,
   opt   =>  41,
   spf   =>  99,
   tkey  => 249,
   tsig  => 250,
   ixfr  => 251,
   axfr  => 252,
   mailb => 253,
   "*"   => 255,
);

our %type_str = reverse %type_id;

our %class_id = (
   in   =>   1,
   ch   =>   3,
   hs   =>   4,
   none => 254,
   "*"  => 255,
);

our %class_str = reverse %class_id;

# names MUST have a trailing dot
sub _enc_qname($) {
   pack "(C/a)*", (split /\./, shift), ""
}

sub _enc_qd() {
   (_enc_qname $_->[0]) . pack "nn",
     ($_->[1] > 0 ? $_->[1] : $type_id {$_->[1]}),
     ($_->[2] > 0 ? $_->[2] : $class_id{$_->[2] || "in"})
}

sub _enc_rr() {
   die "encoding of resource records is not supported";
}

=item $pkt = AnyEvent::DNS::dns_pack $dns

Packs a perl data structure into a DNS packet. Reading RFC1034 is strongly
recommended, then everything will be totally clear. Or maybe not.

Resource records are not yet encodable.

Examples:

  # very simple request, using lots of default values:
  { rd => 1, qd => [ [ "host.domain", "a"] ] }

  # more complex example, showing how flags etc. are named:

  {
     id => 10000,
     op => "query",
     rc => "nxdomain",

     # flags
     qr => 1,
     aa => 0,
     tc => 0,
     rd => 0,
     ra => 0,
     ad => 0,
     cd => 0,

     qd => [@rr], # query section
     an => [@rr], # answer section
     ns => [@rr], # authority section
     ar => [@rr], # additional records section
  }

=cut

sub dns_pack($) {
   my ($req) = @_;

   pack "nn nnnn a* a* a* a* a*",
      $req->{id},

      ! !$req->{qr}   * 0x8000
      + $opcode_id{$req->{op}} * 0x0800
      + ! !$req->{aa} * 0x0400
      + ! !$req->{tc} * 0x0200
      + ! !$req->{rd} * 0x0100
      + ! !$req->{ra} * 0x0080
      + ! !$req->{ad} * 0x0020
      + ! !$req->{cd} * 0x0010
      + $rcode_id{$req->{rc}} * 0x0001,

      scalar @{ $req->{qd} || [] },
      scalar @{ $req->{an} || [] },
      scalar @{ $req->{ns} || [] },
      $EDNS0 + scalar @{ $req->{ar} || [] }, # include EDNS0 option here

      (join "", map _enc_qd, @{ $req->{qd} || [] }),
      (join "", map _enc_rr, @{ $req->{an} || [] }),
      (join "", map _enc_rr, @{ $req->{ns} || [] }),
      (join "", map _enc_rr, @{ $req->{ar} || [] }),

      ($EDNS0 ? pack "C nnNn", 0, 41, 4096, 0, 0 : "") # EDNS0, 4kiB udp payload size
}

our $ofs;
our $pkt;

# bitches
sub _dec_qname {
   my @res;
   my $redir;
   my $ptr = $ofs;
   my $cnt;

   while () {
      return undef if ++$cnt >= 256; # to avoid DoS attacks

      my $len = ord substr $pkt, $ptr++, 1;

      if ($len & 0xc0) {
         $ptr++;
         $ofs = $ptr if $ptr > $ofs;
         $ptr = (unpack "n", substr $pkt, $ptr - 2, 2) & 0x3fff;
      } elsif ($len) {
         push @res, substr $pkt, $ptr, $len;
         $ptr += $len;
      } else {
         $ofs = $ptr if $ptr > $ofs;
         return join ".", @res;
      }
   }
}

sub _dec_qd {
   my $qname = _dec_qname;
   my ($qt, $qc) = unpack "nn", substr $pkt, $ofs; $ofs += 4;
   [$qname, $type_str{$qt} || $qt, $class_str{$qc} || $qc]
}

our %dec_rr = (
     1 => sub { join ".", unpack "C4" }, # a
     2 => sub { local $ofs = $ofs - length; _dec_qname }, # ns
     5 => sub { local $ofs = $ofs - length; _dec_qname }, # cname
     6 => sub { 
             local $ofs = $ofs - length;
             my $mname = _dec_qname;
             my $rname = _dec_qname;
             ($mname, $rname, unpack "NNNNN", substr $pkt, $ofs)
          }, # soa
    11 => sub { ((join ".", unpack "C4"), unpack "C a*", substr $_, 4) }, # wks
    12 => sub { local $ofs = $ofs - length; _dec_qname }, # ptr
    13 => sub { unpack "C/a C/a", $_ }, # hinfo
    15 => sub { local $ofs = $ofs + 2 - length; ((unpack "n", $_), _dec_qname) }, # mx
    16 => sub { unpack "(C/a)*", $_ }, # txt
    28 => sub { AnyEvent::Socket::format_ip ($_) }, # aaaa
    33 => sub { local $ofs = $ofs + 6 - length; ((unpack "nnn", $_), _dec_qname) }, # srv
    99 => sub { unpack "(C/a)*", $_ }, # spf
);

sub _dec_rr {
   my $qname = _dec_qname;

   my ($rt, $rc, $ttl, $rdlen) = unpack "nn N n", substr $pkt, $ofs; $ofs += 10;
   local $_ = substr $pkt, $ofs, $rdlen; $ofs += $rdlen;

   [
      $qname,
      $type_str{$rt}  || $rt,
      $class_str{$rc} || $rc,
      ($dec_rr{$rt} || sub { $_ })->(),
   ]
}

=item $dns = AnyEvent::DNS::dns_unpack $pkt

Unpacks a DNS packet into a perl data structure.

Examples:

  # an unsuccessful reply
  {
    'qd' => [
              [ 'ruth.plan9.de.mach.uni-karlsruhe.de', '*', 'in' ]
            ],
    'rc' => 'nxdomain',
    'ar' => [],
    'ns' => [
              [
                'uni-karlsruhe.de',
                'soa',
                'in',
                'netserv.rz.uni-karlsruhe.de',
                'hostmaster.rz.uni-karlsruhe.de',
                2008052201, 10800, 1800, 2592000, 86400
              ]
            ],
    'tc' => '',
    'ra' => 1,
    'qr' => 1,
    'id' => 45915,
    'aa' => '',
    'an' => [],
    'rd' => 1,
    'op' => 'query'
  }

  # a successful reply

  {
    'qd' => [ [ 'www.google.de', 'a', 'in' ] ],
    'rc' => 0,
    'ar' => [
              [ 'a.l.google.com', 'a', 'in', '209.85.139.9' ],
              [ 'b.l.google.com', 'a', 'in', '64.233.179.9' ],
              [ 'c.l.google.com', 'a', 'in', '64.233.161.9' ],
            ],
    'ns' => [
              [ 'l.google.com', 'ns', 'in', 'a.l.google.com' ],
              [ 'l.google.com', 'ns', 'in', 'b.l.google.com' ],
            ],
    'tc' => '',
    'ra' => 1,
    'qr' => 1,
    'id' => 64265,
    'aa' => '',
    'an' => [
              [ 'www.google.de', 'cname', 'in', 'www.google.com' ],
              [ 'www.google.com', 'cname', 'in', 'www.l.google.com' ],
              [ 'www.l.google.com', 'a', 'in', '66.249.93.104' ],
              [ 'www.l.google.com', 'a', 'in', '66.249.93.147' ],
            ],
    'rd' => 1,
    'op' => 0
  }

=cut

sub dns_unpack($) {
   local $pkt = shift;
   my ($id, $flags, $qd, $an, $ns, $ar)
      = unpack "nn nnnn A*", $pkt;

   local $ofs = 6 * 2;

   {
      id => $id,
      qr => ! ! ($flags & 0x8000),
      aa => ! ! ($flags & 0x0400),
      tc => ! ! ($flags & 0x0200),
      rd => ! ! ($flags & 0x0100),
      ra => ! ! ($flags & 0x0080),
      ad => ! ! ($flags & 0x0020),
      cd => ! ! ($flags & 0x0010),
      op => $opcode_str{($flags & 0x001e) >> 11},
      rc => $rcode_str{($flags & 0x000f)},

      qd => [map _dec_qd, 1 .. $qd],
      an => [map _dec_rr, 1 .. $an],
      ns => [map _dec_rr, 1 .. $ns],
      ar => [map _dec_rr, 1 .. $ar],
   }
}

#############################################################################

=back

=head2 THE AnyEvent::DNS RESOLVER CLASS

This is the class which does the actual protocol work.

=over 4

=cut

use Carp ();
use Scalar::Util ();
use Socket ();

our $NOW;

=item AnyEvent::DNS::resolver

This function creates and returns a resolver that is ready to use and
should mimic the default resolver for your system as good as possible.

It only ever creates one resolver and returns this one on subsequent
calls.

Unless you have special needs, prefer this function over creating your own
resolver object.

=cut

our $RESOLVER;

sub resolver() {
   $RESOLVER || do {
      $RESOLVER = new AnyEvent::DNS;
      $RESOLVER->os_config;
      $RESOLVER
   }
}

=item $resolver = new AnyEvent::DNS key => value...

Creates and returns a new resolver.

The following options are supported:

=over 4

=item server => [...]

A list of server addresses (default: C<v127.0.0.1>) in network format (4
octets for IPv4, 16 octets for IPv6 - not yet supported).

=item timeout => [...]

A list of timeouts to use (also determines the number of retries). To make
three retries with individual time-outs of 2, 5 and 5 seconds, use C<[2,
5, 5]>, which is also the default.

=item search => [...]

The default search list of suffixes to append to a domain name (default: none).

=item ndots => $integer

The number of dots (default: C<1>) that a name must have so that the resolver
tries to resolve the name without any suffixes first.

=item max_outstanding => $integer

Most name servers do not handle many parallel requests very well. This option
limits the number of outstanding requests to C<$n> (default: C<10>), that means
if you request more than this many requests, then the additional requests will be queued
until some other requests have been resolved.

=item reuse => $seconds

The number of seconds (default: C<300>) that a query id cannot be re-used
after a timeout. If there as no time-out then query id's can be reused
immediately.

=back

=cut

sub new {
   my ($class, %arg) = @_;

   socket my $fh, &Socket::AF_INET, &Socket::SOCK_DGRAM, 0
      or Carp::croak "socket: $!";

   AnyEvent::Util::fh_nonblocking $fh, 1;

   my $self = bless {
      server  => [v127.0.0.1],
      timeout => [2, 5, 5],
      search  => [],
      ndots   => 1,
      max_outstanding => 10,
      reuse   => 300, # reuse id's after 5 minutes only, if possible
      %arg,
      fh      => $fh,
      reuse_q => [],
   }, $class;

   # search should default to gethostname's domain
   # but perl lacks a good posix module

   Scalar::Util::weaken (my $wself = $self);
   $self->{rw} = AnyEvent->io (fh => $fh, poll => "r", cb => sub { $wself->_recv });

   $self->_compile;

   $self
}

=item $resolver->parse_resolv_conv ($string)

Parses the given string as if it were a F<resolv.conf> file. The following
directives are supported (but not necessarily implemented).

C<#>-style comments, C<nameserver>, C<domain>, C<search>, C<sortlist>,
C<options> (C<timeout>, C<attempts>, C<ndots>).

Everything else is silently ignored.

=cut

sub parse_resolv_conf {
   my ($self, $resolvconf) = @_;

   $self->{server} = [];
   $self->{search} = [];

   my $attempts;

   for (split /\n/, $resolvconf) {
      if (/^\s*#/) {
         # comment
      } elsif (/^\s*nameserver\s+(\S+)\s*$/i) {
         my $ip = $1;
         if (AnyEvent::Util::dotted_quad $ip) {
            push @{ $self->{server} }, AnyEvent::Util::socket_inet_aton $ip;
         } else {
            warn "nameserver $ip invalid and ignored\n";
         }
      } elsif (/^\s*domain\s+(\S*)\s+$/i) {
         $self->{search} = [$1];
      } elsif (/^\s*search\s+(.*?)\s*$/i) {
         $self->{search} = [split /\s+/, $1];
      } elsif (/^\s*sortlist\s+(.*?)\s*$/i) {
         # ignored, NYI
      } elsif (/^\s*options\s+(.*?)\s*$/i) {
         for (split /\s+/, $1) {
            if (/^timeout:(\d+)$/) {
               $self->{timeout} = [$1];
            } elsif (/^attempts:(\d+)$/) {
               $attempts = $1;
            } elsif (/^ndots:(\d+)$/) {
               $self->{ndots} = $1;
            } else {
               # debug, rotate, no-check-names, inet6
            }
         }
      }
   }

   $self->{timeout} = [($self->{timeout}[0]) x $attempts]
      if $attempts;

   $self->_compile;
}

=item $resolver->os_config

Tries so load and parse F</etc/resolv.conf> on portable operating systems. Tries various
egregious hacks on windows to force the DNS servers and searchlist out of the system.

=cut

sub os_config {
   my ($self) = @_;

   if ($^O =~ /mswin32|cygwin/i) {
      # yeah, it suxx... lets hope DNS is DNS in all locales

      if (open my $fh, "ipconfig /all |") {
         delete $self->{server};
         delete $self->{search};

         while (<$fh>) {
            # first DNS.* is suffix list
            if (/^\s*DNS/) {
               while (/\s+([[:alnum:].\-]+)\s*$/) {
                  push @{ $self->{search} }, $1;
                  $_ = <$fh>;
               }
               last;
            }
         }

         while (<$fh>) {
            # second DNS.* is server address list
            if (/^\s*DNS/) {
               while (/\s+(\d+\.\d+\.\d+\.\d+)\s*$/) {
                  my $ip = $1;
                  push @{ $self->{server} }, AnyEvent::Util::socket_inet_aton $ip
                     if AnyEvent::Util::dotted_quad $ip;
                  $_ = <$fh>;
               }
               last;
            }
         }

         $self->_compile;
      }
   } else {
      # try resolv.conf everywhere

      if (open my $fh, "</etc/resolv.conf") {
         local $/;
         $self->parse_resolv_conf (<$fh>);
      }
   }
}

sub _compile {
   my $self = shift;

   my @retry;

   for my $timeout (@{ $self->{timeout} }) {
      for my $server (@{ $self->{server} }) {
         push @retry, [$server, $timeout];
      }
   }

   $self->{retry} = \@retry;
}

sub _feed {
   my ($self, $res) = @_;

   $res = dns_unpack $res
      or return;

   my $id = $self->{id}{$res->{id}};

   return unless ref $id;

   $NOW = time;
   $id->[1]->($res);
}

sub _recv {
   my ($self) = @_;

   while (my $peer = recv $self->{fh}, my $res, 4096, 0) {
      my ($port, $host) = AnyEvent::Socket::unpack_sockaddr ($peer);

      return unless $port == 53 && grep $_ eq $host, @{ $self->{server} };

      $self->_feed ($res);
   }
}

sub _free_id {
   my ($self, $id, $timeout) = @_;

   if ($timeout) {
      # we need to block the id for a while
      $self->{id}{$id} = 1;
      push @{ $self->{reuse_q} }, [$NOW + $self->{reuse}, $id];
   } else {
      # we can quickly recycle the id
      delete $self->{id}{$id};
   }

   --$self->{outstanding};
   $self->_scheduler;
}

# execute a single request, involves sending it with timeouts to multiple servers
sub _exec {
   my ($self, $req) = @_;

   my $retry; # of retries
   my $do_retry;

   $do_retry = sub {
      my $retry_cfg = $self->{retry}[$retry++]
         or do {
            # failure
            $self->_free_id ($req->[2], $retry > 1);
            undef $do_retry; return $req->[1]->();
         };

      my ($server, $timeout) = @$retry_cfg;
      
      $self->{id}{$req->[2]} = [AnyEvent->timer (after => $timeout, cb => sub {
         $NOW = time;

         # timeout, try next
         &$do_retry;
      }), sub {
         my ($res) = @_;

         if ($res->{tc}) {
            # success, but truncated, so use tcp
            AnyEvent::Socket::tcp_connect ((Socket::inet_ntoa $server), 53, sub {
               my ($fh) = @_
                  or return &$do_retry;

               my $handle = new AnyEvent::Handle
                  fh       => $fh,
                  on_error => sub {
                     # failure, try next
                     &$do_retry;
                  };

               $handle->push_write (pack "n/a", $req->[0]);
               $handle->push_read_chunk (2, sub {
                  $handle->unshift_read_chunk ((unpack "n", $_[1]), sub {
                     $self->_feed ($_[1]);
                  });
               });
               shutdown $fh, 1;

            }, sub { $timeout });

         } else {
            # success
            $self->_free_id ($req->[2], $retry > 1);
            undef $do_retry; return $req->[1]->($res);
         }
      }];

      send $self->{fh}, $req->[0], 0, AnyEvent::Socket::pack_sockaddr (53, $server);
   };

   &$do_retry;
}

sub _scheduler {
   my ($self) = @_;

   $NOW = time;

   # first clear id reuse queue
   delete $self->{id}{ (shift @{ $self->{reuse_q} })->[1] }
      while @{ $self->{reuse_q} } && $self->{reuse_q}[0][0] <= $NOW;

   while ($self->{outstanding} < $self->{max_outstanding}) {

      if (@{ $self->{reuse_q} } >= 30000) {
         # we ran out of ID's, wait a bit
         $self->{reuse_to} ||= AnyEvent->timer (after => $self->{reuse_q}[0][0] - $NOW, cb => sub {
            delete $self->{reuse_to};
            $self->_scheduler;
         });
         last;
      }

      my $req = shift @{ $self->{queue} }
         or last;

      while () {
         $req->[2] = int rand 65536;
         last unless exists $self->{id}{$req->[2]};
      }

      ++$self->{outstanding};
      $self->{id}{$req->[2]} = 1;
      substr $req->[0], 0, 2, pack "n", $req->[2];

      $self->_exec ($req);
   }
}

=item $resolver->request ($req, $cb->($res))

Sends a single request (a hash-ref formated as specified for
C<dns_pack>) to the configured nameservers including
retries. Calls the callback with the decoded response packet if a reply
was received, or no arguments on timeout.

=cut

sub request($$) {
   my ($self, $req, $cb) = @_;

   push @{ $self->{queue} }, [dns_pack $req, $cb];
   $self->_scheduler;
}

=item $resolver->resolve ($qname, $qtype, %options, $cb->($rcode, @rr))

Queries the DNS for the given domain name C<$qname> of type C<$qtype> (a
qtype of "*" is supported and means "any").

The callback will be invoked with a list of matching result records or
none on any error or if the name could not be found.

CNAME chains (although illegal) are followed up to a length of 8.

Note that this resolver is just a stub resolver: it requires a name server
supporting recursive queries, will not do any recursive queries itself and
is not secure when used against an untrusted name server.

The following options are supported:

=over 4

=item search => [$suffix...]

Use the given search list (which might be empty), by appending each one
in turn to the C<$qname>. If this option is missing then the configured
C<ndots> and C<search> define its value. If the C<$qname> ends in a dot,
then the searchlist will be ignored.

=item accept => [$type...]

Lists the acceptable result types: only result types in this set will be
accepted and returned. The default includes the C<$qtype> and nothing
else.

=item class => "class"

Specify the query class ("in" for internet, "ch" for chaosnet and "hs" for
hesiod are the only ones making sense). The default is "in", of course.

=back

Examples:

   $res->resolve ("ruth.plan9.de", "a", sub {
      warn Dumper [@_];
   });

   [
     [
       'ruth.schmorp.de',
       'a',
       'in',
       '129.13.162.95'
     ]
   ]

   $res->resolve ("test1.laendle", "*",
      accept => ["a", "aaaa"],
      sub {
         warn Dumper [@_];
      }
   );

   [
     [
       'test1.laendle',
       'a',
       'in',
       '10.0.0.255'
     ],
     [
       'test1.laendle',
       'aaaa',
       'in',
       '3ffe:1900:4545:0002:0240:0000:0000:f7e1'
     ]
   ]

=cut

sub resolve($%) {
   my $cb = pop;
   my ($self, $qname, $qtype, %opt) = @_;

   my @search = $qname =~ s/\.$//
      ? ""
      : $opt{search}
        ? @{ $opt{search} }
        : ($qname =~ y/.//) >= $self->{ndots}
          ? ("", @{ $self->{search} })
          : (@{ $self->{search} }, "");

   my $class = $opt{class} || "in";

   my %atype = $opt{accept}
      ? map +($_ => 1), @{ $opt{accept} }
      : ($qtype => 1);

   # advance in searchlist
   my ($do_search, $do_req);
   
   $do_search = sub {
      @search
         or (undef $do_search), (undef $do_req), return $cb->();

      (my $name = lc "$qname." . shift @search) =~ s/\.$//;
      my $depth = 2;

      # advance in cname-chain
      $do_req = sub {
         $self->request ({
            rd => 1,
            qd => [[$name, $qtype, $class]],
         }, sub {
            my ($res) = @_
               or return $do_search->();

            my $cname;

            while () {
               # results found?
               my @rr = grep $name eq lc $_->[0] && ($atype{"*"} || $atype{$_->[1]}), @{ $res->{an} };

               (undef $do_search), (undef $do_req), return $cb->(@rr)
                  if @rr;

               # see if there is a cname we can follow
               my @rr = grep $name eq lc $_->[0] && $_->[1] eq "cname", @{ $res->{an} };

               if (@rr) {
                  $depth--
                     or return $do_search->(); # cname chain too long

                  $cname = 1;
                  $name = $rr[0][3];

               } elsif ($cname) {
                  # follow the cname
                  return $do_req->();

               } else {
                  # no, not found anything
                  return $do_search->();
               }
             }
         });
      };

      $do_req->();
   };

   $do_search->();
}

use AnyEvent::Socket (); # circular dependency, so do not import anything and do it at the end

1;

=back

=head1 AUTHOR

 Marc Lehmann <schmorp@schmorp.de>
 http://home.schmorp.de/

=cut

