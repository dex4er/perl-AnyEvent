=head1 NAME

AnyEvent - ???

=head1 SYNOPSIS

=head1 DESCRIPTION

=over 4

=cut

package AnyEvent;

use Carp;

$VERSION = 0.1;

no warnings;

my @models = (
      [Coro  => Coro::Event::],
      [Event => Event::],
      [Glib  => Glib::],
      [Tk    => Tk::],
);

sub AUTOLOAD {
   $AUTOLOAD =~ s/.*://;

   for (@models) {
      my ($model, $package) = @$_;
      if (defined ${"$package\::VERSION"}) {
         $EVENT = "AnyEvent::Impl::$model";
         eval "require $EVENT"; die if $@;
         goto &{"$EVENT\::$AUTOLOAD"};
      }
   }

   for (@models) {
      my ($model, $package) = @$_;
      $EVENT = "AnyEvent::Impl::$model";
      if (eval "require $EVENT") {
         goto &{"$EVENT\::$AUTOLOAD"};
      }
   }

   die "No event module selected for AnyEvent and autodetect failed. Install any of these: Coro, Event, Glib or Tk.";
}

1;

