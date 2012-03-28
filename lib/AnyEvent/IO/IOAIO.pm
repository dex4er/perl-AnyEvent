=head1 NAME

AnyEvent::IOAIO - AnyEvent::IO backend based on IO::AIO

=head1 SYNOPSIS

   use AnyEvent::IO;

=head1 DESCRIPTION

This is the L<IO::AIO>-based backend of L<AnyEvent::IO> (via
L<AnyEvent::AIO>). All I/O operations it implements are done
asynchronously.

=head1 FUNCTIONS

=over 4

=cut

package AnyEvent::IO::IOAIO;

use AnyEvent (); BEGIN { AnyEvent::common_sense }
our $VERSION = $AnyEvent::VERSION;

package AnyEvent::IO;

use IO::AIO ();
use AnyEvent::AIO ();

our $MODEL = "IOAIO";

sub ae_load($$) {
   my ($cb, $data) = $_[1];
   IO::AIO::aio_load $_[0], $data, sub { $cb->($_[0] >= 0 ? $data : ()) };
}

sub ae_open($$$$) {
   my $cb = $_[3];
   IO::AIO::aio_open $_[0], $_[1], $_[2], sub { $cb->($_[0] or ()) };
}

sub ae_close($$) {
   my $cb = $_[1];
   IO::AIO::aio_close $_[0], sub { $cb->($_[0] >= 0 ? 1 : ()) };
}

sub ae_read($$$) {
   my ($cb, $data) = $_[2];

   IO::AIO::aio_read $_[0], undef, $_[1], $data, 0, sub {
      $cb->($_[0] >= 0 ? $data : ())
   };
}

sub ae_write($$$) {
   my $cb = $_[2];

   IO::AIO::aio_write $_[0], undef, (length $_[1]), $_[1], 0, sub {
      $cb->($_[0] >= 0 ? $_[0] : ())
   };
}

sub ae_stat($$) {
   my $cb = $_[1];
   IO::AIO::aio_stat $_[0], sub { $cb->($_[0] >= 0 ? 1 : ()) };
}

sub ae_lstat($$) {
   my $cb = $_[1];
   IO::AIO::aio_lstat $_[0], sub { $cb->($_[0] >= 0 ? 1 : ()) }
}

sub ae_link($$$) {
   my $cb = $_[2];
   IO::AIO::aio_link $_[0], $_[1], sub { $cb->($_[0] >= 0 ? 1 : ()) };
}

sub ae_symlink($$$) {
   my $cb = $_[2];
   IO::AIO::aio_symlink $_[0], $_[1], sub { $cb->($_[0] >= 0 ? 1 : ()) };
}

sub ae_readlink($$) {
   my $cb = $_[1];
   IO::AIO::aio_readlink $_[0], sub { $cb->(defined $_[0] ? $_[0] : ()) };
}

sub ae_rename($$$) {
   my $cb = $_[2];
   IO::AIO::aio_rename $_[0], $_[1], sub { $cb->($_[0] >= 0 ? 1 : ()) };
}

sub ae_unlink($$) {
   my $cb = $_[1];
   IO::AIO::aio_unlink $_[0], sub { $cb->($_[0] >= 0 ? 1 : ()) };
}

sub ae_mkdir($$$) {
   my $cb = $_[2];
   IO::AIO::aio_mkdir $_[0], $_[1], sub { $cb->($_[0] >= 0 ? 1 : ()) };
}

sub ae_rmdir($$) {
   my $cb = $_[1];
   IO::AIO::aio_rmdir $_[0], sub { $cb->($_[0] >= 0 ? 1 : ()) };
}

sub ae_readdir($$) {
   my $cb = $_[1];

   IO::AIO::aio_readdirx $_[0], IO::AIO::READDIR_DIRS_FIRST | IO::AIO::READDIR_STAT_ORDER, sub {
      $cb->($_[0] or ());
   };
}

=back

=head1 SEE ALSO

L<AnyEvent::IO>, L<AnyEvent>.

=head1 AUTHOR

 Marc Lehmann <schmorp@schmorp.de>
 http://home.schmorp.de/

=cut

1

