=head1 NAME

AnyEvent::IO::Perl - pure perl backend for AnyEvent::IO

=head1 SYNOPSIS

   use AnyEvent::IO;

=head1 DESCRIPTION

This is the pure-perl backend of L<AnyEvent::IO> - it is always available,
but does not actually implement any I/O operation asynchronously -
everything is synchronous.

For simple programs that can wait for I/O, this is likely the most
efficient implementation.

=cut

package AnyEvent::IO::Perl;

use AnyEvent (); BEGIN { AnyEvent::common_sense }
our $VERSION = $AnyEvent::VERSION;

package AnyEvent::IO;

our $MODEL = "Perl";

sub io_load($$) {
   my ($path, $cb) = @_;

   open my $fh, "<:raw:perlio", $path
      or return $cb->();
   stat $fh
      or return $cb->();
   (-s $_) == sysread $fh, my $data, -s $_
      or return $cb->();

   $cb->($data)
}

sub io_open($$$$) {
   sysopen my $fh, $_[0], $_[1], $_[2]
      or return $_[3]();

   $_[3]($fh)
}

sub io_close($$) {
   $_[1](close $_[0]);
}

sub io_read($$$) {
   my $data;

   $_[2]( (sysread $_[0], $data, $_[1]) ? $data : () );
}

sub io_write($$$) {
   $_[2]( syswrite $_[0], $_[1] or () );
}

sub io_stat($$) {
   $_[1](stat  $_[0]);
}

sub io_lstat($$) {
   $_[1](lstat $_[0]);
}

=head1 SEE ALSO

L<AnyEvent::IO>, L<AnyEvent>.

=head1 AUTHOR

 Marc Lehmann <schmorp@schmorp.de>
 http://home.schmorp.de/

=cut

1

