=head1 NAME

AnyEvent::Util - various utility functions.

=head1 SYNOPSIS

 use AnyEvent::Util;

 inet_aton $name, $cb->($ipn || undef)

=head1 DESCRIPTION

This module implements various utility functions, mostly replacing
well-known functions by event-ised counterparts.

=over 4

=cut

package AnyEvent::Util;

use strict;

no warnings "uninitialized";

use Socket ();

use AnyEvent;

use base 'Exporter';

#our @EXPORT = qw(gethostbyname gethostbyaddr);
our @EXPORT_OK = qw(inet_aton fork_eval);

our $VERSION = '1.0';

our $MAXPARALLEL = 16; # max. number of parallel jobs

our $running;
our @queue;

sub _schedule;
sub _schedule {
   return unless @queue;
   return if $running >= $MAXPARALLEL;

   ++$running;
   my ($cb, $sub, @args) = @{shift @queue};

   if (eval { require POSIX }) {
      my $pid = open my $fh, "-|";

      if (!defined $pid) {
         die "fork: $!";
      } elsif (!$pid) {
         syswrite STDOUT, join "\0", map { unpack "H*", $_ } $sub->(@args);
         POSIX::_exit (0);
      }

      my $w; $w = AnyEvent->io (fh => $fh, poll => 'r', cb => sub {
         --$running;
         _schedule;
         undef $w;

         my $buf;
         sysread $fh, $buf, 16384, length $buf;
         $cb->(map { pack "H*", $_ } split /\0/, $buf);
      });
   } else {
      $cb->($sub->(@args));
   }
}

sub _do_asy {
   push @queue, [@_];
   _schedule;
}

sub dotted_quad($) {
   $_[0] =~ /^(?:25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[0-9][0-9]?)
            \.(?:25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[0-9][0-9]?)
            \.(?:25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[0-9][0-9]?)
            \.(?:25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[0-9][0-9]?)$/x
}

my $has_ev_adns;

sub has_ev_adns {
   ($has_ev_adns ||= do {
      my $model = AnyEvent::detect;
      (($model eq "AnyEvent::Impl::CoroEV" or $model eq "AnyEvent::Impl::EV")
       && eval { require EV::ADNS })
         ? 2 : 1
   }) - 1
}

=item AnyEvent::Util::inet_aton $name_or_address, $cb->($binary_address_or_undef)

Works almost exactly like its Socket counterpart, except that it uses a
callback.

=cut

sub inet_aton {
   my ($name, $cb) = @_;

   if (&dotted_quad) {
      $cb->(Socket::inet_aton $name);
   } elsif (has_ev_adns) {
      my $current = $Coro::current;
      my @a;
 
      EV::ADNS::submit ($_[0], &EV::ADNS::r_a, 0, sub {
         (undef, undef, @a) = @_;
         $cb->(@a ? Socket::inet_aton $a[0] : undef);
      });
   } else {
      _do_asy $cb, sub { Socket::inet_aton $_[0] }, @_;
   }
}

1;

=back

=head1 AUTHOR

 Marc Lehmann <schmorp@schmorp.de>
 http://home.schmorp.de/

=cut

