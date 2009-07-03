package AnyEvent::TLS;

no warnings;
use strict qw(subs vars);

use Carp qw(croak);
use Scalar::Util ();

use AnyEvent::Util ();

use Net::SSLeay 1.33;

=head1 NAME

AnyEvent::TLS - SSLv2/SSLv3/TLSv1 contexts for use in AnyEvent::Handle

=cut

our $VERSION = 4.45;

=head1 SYNOPSIS

   use AnyEvent;
   use AnyEvent::Handle;

=head1 DESCRIPTION

This module is a helper module that implements TLS (Transport Layer
Security/Secure Sockets Layer) contexts. A TLS context is a common set of
configuration values for use in etsablishing TLS connections.

A single TLS context can be used for any number of TLS connections that
wish to use the same certificates, policy etc.

Note that this module is inherently tied to L<Net::SSLeay>, as this
library is used to implement it. Since that perl module is rather ugly,
and openssl has a rather ugly license, AnyEvent might switch TLS providers
at some future point, at which this API will change dramatically, at least
in the Net::SSLeay-specific parts (most constructor arguments should still
work, though).

=head1 PUBLIC METHODS AND FUNCTIONS

=over 4

=cut

our $REF_IDX; # our session ex_data id

# create temp file, populate it, and returna  guard and filename
sub _tmpfile($) {
   require File::Temp;
   my ($fh, $path) = File::Temp::mkstemp ("aetlspemXXXXXX");
   my $guard = AnyEvent::Util::guard { unlink $path };

   syswrite $fh, $_[0];
   close $fh;

   ($path, $guard)
}

=item $tls = new AnyEvent::TLS key => value...

The constructor supports these arguments (all as key => value pairs).

=over 4

=item method => "SSLv2" | "SSLv3" | "TLSv1" | "any"

The protocol parser to use. C<SSLv2>, C<SSLv3> and C<TLSv1> will use
a parser for those protocols only (so will I<not> accept or create
connections with/to other protocol versions), while C<any> (the
default) uses a parser capable of all three protocols.

The default is to use C<"any"> but disable SSLv2. This has the effect of
sending a SSLv2 hello, indicating the support for SSLv3 and TLSv1, but not
actually negotiating an (insecure) SSLv2 connection.

Specifying a specific version is almost always wrong to use for a server,
and often wrong for a client. If you only want to allow a specific
protocol version, use the C<sslv2>, C<sslv3> or C<tlsv1> arguments
instead.

=item sslv2 => $enabled

Enable or disable SSLv2 (normally I<disabled>).

=item sslv3 => $enabled

Enable or disable SSLv3 (normally I<enabled>).

=item tlsv1 => $enabled

Enable or disable SSLv3 (normally I<enabled>).

=item verify => $enable

Enable or disable peer certificate checking (default is I<disabled>, which
is I<not recommended>).

This is the "master switch" for all verify-related parameters and
functions.

If it is disabled, then no peer certificate verification will be done
- the connection will be encrypted, but the peer certificate won't be
verified against any known CAs, or whether it is still valid or not. No
common name verification or custom verification will be done either.

If enabled, then the peer certificate (required in client mode, optional
in server mode, see C<verify_require_client_cert>) will be checked against
its CA certificate chain - that means there must be a signing chain from
the peer certificate to any of the CA certificates you trust locally, as
specified by the C<ca_file> and/or C<ca_cert> parameters (or the system
default CA repository, if those parameters are missing).

Other basic checks, such as checking the validity period, will also be
done, as well as optional common name verification C<verify_cn>.

An optional C<verify_cb> callback can also be set, which will be invoked
with the verification results, and which can override the decision.

=item verify_require_client_cert => $enable

Enable or disable mandatory client certificates (default is
I<disabled>). When this mode is enabled, then a client certificate will be
required in server mode (a server certificate is mandatory, so in client
mode, this switch has no effect).

=item verify_cb => $callback->($tls, $ref, $cn, $depth, $preverify_ok, $x509_store_ctx, $cert)

Provide a custom peer verification callback used by TLS sessions,
which is called with the result of any other verification (C<verify>,
C<verify_cn>).

This callback will only be called when verification is enabled (C<< verify
=> 1 >>).

C<$tls> is the C<AnyEvent::TLS> object associated with the session,
while C<$ref> is whatever the user associated with the session (usually
an L<AnyEvent::Handle> object when used by AnyEvent::Handle).

C<$depth> is the current verification depth - C<$depth = 0> means the
certificate to verify is the peer certificate, higher levels are its CA
certificate and so on. In most cases, you can just return C<$preverify_ok>
if the C<$depth> is non-zero:

   verify_cb => sub {
      my ($tls, $ref, $cn, $depth, $preverify_ok, $x509_store_ctx, $cert) = @_;

      return $preverify_ok
         if $depth;

      # more verification
   },

C<$preverify_ok> is true iff the basic verification of the certificates
was successful (a valid CA chain must exist, the certificate has passed
basic validity checks, common name verification succeeded).

C<$x509_store_ctx> is the Net::SSLeay::X509_CTX> object.

C<$cert> is the C<Net::SSLeay::X509> object representing the
peer certificate, or zero if there was an error. You can call
C<AnyEvent::TLS::certname $cert> to get a nice user-readable string to
identify the certificate.

The callback must return either C<0> to indicate failure, or C<1> to
indicate success.

=item verify_cn => $scheme | $callback->($tls, $cert, $local_cn)

TLS only protects the data that is sent - it cannot automatically verify
that you are really talking to the right peer. The reason is that
certificates contain a "common name" (and a set of possile alternative
"names") that needs to be checked against the peer name (usually, but not
always, the DNS name of the server) in a protocol-dependent way.

#TODO#

This verification will only be done when verification is enabled (C<<
verify => 1 >>).

=item verify_client_once => $enable

Enable or disable skipping the client certificate verification on
renegotiations (default is I<disabled>, the certificate will always be
checked). Only makes sense in server mode.

=item ca_file => $path

If this parameter is specified and non-empty, it will be the path to a
file with (server) CA certificates in PEM format that will be loaded. Each
certificate will look like:

   -----BEGIN CERTIFICATE-----
   ... (CA certificate in base64 encoding) ...
   -----END CERTIFICATE-----

You have to enable verify mode (C<< verify => 1 >>) for this parameter to
have any effect.

=item ca_path => $path

If this parameter is specified and non-empty, it will be the
path to a directory with hashed (server) CA certificate files
in PEM format. When the ca certificate is being verified, the
certificate will be hashed and looked up in that directory (see
L<http://www.openssl.org/docs/ssl/SSL_CTX_load_verify_locations.html> for
details)

The certificates specified via C<ca_file> take precedence over the ones
found in C<ca_path>.

You have to enable verify mode (C<< verify => 1 >>) for this parameter to
have any effect.

=item check_crl => $enable

Enable or disable certificate revocation list checking. If enabled, then
peer certificates will be checked against a list of revocked certificates
issued by the CA. The revocation lists will be expected in the C<ca_path>
directory.

This requires OpenSSL >= 0.9.7b. Check the OpenSSL documentation for more
details.

=item key_file => $path

Path to the local private key file in PEM format (might be a combined
certificate/private key file).

The local certificate is used to authenticate against the peer - servers
mandatorily need a certificate and key, clients can use certificate and
key optionally to authenticate, e.g. for log-in purposes.

The key in the file should look similar this:

   -----BEGIN RSA PRIVATE KEY-----
   ...header data
   ... (key data in base64 encoding) ...
   -----END RSA PRIVATE KEY-----

=item key => $string

The private key string in PEM format (see C<key_file>, only one of
C<key_file> or C<key> can be specified).

The idea behind being able to specify a string is to aovid blocking in
I/O. Unfortunately, Net::SSLeay fails to implement any interface to the
needed openssl functionality, this is currently implemented by writing to
a temporary file.

=item cert_file => $path

The path to the local certificate file in PEM format (might be a combined
certificate/private key file).

The local certificate (and key) are used to authenticate against the
peer - servers mandatorily need a certificate and key, clients can use
certificate and key optionally to authenticate, e.g. for log-in purposes.

The certificate in the file should look like this:

   -----BEGIN CERTIFICATE-----
   ... (certificate in base64 encoding) ...
   -----END CERTIFICATE-----

If the certificate file or string contain botht the certificate and
private key, then there is no need to specify a separate C<key_file> or
C<key>.

=item cert => $string

The local certificate in PEM format (might be a combined
certificate/private key file). See C<cert_file>.

The idea behind being able to specify a string is to aovid blocking in
I/O. Unfortunately, Net::SSLeay fails to implement any interface to the
needed openssl functionality, this is currently implemented by writing to
a temporary file.

=item cert_password => $string | $callback->($tls)

The certificate password - if the certificate is password-protected, then
you can specify its password here.

Instead of providing a password directly (which is not so recommended),
you can also provide a password-query callback. The callback will be
called whenever a password is required to decode a local certificate, and
is supposed to return the password.

=cut



# verify_depth?

# use_cert
# dh_file
# dh
# passwd_cb
# verifycn_scheme
# verifycn_name
# reuse_ctx
# session_cache_size
# session_cache

#=item debug => $level
#
#Enable or disable sending debugging output to STDERR. This is, as
#the name says, mostly for debugging. The default is taken from the
#C<PERL_ANYEVENT_TLS_DEBUG> environment variable.
#
#=cut

=item cipher_list => $string

The list of ciphers to use, as a string (example:
C<AES:ALL:!aNULL:!eNULL:+RC4:@STRENGTH>). The format
of this string and its default value is documented at
L<http://www.openssl.org/docs/apps/ciphers.html#CIPHER_STRINGS>.

=item prepare => $coderef->($tls)

If this argument is present, then it will be called with the new
AnyEvent::TLS object after any other initialisation has bee done, in acse
you wish to fine-tune something...

=back

=cut

sub init ();

sub new {
   my ($class, %arg) = @_;

   init unless $REF_IDX;

   my $method = lc $arg{method} || "any";

   my $ctx = $method eq "any"    ? Net::SSLeay::CTX_new       ()
           : $method eq "sslv23" ? Net::SSLeay::CTX_new       () # deliberately undocumented
           : $method eq "sslv2"  ? Net::SSLeay::CTX_v2_new    ()
           : $method eq "sslv3"  ? Net::SSLeay::CTX_v3_new    ()
           : $method eq "tlsv1"  ? Net::SSLeay::CTX_tlsv1_new ()
           : croak "'$method' is not a valid AnyEvent::TLS method (must be one of SSLv2, SSLv3, TLSv1 or any)";

   my $self = bless { ctx => $ctx }, $class; # to make sure it's destroyed if we croak

   Net::SSLeay::CTX_set_options ($ctx, Net::SSLeay::OP_ALL ());

   Net::SSLeay::CTX_set_cipher_list ($ctx, $arg{cipher_list})
      or croak "'$arg{cipher_list}' was not accepted as a valid cipher list by AnyEvent::TLS"
         if exists $arg{cipher_list};

   if ($arg{verify}) {
      $self->{verify_mode} = Net::SSLeay::VERIFY_PEER ();

      $self->{verify_mode} |= Net::SSLeay::VERIFY_FAIL_IF_NO_PEER_CERT ()
         if $arg{verify_require_client_cert};

      $self->{verify_mode} |= Net::SSLeay::VERIFY_CLIENT_ONCE ()
         if $arg{verify_client_once};

   } else {
      $self->{verify_mode} = Net::SSLeay::VERIFY_NONE ();
   }

   $self->{verify_cn} = $arg{verify_cn}
      if exists $arg{verify_cn};

   $self->{verify_cb} = $arg{verify_cb}
      if exists $arg{verify_cb};

   $self->{debug} = $ENV{PERL_ANYEVENT_TLS_DEBUG}
      if exists $ENV{PERL_ANYEVENT_TLS_DEBUG};

   $self->{debug} = $arg{debug}
      if exists $arg{debug};

   Net::SSLeay::CTX_set_options ($ctx, Net::SSLeay::OP_NO_SSLv2 ()) unless $arg{sslv2};
   Net::SSLeay::CTX_set_options ($ctx, Net::SSLeay::OP_NO_SSLv3 ()) if exists $arg{sslv3} && !$arg{sslv3};
   Net::SSLeay::CTX_set_options ($ctx, Net::SSLeay::OP_NO_TLSv1 ()) if exists $arg{tlsv1} && !$arg{tlsv1};

   my $pw = $arg{cert_password};
   Net::SSLeay::CTX_set_default_passwd_cb ($ctx, ref $pw ? $pw : sub { $pw });

   if ($self->{verify_mode}) {
      if (exists $arg{ca_file} or exists $arg{ca_cert} or exists $arg{ca_string}) {
         # either specified: use them
         if (exists $arg{ca_file} or exists $arg{ca_cert}) {
            Net::SSLeay::CTX_load_verify_locations ($ctx, $arg{ca_file}, $arg{ca_cert});
         }
         if (exists $arg{ca_string}) {
            # not yet implemented # TODO
         }
      } else {
         # else fall back to defaults
         Net::SSLeay::CTX_set_default_verify_paths ($ctx);
      }
   }

   if (exists $arg{cert} or exists $arg{cert_file}) {
      my ($g1, $g2);

      if (exists $arg{cert}) {
         croak "specifying both cert_file and cert is not allowed"
            if exists $arg{cert_file};

        ($arg{cert_file}, $g1) = _tmpfile delete $arg{cert};
      }

      if (exists $arg{key} or exists $arg{key_file}) {
         if (exists $arg{key}) {
            croak "specifying both key_file and key is not allowed"
               if exists $arg{cert_file};
           ($arg{key_file}, $g2) = _tmpfile delete $arg{key};
         }
      } else {
         $arg{key_file} = $arg{cert_file};
      }

      Net::SSLeay::CTX_use_PrivateKey_file
            ($ctx, $arg{key_file}, Net::SSLeay::FILETYPE_PEM ())
         or croak "$arg{key_file}: failed to load local private key (key_file or key)";

      Net::SSLeay::CTX_use_certificate_file
            ($ctx, $arg{cert_file}, Net::SSLeay::FILETYPE_PEM ())
         or croak "$arg{cert_file}: failed to use local certificate (cert_file or cert)";
   }

   if ($arg{check_crl}) {
      Net::SSLeay::OPENSSL_VERSION_NUMBER () >= 0x00090702f
         or croak "check_crl requires openssl v0.9.7b or higher";

      Net::SSLeay::X509_STORE_set_flags (
         Net::SSLeay::CTX_get_cert_store ($ctx),
         Net::SSLeay::X509_V_FLAG_CRL_CHECK ());
   }

   Net::SSLeay::CTX_set_read_ahead ($ctx, 1);

   $arg{prepare}->($self)
      if $arg{prepare};

   $self
}

=item $tls = new_from_ssleay AnyEvent::TLS $ctx

This constructor takes an existing L<Net::SSLeay> SSL_CTX object
(which is just an integer) and converts it into an C<AnyEvent::TLS>
object. This only works because AnyEvent::TLS is currently implemented
using Net::SSLeay. As this is such a horrible perl module and OpenSSL has
such an annoying license, this might change in the future, in which case
this method might vanish.

=cut

sub new_from_ssleay {
   my ($class, $ctx) = @_;

   bless { ctx => $ctx }, $class
}

=item $ctx = $tls->ctx

Returns the actual L<Net::SSLeay::CTX> object (just an integer).

=cut

sub ctx {
   $_[0]{ctx}
}

sub verify_cn($$$);

sub _verify_cn {
   my ($self, $cn, $cert) = @_;

   return 1
      unless exists $self->{verify_cn} && "none" ne lc $self->{verify_cn};

   return $self->{verify_cn}->($self, $cn, $cert)
      if ref $self->{verify_cn};

   verify_cn $cn, $cert, $self->{verify_cn}
}

sub verify {
   my ($self, $session, $ref, $cn, $preverify_ok, $x509_store_ctx) = @_;

   my $cert = $x509_store_ctx
      ? Net::SSLeay::X509_STORE_CTX_get_current_cert ($x509_store_ctx)
      : undef;
   my $depth = Net::SSLeay::X509_STORE_CTX_get_error_depth ($x509_store_ctx);

   $preverify_ok &&= $self->_verify_cn ($cn, $cert)
      unless $depth;

   $preverify_ok = $self->{verify_cb}->($self, $ref, $cn, $depth, $preverify_ok, $x509_store_ctx, $cert)
      if $self->{verify_cb};

   $preverify_ok
}

#=item $ssl = $tls->_get_session ($mode[, $ref])
#
#Creates a new Net::SSLeay::SSL session object, puts it into C<$mode>
#(C<accept> or C<connect>) and optionally associates it with the given
#C<$ref>. If C<$mode> is already a C<Net::SSLeay::SSL> object, then just
#associate data with it.
#
#=cut

#our %REF_MAP;

sub _get_session($$;$$) {
   my ($self, $mode, $ref, $cn) = @_;

   my $session;

   if ($mode eq "accept") {
      $session = Net::SSLeay::new ($self->{ctx});
      Net::SSLeay::set_accept_state ($session);
   } elsif ($mode eq "connect") {
      $session = Net::SSLeay::new ($self->{ctx});
      Net::SSLeay::set_connect_state ($session);
   }

#   # associate data
#   Net::SSLeay::set_ex_data ($session, $REF_IDX, $ref+0);
#   Scalar::Util::weaken ($REF_MAP{$ref+0} = $ref)
#      if ref $ref;
   
   if ($self->{debug}) {
      #d# Net::SSLeay::set_info_callback ($session, 50000);
   }

   if ($self->{verify_mode}) {
      Scalar::Util::weaken $self;
      Scalar::Util::weaken $ref;

      # we have to provide a dummy callbacks as at least Net::SSLeay <= 1.35
      # try to call it even if specified as 0 or undef.
      Net::SSLeay::set_verify
         $session,
         $self->{verify_mode},
         sub { $self->verify ($session, $ref, $cn, @_) };
   }

   $session
}

sub _put_session($$) {
   my ($self, $session) = @_;

   # clear callback, if any
   # this leaks memoryin Net::SSLeay up to at least 1.35, but there
   # apparently is no other way.
   Net::SSLeay::set_verify $session, 0, undef;

#   # disassociate data
#   delete $REF_MAP{Net::SSLeay::get_ex_data ($session, $REF_IDX)};

   Net::SSLeay::free ($session);
}

#sub _ref($) {
#   $REF_MAP{Net::SSLeay::get_ex_data ($_[0], $REF_IDX)}
#}

sub DESTROY {
   my ($self) = @_;

   # better be safe than sorry with net-ssleay
   Net::SSLeay::CTX_set_default_passwd_cb ($self->{ctx});

   Net::SSLeay::CTX_free ($self->{ctx});
}

=item AnyEvent::TLS::init

AnyEvent::TLS does on-demand initialisation, and normally there is no need to call an initialise
function.

As initialisation might take some time (to read e.g. C</dev/urandom>), this
could be annoying in some highly interactive programs. In that case, you can
call C<AnyEvent::TLS::init> to make sure there will be no costly initialisation
later. It is harmless to call C<AnyEvent::TLS::init> multiple times.

=cut

sub init() {
   return if $REF_IDX;

   Net::SSLeay::load_error_strings ();
   Net::SSLeay::SSLeay_add_ssl_algorithms ();
   Net::SSLeay::randomize ();

   $REF_IDX = Net::SSLeay::get_ex_new_index (0, 0, 0, 0, 0)
      until $REF_IDX; # Net::SSLeay uses id #0 for it's own stuff without allocating it
}

=item $certname = AnyEvent::TLS::certname $x509

Utility function that returns a user-readable string identifying the X509
certificate object.

=cut

sub certname {
   $_[0]
      ? Net::SSLeay::X509_NAME_oneline (Net::SSLeay::X509_get_issuer_name ($_[0]))
        . Net::SSLeay::X509_NAME_oneline (Net::SSLeay::X509_get_subject_name ($_[0]))
      : undef
}

our %CN_SCHEME = (
   # each tuple is [$cn_wildcards, $alt_wildcards, $check_cn]
   # where *_wildcards is 0 for none allowed, 1 for allowed at beginning and 2 for allowed everywhere
   # and check_cn is 0 for do not check, 1 for check when no alternate dns names and 2 always
   # all of this is from IO::Socket::SSL

   rfc4513 => [0, 1, 2],
   rfc2818 => [0, 2, 1],
   rfc3207 => [0, 0, 2], # see IO::Socket::SSL, rfc seems unclear
   none    => [],        # do not check

   ldap    => "rfc4513",                    ldaps => "ldap",
   http    => "rfc2818",                    https => "http",
   smtp    => "rfc3207",                    smtps => "smtp",

   xmpp    => "rfc3920", rfc3920 => "http",
   pop3    => "rfc2595", rfc2595 => "ldap", pop3s => "pop3",
   imap    => "rfc2595", rfc2595 => "ldap", imaps => "imap",
   acap    => "rfc2595", rfc2595 => "ldap",
   nntp    => "rfc4642", rfc4642 => "ldap", nntps => "nntp",
   ftp     => "rfc4217", rfc4217 => "http", ftps  => "ftp" ,
);

sub match_cn($$$) {
   my ($name, $cn, $type) = @_;

   # remove leading and trailing garbage
   for ($name, $cn) {
      s/[\x00-\x1f]+$//;
      s/^[\x00-\x1f]+//;
   }

   my $pattern;

   ### IMPORTANT!
   # we accept only a single wildcard and only for a single part of the FQDN
   # e.g *.example.org does match www.example.org but not bla.www.example.org
   # The RFCs are in this regard unspecific but we don't want to have to
   # deal with certificates like *.com, *.co.uk or even *
   # see also http://nils.toedtmann.net/pub/subjectAltName.txt
   if ($type == 2 and $name =~m{^([^.]*)\*(.+)} ) {
      $pattern = qr{^\Q$1\E[^.]*\Q$2\E$}i;
   } elsif ($type == 1 and $name =~m{^\*(\..+)$} ) {
      $pattern = qr{^[^.]*\Q$1\E$}i;
   } else {
      $pattern = qr{^\Q$name\E$}i;
   }

   $cn =~ $pattern
}

# taken verbatim from IO::Socket::SSL, then changed to take advantage of
# AnyEvent utilities.
sub verify_cn($$$) {
   my ($cn, $cert, $scheme) = @_;

   while (!ref $scheme) {
      $scheme = $CN_SCHEME{$scheme}
         or return 1;
   }

   my $cert_cn =
      Net::SSLeay::X509_NAME_get_text_by_NID (
         Net::SSLeay::X509_get_subject_name ($cert), Net::SSLeay::NID_commonName ());

   my @cert_alt = Net::SSLeay::X509_get_subjectAltNames ($cert);

   # rfc2460 - convert to network byte order
   my $ip = AnyEvent::Socket::parse_address $cn;

   my $alt_dns_count;

   while (my ($type, $name) = splice @cert_alt, 0, 2) {
      if ($type == Net::SSLeay::GEN_IPADD ()) {
         # $name is already packed format (inet_xton)
         return 1 if $ip eq $name;
      } elsif ($type == Net::SSLeay::GEN_DNS ()) {
         $alt_dns_count++;

         return 1 if match_cn $name, $cn, $scheme->[1];
      }
   }

   if ($scheme->[2] == 2
       || ($scheme->[2] == 1 && !$alt_dns_count)) {
      return 1 if match_cn $cert_cn, $cn, $scheme->[0];
   }

   0
}

=back

=head1 BUGS

To to the abysmal code quality of Net::SSLeay, this module will leak small
amounts of memory per TLS connection (currently at least one perl scalar).

=head1 AUTHORS

Marc Lehmann <schmorp@schmorp.de>.

Some of the API and implementation (verify_hostname) and a lot of
ideas/workarounds/knowledge has been taken from the L<IO::Socket::SSL>
module. Care has been taken to keep the API similar to that and other
modules, to the extent possible while providing a sensible API for
AnyEvent.

=cut

1

