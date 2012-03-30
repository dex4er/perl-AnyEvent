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

our $MODEL = "AnyEvent::IO::Perl";

sub ae_load($$) {
   my ($path, $cb, $fh, $data) = @_;

   $cb->(
      (open $fh, "<:raw:perlio", $path
         and stat $fh
         and (-s _) == sysread $fh, $data, -s _)
      ? $data : ()
   );
}

sub ae_open($$$$) {
   sysopen my $fh, $_[0], $_[1], $_[2]
      or return $_[3]();

   $_[3]($fh)
}

sub ae_close($$) {
   $_[1](close $_[0]);
}

sub ae_read($$$) {
   my $data;
   $_[2]( (defined sysread $_[0], $data, $_[1]) ? $data : () );
}

sub ae_write($$$) {
   my $res = syswrite $_[0], $_[1];
   $_[2](defined $res ? $res : ());
}

sub ae_stat($$) {
   $_[1](stat  $_[0]);
}

sub ae_lstat($$) {
   $_[1](lstat $_[0]);
}

sub ae_link($$$) {
   $_[2](link $_[0], $_[1] or ());
}

sub ae_symlink($$$) {
   #TODO: raises an exception on !symlink systems, maybe eval + set errno?
   $_[2](symlink $_[0], $_[1] or ());
}

sub ae_readlink($$) {
   #TODO: raises an exception on !symlink systems, maybe eval + set errno?
   my $res = readlink $_[0];
   $_[1](defined $res ? $res : ());
}

sub ae_rename($$$) {
   $_[2](rename $_[0], $_[1] or ());
}

sub ae_unlink($$) {
   $_[1](unlink $_[0] or ());
}

sub ae_mkdir($$$) {
   $_[2](mkdir $_[0], $_[1] or ());
}

sub ae_rmdir($$) {
   $_[1](rmdir $_[0] or ());
}

sub ae_readdir($$) {
   my ($fh, @res);

   opendir $fh, $_[0]
      or return $_[1]();

   @res = grep !/^\.\.?$/, readdir $fh;

   $_[1]((closedir $fh) ? \@res : ());
}

=head1 SEE ALSO

L<AnyEvent::IO>, L<AnyEvent>.

=head1 AUTHOR

 Marc Lehmann <schmorp@schmorp.de>
 http://home.schmorp.de/

=cut

1

