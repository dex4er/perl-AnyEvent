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
    test         => { TESTS => "t/*.t t/handle/*.t" },
    NAME         => "AnyEvent",
    VERSION_FROM => "lib/AnyEvent.pm",
    EXTRA_META => q{
recommends:
  Net::SSLeay: 0
  JSON: 2.09
  JSON::XS 2.2
  EV: 4.05
    },
);

