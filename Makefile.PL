use ExtUtils::MakeMaker;

use 5.006;

WriteMakefile(
    dist	=> {
	            PREOP	=> 'pod2text MythTV/Backend.pm | tee README >$(DISTVNAME)/README; chmod -R u=rwX,go=rX . ;',
	            COMPRESS	=> 'gzip -9v',
	            SUFFIX	=> '.gz',
	           },
    NAME => "AnyEvent",
    VERSION_FROM => "lib/Event/Generic/Txn.pm",
);

