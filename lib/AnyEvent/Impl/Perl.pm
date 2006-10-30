package AnyEvent::Impl::Perl;

use Time::HiRes qw(time);
use Scalar::Util ();

our $VERSION = 0.1;

my ($fds_r, $fds_w) = ({ ref => {} }, { ref => {} });
my @timer;
my $need_sort;

sub add_fh($$) {
   my ($self, $fds) = @_;

   my $fd = fileno $self->{fh};

   (vec $fds->{v}, $fd, 1) = 1
      unless $fds->{w}{$fd};

   push @{ $fds->{w}{$fd} }, $self;
   Scalar::Util::weaken $fds->{w}{$fd}[-1];
}

sub del_fh($$) {
   my ($self, $fds) = @_;

   my $fd = fileno $self->{fh};

   if (@{ $fds->{w}{$fd} } == 1) {
      delete $fds->{w}{$fd};
      (vec $fds->{v}, $fd, 1) = 0;
   } else {
      $fds->{w}{$fd} = [
         grep $_ != $self, @{ $fds->{w}{$fd} }
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
sub iteration {
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

sub condvar {
   my $class = shift;

   bless \my $flag, $class
}

sub broadcast {
   ${$_[0]}++;
}

sub wait {
   iteration while !${$_[0]};
}

1

