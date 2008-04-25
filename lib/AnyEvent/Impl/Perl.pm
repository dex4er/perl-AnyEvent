=head1 NAME

AnyEvent::Impl::Perl - Pure-Perl event loop and AnyEvent adaptor for itself

=head1 SYNOPSIS

  use AnyEvent;
  # use AnyEvent::Impl::Perl;

  # this module gets loaded automatically as required

=head1 DESCRIPTION

This module provides transparent support for AnyEvent in case no other
event loop could be found or loaded. You don't have to do anything to make
it work with AnyEvent except by possibly loading it before creating the
first AnyEvent watcher.

If you want to use this module instead of autoloading another event loop
you can simply load it before creating the first watcher.

=cut

package AnyEvent::Impl::Perl;

no warnings;
use strict;

use Time::HiRes qw(time);
use Scalar::Util ();

our $VERSION = 0.1;

my ($fds_r, $fds_w) = ({}, {});
my @timer;
my $need_sort;

sub fds_chk($$) {
   my ($fds, $vec) = @_;

   for my $fd (keys %{ $fds->{w} }) {
      if (vec $vec, $fd, 1) {
         $_ && $_->[2]()
            for @{ $fds->{w}{$fd} || [] };
      }
   }
}

# the pure perl mainloop
sub one_event {
   # 1. sort timers if required (slow)
   if ($need_sort) {
      undef $need_sort;
      @timer = sort { $a->[0] <=> $b->[0] } @timer;
   }

   my $NOW = time;

   # 2. check timers
   if (@timer && $timer[0][0] <= $NOW) {
      do {
         my $timer = shift @timer;
         $timer->[1][0]() if $timer->[1];
      } while @timer && $timer[0][0] <= $NOW;
   } else {

      # 3. select
      if (my $fds = select
            my $r = $fds_r->{v},
            my $w = $fds_w->{v},
            undef,
            @timer ? $timer[0][0] - $NOW  + 0.0009 : 3600
      ) {
         fds_chk $fds_w, $w;
         fds_chk $fds_r, $r;
      }
   }
}

sub io {
   my ($class, %arg) = @_;

   $arg{fd} = fileno $arg{fh};
   
   my $self = bless [
      $arg{fh},
      $arg{poll} eq "r",
      $arg{cb},
      # q-idx
   ], AnyEvent::Impl::Perl::Io::;

   my $fds = $self->[1] ? $fds_r : $fds_w;

   # add_fh
   my $fd = fileno $self->[0];
   my $q = $fds->{w}{$fd} ||= [];

   (vec $fds->{v}, $fd, 1) = 1;

   $self->[3] = @$q;
   push @$q, $self;
   Scalar::Util::weaken $q->[-1];

   $self
}

sub AnyEvent::Impl::Perl::Io::DESTROY {
   my ($self) = @_;

   my $fds = $self->[1] ? $fds_r : $fds_w;

   # del_fh
   my $fd = fileno $self->[0];

   if (@{ $fds->{w}{$fd} } == 1) {
      delete $fds->{w}{$fd};
      (vec $fds->{v}, $fd, 1) = 0;
   } else {
      my $q = $fds->{w}{$fd};
      my $last = pop @$q;

      if ($last != $self) {
         $q->[$self->[3]] = $last;
         $last->[3] = $self->[3];
      }
   }
}

sub timer {
   my ($class, %arg) = @_;
   
   my $self = bless [$arg{cb}], AnyEvent::Impl::Perl::Timer::;

   push @timer, [time + $arg{after}, $self];
   Scalar::Util::weaken $timer[-1][1];
   $need_sort = 1;

   $self
}

1;

=head1 SEE ALSO

L<AnyEvent>.

=head1 AUTHOR

 Marc Lehmann <schmorp@schmorp.de>
 http://home.schmorp.de/

=cut


