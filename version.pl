#!/usr/bin/perl -w

use FindBin;                # Find the script location
use lib "$FindBin::Bin/lib";# Add the script libdir to libs

use strict;
use Molmed::Sisyphus::Common;

my $sisyphus = Molmed::Sisyphus::Common->new(PATH=>$FindBin::Bin);
our $VERSION = $sisyphus->version();

print $VERSION;


