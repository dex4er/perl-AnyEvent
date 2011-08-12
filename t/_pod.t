#!perl

BEGIN { eval "use Test::Pod 1.14; 1" or ((print "1..0 # SKIP Test::Pod not installed\n"), exit 0) }

use Test::Pod 1.14;
all_pod_files_ok;
