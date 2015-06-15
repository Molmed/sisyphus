#!/usr/bin/perl -w

use strict;

use FindBin;                # Find the script location
use lib "$FindBin::Bin/lib";# Add the script libdir to libs

use Pod::Usage;
use Getopt::Long;


use Molmed::Sisyphus::Common;

=pod

=head1 NAME

generateIncludedTiles.pl - Print tiles to include, one tile per line to stdout. 

=head1 SYNOPSIS

 generateIncludedTiles.pl -help|-man
 generateIncludedTiles.pl -runfolder <runfolder>

=head1 OPTIONS

=over 4

=item -h|-help

Prints out a brief help text.

=item -m|-man

Opens the man page

=item -runfolder

The runfolder to extract the included tiles information from.

=item -format

Format as a comma-separated string to be consumed by bcl2fastq.

=item -debug

Print debuging information

=head1 DESCRIPTION

Generates a list of tiles to include. Please note that the error rate used to
decide if a tile should be included or not is decided by the values
specified in the sisyphus.yml config file.

=cut

my $rfPath = undef;
my $debug = undef;
my $format = undef;

my ($help,$man) = (0,0);

GetOptions('help|?'=>\$help,
	   'man'=>\$man,
	   'runfolder=s' => \$rfPath,
           'format' => \$format,
	   'debug' => \$debug,
	  ) or pod2usage(-verbose => 0);
pod2usage(-verbose => 1)  if ($help);
pod2usage(-verbose => 2)  if ($man);

unless(defined $rfPath && -e $rfPath){
    print STDERR "Runfolder not specified or does not exist\n";
    pod2usage(-verbose => 1);
    exit 1;
}


my $sisyphus = Molmed::Sisyphus::Common->new(PATH=>$rfPath, DEBUG=>$debug);

# Identify tiles with too high error for exclusion
my ($incTilesRef, $excTilesRef) = $sisyphus->getExcludedAndIncludedTiles();

my @incTiles = @{$incTilesRef};
my @excTiles = @{$excTilesRef};

if(defined($format)){
    my $includeTiles = join ',', @incTiles;
    print "$includeTiles\n";
}
else {
    foreach(@incTiles){
        print "$_\n";
    }
}

