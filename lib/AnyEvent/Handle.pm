package AnyEvent::Handle;

use warnings;
use strict;

use AnyEvent;
use IO::Handle;
use Errno qw/EAGAIN EINTR/;

=head1 NAME

AnyEvent::Handle - non-blocking I/O on filehandles via AnyEvent

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';

=head1 SYNOPSIS

   use AnyEvent;
   use AnyEvent::Handle;

   my $cv = AnyEvent->condvar;

   my $ae_fh = AnyEvent::Handle->new (fh => \*STDIN);

   $ae_fh->readlines (sub {
      my ($ae_fh, @lines) = @_;
      for (@lines) {
         chomp;
         print "Line: $_";
      }
      $cv->broadcast;
   });

   $cv->wait;

=head1 DESCRIPTION

This module is a helper module to make it easier to do non-blocking I/O
on filehandles (and sockets, see L<AnyEvent::Socket>).

The event loop is provided by L<AnyEvent>.

=head1 METHODS

=over 4

=item B<new (%args)>

The constructor has these arguments:

=over 4

=item fh => $filehandle

The filehandle this L<AnyEvent::Handle> object will operate on.

NOTE: The filehandle will be set to non-blocking.

=item read_block_size => $size

The default read block size use for reads via the C<on_read>
method.

=back

=cut

sub new {
   my $this  = shift;
   my $class = ref($this) || $this;
   my $self  = {
      read_block_size => 4096,
      rbuf            => '',
      @_
   };
   bless $self, $class;

   $self->{fh}->blocking (0) if $self->{fh};

   if ($self->{on_read}) {
      $self->on_read ($self->{on_read});

   } elsif ($self->{on_readline}) {
      $self->readlines ($self->{on_readline});
   }

   return $self
}

=item B<fh>

This method returns the filehandle of the L<AnyEvent::Handle> object.

=cut

sub fh { $_[0]->{fh} }

=item B<on_read ($callback)>

This method installs a C<$callback> that will be called
when new data arrived. You can access the read buffer via the C<rbuf>
method (see below).

The first argument of the C<$callback> will be the L<AnyEvent::Handle> object.

=cut

sub on_read {
   my ($self, $cb) = @_;
   $self->{on_read} = $cb;

   unless (defined $self->{on_read}) {
      delete $self->{on_read_w};
      return;
   }
  
   $self->{on_read_w} =
      AnyEvent->io (poll => 'r', fh => $self->{fh}, cb => sub {
         #d# warn "READ:[$self->{read_size}] $self->{read_block_size} : ".length ($self->{rbuf})."\n";
         my $rbuf_len = length $self->{rbuf};
         my $l;
         if (defined $self->{read_size}) {
            $l = sysread $self->{fh}, $self->{rbuf},
                         ($self->{read_size} - $rbuf_len), $rbuf_len;
         } else {
            $l = sysread $self->{fh}, $self->{rbuf}, $self->{read_block_size}, $rbuf_len;
         }
         #d# warn "READL $l [$self->{rbuf}]\n";

         if (not defined $l) {
            return if $! == EAGAIN || $! == EINTR;
            $self->{on_error}->($self, $!) if $self->{on_error};
            delete $self->{on_read_w};

         } elsif ($l == 0) {
            $self->{on_eof}->($self) if $self->{on_eof};
            delete $self->{on_read_w};

         } else {
            $self->{on_read}->($self);
         }
      });
}

=item B<on_error ($callback)>

Whenever a read or write operation resulted in an error the C<$callback>
will be called.

The first argument of C<$callback> will be the L<AnyEvent::Handle> object itself
and the second argument will be the value of C<$!>.

=cut

sub on_error {
   $_[0]->{on_error} = $_[1];
}

=item B<on_eof ($callback)>

Installs the C<$callback> that will be called when the end of file is
encountered in a read operation this C<$callback> will be called. The first
argument will be the L<AnyEvent::Handle> object itself.

=cut

sub on_eof {
   $_[0]->{on_eof} = $_[1];
}

=item B<rbuf>

Returns a reference to the read buffer.

NOTE: The read buffer should only be used or modified if the C<on_read>
method is used directly. The C<read> and C<readlines> methods will provide
the read data to their callbacks.

=cut

sub rbuf : lvalue { $_[0]->{rbuf} }

=item B<read ($len, $callback)>

Will read exactly C<$len> bytes from the filehandle and call the C<$callback>
if done so. The first argument to the C<$callback> will be the L<AnyEvent::Handle>
object itself and the second argument the read data.

NOTE: This method will override any callbacks installed via the C<on_read> method.

=cut

sub read {
   my ($self, $len, $cb) = @_;

   $self->{read_cb} = $cb;
   my $old_blk_size = $self->{read_block_size};
   $self->{read_block_size} = $len;

   $self->on_read (sub {
      #d# warn "OFOFO $len || ".length($_[0]->{rbuf})."||\n";

      if ($len == length $_[0]->{rbuf}) {
         $_[0]->{read_block_size} = $old_blk_size;
         $_[0]->on_read (undef);
         $_[0]->{read_cb}->($_[0], (substr $self->{rbuf}, 0, $len, ''));
      }
   });
}

=item B<readlines ($callback)>

=item B<readlines ($sep, $callback)>

This method will read lines from the filehandle, seperated by C<$sep> or C<"\n">
if C<$sep> is not provided. C<$sep> will be used as part of a regex, so it can be
a regex itself and won't be quoted!

The C<$callback> will be called when at least one
line could be read. The first argument to the C<$callback> will be the L<AnyEvent::Handle>
object itself and the rest of the arguments will be the read lines.

NOTE: This method will override any callbacks installed via the C<on_read> method.

=cut

sub readlines {
   my ($self, $NL, $cb) = @_;

   if (ref $NL) {
      $cb = $NL;
      $NL = "\n";
   }

   $self->{on_readline} = $cb;

   $self->on_read (sub {
      my @lines;
      push @lines, $1 while $_[0]->{rbuf} =~ s/(.*)$NL//;
      $self->{on_readline}->($_[0], @lines);
   });
}

=item B<write ($data)>

=item B<write ($callback)>

=item B<write ($data, $callback)>

This method will write C<$data> to the filehandle and call the C<$callback>
afterwards. If only C<$callback> is provided it will be called when the
write buffer becomes empty the next time (or immediately if it already is empty).

=cut

sub write {
   my ($self, $data, $cb) = @_;
   if (ref $data) { $cb = $data; undef $data }
   push @{$self->{write_bufs}}, [$data, $cb];
   $self->_check_writer;
}

sub _check_writer {
   my ($self) = @_;

   if ($self->{write_w}) {
      unless ($self->{write_cb}) {
         while (@{$self->{write_bufs}} && not defined $self->{write_bufs}->[0]->[1]) {
            my $wba = shift @{$self->{write_bufs}};
            $self->{wbuf} .= $wba->[0];
         }
      }
      return;
   }

   my $wba = shift @{$self->{write_bufs}}
      or return;

   unless (defined $wba->[0]) {
      $wba->[1]->($self) if $wba->[1];
      $self->_check_writer;
      return;
   }

   $self->{wbuf}     = $wba->[0];
   $self->{write_cb} = $wba->[1];

   $self->{write_w} =
      AnyEvent->io (poll => 'w', fh => $self->{fh}, cb => sub {
         my $l = syswrite $self->{fh}, $self->{wbuf}, length $self->{wbuf};

         if (not defined $l) {
            return if $! == EAGAIN || $! == EINTR;
            delete $self->{write_w};

            $self->{on_error}->($self, $!) if $self->{on_error};

         } else {
            substr $self->{wbuf}, 0, $l, '';

            if (length ($self->{wbuf}) == 0) {
               $self->{write_cb}->($self) if $self->{write_cb};

               delete $self->{write_w};
               delete $self->{wbuf};
               delete $self->{write_cb};

               $self->_check_writer;
            }
         }
      });
}

=back

=head1 AUTHOR

Robin Redeker, C<< <elmex at ta-sa.org> >>

=head1 BUGS

Please report any bugs or feature requests to
C<bug-io-anyevent at rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=IO-AnyEvent>.
I will be notified, and then you'll automatically be notified of progress on
your bug as I make changes.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc AnyEvent::Handle

You can also look for information at:

=over 4

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/IO-AnyEvent>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/IO-AnyEvent>

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=IO-AnyEvent>

=item * Search CPAN

L<http://search.cpan.org/dist/IO-AnyEvent>

=back

=head1 ACKNOWLEDGEMENTS

=head1 COPYRIGHT & LICENSE

Copyright 2008 Robin Redeker, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1; # End of AnyEvent::Handle
