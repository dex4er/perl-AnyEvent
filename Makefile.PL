use ExtUtils::MakeMaker;

use 5.008;

print <<EOF;

***
*** The EV or Event modules are recommended for performance, unless
*** you have to use one of the other adaptors (Glib, Tk, etc.).
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
);

