=head1 NAME

AnyEvent::Impl::Glib - AnyEvent adaptor for Glib

=head1 SYNOPSIS

   use AnyEvent;
   use Glib;
  
   # this module gets loaded automatically as required

=head1 DESCRIPTION

This module provides transparent support for AnyEvent. You don't have to
do anything to make Glib work with AnyEvent except by loading Glib before
creating the first AnyEvent watcher.

Glib is probably the most inefficient event loop that has ever seen the
light of the world: Glib not only scans all its watchers (really, ALL
of them, whether I/O-related, timer-related or not) during each loop
iteration, it also does so multiple times and rebuilds the poll list for
the kernel each time again, dynamically even.

If you create many watchers (as in: more than two), you might consider one
of the L<Glib::EV>, L<EV::Glib> or L<Glib::Event> modules that map Glib to
other, more efficient, event loops.

This module uses the default Glib main context for all it's watchers.

=cut

package AnyEvent::Impl::Glib;

no warnings;
use strict;

use Glib ();

our $maincontext = Glib::MainContext->default;

sub io {
   my ($class, %arg) = @_;
   
   my $fh = $arg{fh};
   my $cb = $arg{cb};

   my @cond;
   # some glibs need hup, others error with it, YMMV
   push @cond, "in",  "hup" if $arg{poll} eq "r";
   push @cond, "out", "hup" if $arg{poll} eq "w";

   my $source = add_watch Glib::IO fileno $arg{fh}, \@cond, sub {
      &$cb;
      $fh; # mention it here to keep it from being destroyed
      1
   };

   bless \\$source, $class
}

sub timer {
   my ($class, %arg) = @_;
   
   my $cb = $arg{cb};
   my $rp = $arg{repeat};

   my $source = add Glib::Timeout 1000 * delete $arg{after}, sub {
      &$cb;
      $rp
   };

   bless \\$source, $class
}

sub DESTROY {
   remove Glib::Source $${$_[0]};
}

sub one_event {
   $maincontext->iteration (1);
}

1;

=head1 SEE ALSO

L<AnyEvent>, L<Glib>.

=head1 AUTHOR

 Marc Lehmann <schmorp@schmorp.de>
 http://home.schmorp.de/

=cut

