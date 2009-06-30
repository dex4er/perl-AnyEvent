package AnyEvent::TLS;

no warnings;
use strict qw(subs vars);

use Carp qw(croak);

use Scalar::Util ();

use Net::SSLeay 1.30;

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

our %CN_SCHEME = (
   # each tuple is [$cn_wildcards, $alt_wildcards, $check_cn]
   # where *_wildcards is 0 for none allowed, 1 for allowed at beginning and 2 for allowed everywhere
   # and check_cn is 0 for do not check, 1 for check when no alternate names and 2 always
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

# lots of aliase


our $REF_IDX; # our session ex_data id
our %VERIFY_MODE;

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

   %VERIFY_MODE = (
      none                 => Net::SSLeay::VERIFY_NONE (),
      peer                 => Net::SSLeay::VERIFY_PEER (),
      fail_if_no_peer_cert => Net::SSLeay::VERIFY_FAIL_IF_NO_PEER_CERT (),
      verify_client_once   => Net::SSLeay::VERIFY_CLIENT_ONCE (),
   );
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

=item verify_mode => $modes

Set the verification mode to use on peer certificates, as a
comma-separated list of mode strings. The default of C<none> does not
attempt any kind of verification.

The only other mode, C<peer> can be combined with one or two other
modes that are only used for server mode: C<fail_if_no_peer_cert> (fail
verification if no peer certificate exists) and C<verify_client_once> (do
not verify the client certificate on each renegotiation).

See also C<ca_file>, C<ca_cert> and C<verify_cb> parameters to see how
verification is done.

If neither C<ca_file> nor C<ca_cert> are provided and the verification
mode is not C<none>, then a compiled-in default ca file and
directory will be used.

Example: do peer certificate verification, and on servers, also fail
if the client certificate cannot be verified:

   verify_mode => "peer,fail_if_no_peer_cert",

=item verify_cb => $callback->($tls, $ref, $preverify_ok, $x509_store_ctx)

Provide a custom verification callback used by TLS sessions.

C<$tls> is the C<AnyEvent::TLS> object associated with the session,
while C<$ref> is whatever the user associated with the session (usually
an L<AnyEvent::Handle> object when used by AnyEvent::Handle).

C<$preverify_ok> is true iff the basic verification of the certificates
was passed, and C<$x509_store_ctx> is the C<Net::SSLeay::X509_CTX> object.

The callback must return either C<0> to indicate failure, or C<1> to
indicate success.

=item ca_file => $path

If this parameter is specified and non-empty, it will be the path to a
file with (server) CA certificates in PEM format that will be loaded. Each
certificate will look like:

   -----BEGIN CERTIFICATE-----
   ... (CA certificate in base64 encoding) ...
   -----END CERTIFICATE-----

You have to use C<AnyEvent::TLS::VERIFY_PEER> as C<verify_mode> for this
parameter to have any effect.

=item ca_path => $path

If this parameter is specified and non-empty, it will be the
path to a directory with hashed (server) CA certificate files
in PEM format. When the ca certificate is being verified, the
certificate will be hashed and looked up in that directory (see
L<http://www.openssl.org/docs/ssl/SSL_CTX_load_verify_locations.html> for
details)

The certificates specified via C<ca_file> take precedence over the ones
found in C<ca_path>.

You have to use C<AnyEvent::TLS::VERIFY_PEER> as C<verify_mode> for this
parameter to have any effect.

=item check_crl => $enable

Enable or disable certificate revocation list checking. If enabled, then
peer certificates will be checked against a list of revocked certificates
issued by the CA. The revocation lists will be expected in the C<ca_path>
directory.

This requires OpenSSL >= 0.9.7b. Check the OpenSSL documentation for more details

=cut

# verify_depth?

# use_cert
# key_file
# key
# cert_file
# cert
# dh_file
# dh
# passwd_cb
# ca_file
# ca_path
# verify_mode
# verify_callback
# verifycn_scheme
# verifycn_name
# reuse_ctx
# session_cache_size
# session_cache

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

   $arg{verify_mode} ||= "none";

   for ($arg{verify_mode} =~ /([^\s,]+)/g) {
      exists $VERIFY_MODE{$_}
         or croak "verify mode '$_' not supported by AnyEvent::TLS";

      $self->{verify_mode} |= $VERIFY_MODE{$_};
   }

   Net::SSLeay::CTX_set_options ($ctx, Net::SSLeay::OP_NO_SSLv2 ()) unless $arg{sslv2};
   Net::SSLeay::CTX_set_options ($ctx, Net::SSLeay::OP_NO_SSLv3 ()) if exists $arg{sslv3} && !$arg{sslv3};
   Net::SSLeay::CTX_set_options ($ctx, Net::SSLeay::OP_NO_TLSv1 ()) if exists $arg{tlsv1} && !$arg{tlsv1};

   $self->{verify_cb} = $arg{verify_cb}
      if exists $arg{verify_cb};

   if ($arg{verify_mode}) {
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

   if ($arg{check_crl}) {
      Net::SSLeay::OPENSSL_VERSION_NUMBER () >= 0x00090702f
         or croak "check_crl requires openssl v0.9.7b or higher";

      Net::SSLeay::X509_STORE_set_flags (
         Net::SSLeay::CTX_get_cert_store ($ctx),
         Net::SSLeay::X509_V_FLAG_CRL_CHECK ());
   }

   $arg{prepare}->($self)
      if $arg{prepare};

   $self
}

=item $tls = new_from_ssleay AnyEvent::TLS $ctx

This constructor takes an existing L<Net::SSLeay> SSL_CTX object (which
is just an integer) and converts it into an C<AnyEvent::TLS> object. This
only works because AnyEvent::TLS is currently implemented using TLS. As
this is such a horrible perl module and openssl has such an annoying
license, this might change in the future, in which case this method might
vanish.

=cut

sub new_from_ssleay {
   my ($class, $ctx) = @_;

   bless { ctx => $ctx }, $class
}

=item $ctx = $tls->ctx

Returns the actual L<Net::SSLeay::CTX> object (just an integer).

=cut

#=item $ssl = $tls->_get_session ($mode[, $ref])
#
#Creates a new Net::SSLeay::SSL session object, puts it into C<$mode>
#(C<accept> or C<connect>) and optionally associates it with the given
#C<$ref>. If C<$mode> is already a C<Net::SSLeay::SSL> object, then just
#associate data with it.
#
#=cut

#our %REF_MAP;

sub _get_session($$;$) {
   my ($self, $mode, $ref) = @_;

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
   
   if ($self->{verify_mode}) {
      Scalar::Util::weaken $ref;

      # we have to provide a dummy callbacks as at least Net::SSLeay <= 1.35
      # try to call it even if specified as 0 or undef.
      Net::SSLeay::set_verify
         $session,
         $self->{verify_mode},
         $self->{verify_cb} ? (sub { $self->{verify_cb}->($self, $ref, @_) }) : (sub { shift });
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

   Net::SSLeay::CTX_free ($self->{ctx});
}

=back

=head1 BUGS

To to the abysmal code quality of Net::SSLeay, this module will leak small
amounts of memory per TLS connection (currently at least one perl scalar).

=head1 AUTHORS

Marc Lehmann <schmorp@schmorp.de>.

Some of the API and a lot of ideas/workarounds/knowledge has been taken
from the L<IO::Socket::SSL> module. Care has been taken to keep the API
similar to that and other modules, to the extent possible while providing
a sensible API for AnyEvent.

=cut

1

