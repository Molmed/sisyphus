package Molmed::Sisyphus::Libpath;

use strict;
use FindBin;                # Find the script location
use Config;

BEGIN {
    if(-e "$FindBin::Bin/PERL5LIB"){
	my $arch = $Config{archname};
	open(my $IN, "$FindBin::Bin/PERL5LIB") or die "Failed to read $FindBin::Bin/PERL5LIB: $!";
	while(<$IN>){
	    chomp;
	    if($_ && -e $_){
		if(-e "$_/$arch"){
		    unshift(@INC, "$_/$arch");
		}
		unshift(@INC, $_);
	    }
	}
	close($IN);
    }
}

1
