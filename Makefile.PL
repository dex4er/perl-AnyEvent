use ExtUtils::MakeMaker;

use 5.008;

print <<EOF;

***
*** One or more of these modules, in order of importance, is recommended:
*** Event, Coro, Glib, Tk
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
#    PREREQ_PM    => {
#       Event      => 0.86,
#    },
);

