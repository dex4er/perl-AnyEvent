use ExtUtils::MakeMaker;

use 5.008;

print <<EOF;

***
*** You *need* one or more of the following modules to make use of this module:
*** Coro, Event, Glib, Tk
***
*** The Makefile.PL depends on Event, but you can ignore this dependency if
*** any of the other modules are installed.
***

EOF

WriteMakefile(
    dist	=> {
	            PREOP	=> 'pod2text lib/AnyEvent.pm | tee README >$(DISTVNAME)/README; chmod -R u=rwX,go=rX . ;',
	            COMPRESS	=> 'gzip -9v',
	            SUFFIX	=> '.gz',
	           },
    NAME         => "AnyEvent",
    VERSION_FROM => "lib/AnyEvent.pm",
    PREREQ_PM    => {
       Event      => 0.86,
    },
);

