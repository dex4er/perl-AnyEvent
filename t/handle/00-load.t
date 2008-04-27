#!perl -T

use Test::More tests => 1;

BEGIN {
        use_ok( 'AnyEvent::Handle' );
}

diag( "Testing AnyEvent::Handle $AnyEvent::Handle::VERSION, Perl $], $^X" );
