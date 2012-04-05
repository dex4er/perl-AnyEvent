=head1 NAME

AnyEvent::Impl::Stem - AnyEvent adaptor for Stem

=head1 SYNOPSIS

   use AnyEvent;
   use Stem;
  
   # this module gets loaded automatically as required

=head1 DESCRIPTION

This module provides transparent support for AnyEvent. You don't have to
do anything to make Stem work with AnyEvent except by loading Stem before
creating the first AnyEvent watcher.

=cut

package AnyEvent::Impl::Stem;

use AnyEvent (); BEGIN { AnyEvent::common_sense }

use Stem::Event;
use Stem::Class; #???

my $dummy = bless []; # *sigh*

sub timer {
   my ($class, %arg) = @_;

   my $stem = new Stem::Event::Timer
      object   => (bless \\$arg{cb}),
      method   => "invoke",
      delay    => $arg{after},
      interval => 1; # work around bug in stem, it works with one-shot timeouts only

   $stem->start;

   bless \\$stem, "AnyEvent::Impl::Stem::wrap"
}

sub io {
   my ($class, %arg) = @_;

   my $stem = $arg{poll} eq "r"
      ? new Stem::Event::Read
         object => (bless \\$arg{cb}),
         method => "invoke",
         fh     => $arg{fh},
      : new Stem::Event::Write
         object => (bless \\$arg{cb}),
         method => "invoke",
         fh     => $arg{fh};

   $stem->start;

   bless \\$stem, "AnyEvent::Impl::Stem::wrap"
}

sub signal {
   my ($class, %arg) = @_;

   my $stem = new Stem::Event::Signal
      object => (bless \\$arg{cb}),
      method => "invoke",
      signal => AnyEvent::Base::sig2name $arg{signal};

   $stem->start;

   bless \\$stem, "AnyEvent::Impl::Stem::wrap"
}

sub AnyEvent::Impl::Stem::wrap::DESTROY {
   ${${$_[0]}}->cancel;
}

sub invoke {
   ${${$_[0]}}->();
}

sub child {
   my ($class, %arg) = @_;

   die;

#   # seems there is special sigchld support in stem, this needs to be used
#   EV::child $arg{pid}, 0, sub {
#      $cb->($_[0]->rpid, $_[0]->rstatus);
#   }
}

sub condvar {
   die;
   bless \my $flag, "AnyEvent::Impl::Stem"
}

sub broadcast {
   ++${$_[0]};
   Stem::Event::stop_loop;
}

sub stopbusywaiting {
   Stem::Event::stop_loop;
}

sub wait {
   while (!${$_[0]}) {
      Stem::Event::start_loop;
   }
}

=head1 SEE ALSO

L<AnyEvent>, L<Stem>.

=head1 AUTHOR

 Marc Lehmann <schmorp@schmorp.de>
 http://software.schmorp.de/pkg/AnyEvent.html

=cut

1

