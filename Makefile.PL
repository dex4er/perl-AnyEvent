use ExtUtils::MakeMaker;

use 5.008; # AnyEvent perl event loop seems to work with 5.6, other modules not

print <<EOF;

***
*** The EV module is recommended for even better performance, unless you
*** have to use one of the other adaptors (Event, Glib, Tk, etc.).
***
*** This module does not have ANY dependencies, even if it might look
*** otherwise. If you are building a distribution package or have
*** difficulties installing this package due to dependencies, report this
*** to the packager as a bug.
***
*** This module is guaranteed to stay pure-perl and still be full-featured
*** and performant, even without any optionally recommended modules.
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
    META_MERGE => {
        recommends => {
           "Net::SSLeay"      => 1.33,
           "JSON"             => 2.09,
           "JSON::XS"         => 2.2,
           "EV"               => 3.05,
           "Guard"            => 1.02,
           "Async::Interrupt" => 0.6,
        }
    },
);

sub MY::postamble {
   <<EOF;

# set \$VERSION in all modules
setver:
	\$(PERL) -pi -e 's/^(\\s*(our\\s*)?\\\$\$VERSION\\s*=\\s*).*\$\$/\$\${1}\$(VERSION);/' \$(TO_INST_PM)

EOF
}

