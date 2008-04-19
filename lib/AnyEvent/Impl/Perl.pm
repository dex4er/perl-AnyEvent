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

my ($fds_r, $fds_w) = ({ ref => {} }, { ref => {} });
my @timer;
my $need_sort;

sub add_fh($$) {
   my ($self, $fds) = @_;

   (vec $fds->{v}, $self->{fd}, 1) = 1
      unless $fds->{w}{$self->{fd}};

   push @{ $fds->{w}{$self->{fd}} }, $self;
   Scalar::Util::weaken $fds->{w}{$self->{fd}}[-1];
}

sub del_fh($$) {
   my ($self, $fds) = @_;

   if (@{ $fds->{w}{$self->{fd}} } == 1) {
      delete $fds->{w}{$self->{fd}};
      (vec $fds->{v}, $self->{fd}, 1) = 0;
   } else {
      $fds->{w}{$self->{fd}} = [
         grep $_ != $self, @{ $fds->{w}{$self->{fd}} }
      ];
   }
}

sub fds_chk($$) {
   my ($fds, $vec) = @_;

   for my $fd (keys %{ $fds->{w} }) {
      if (vec $vec, $fd, 1) {
         $_->{cb}()
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
      my $timer = shift @timer;
      $timer->[1]{cb}() if $timer->[1];
      return;
   }

   # 3. select
   my $fds = select
      my $r = $fds_r->{v},
      my $w = $fds_w->{v},
      undef,
      @timer ? $timer[0][0] - $NOW  + 0.0009 : 3600;

   if ($fds) {
      fds_chk $fds_w, $w;
      fds_chk $fds_r, $r;
   }
}

sub io {
   my ($class, %arg) = @_;

   $arg{fd} = fileno $arg{fh};
   
   my $self = bless \%arg, $class;

   $self->add_fh ($fds_r) if $self->{poll} eq "r";
   $self->add_fh ($fds_w) if $self->{poll} eq "w";

   $self
}

sub timer {
   my ($class, %arg) = @_;
   
   my $self = bless \%arg, $class;

   push @timer, [time + $self->{after}, $self];
   Scalar::Util::weaken $timer[-1][1];
   $need_sort = 1;

   $self
}

sub DESTROY {
   my ($self) = @_;

   $self->del_fh ($fds_r) if $self->{poll} eq "r";
   $self->del_fh ($fds_w) if $self->{poll} eq "w";

   %$self = ();
}

1;

=head1 SEE ALSO

L<AnyEvent>.

=head1 AUTHOR

 Marc Lehmann <schmorp@schmorp.de>
 http://home.schmorp.de/

=cut


