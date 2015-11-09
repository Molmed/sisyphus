#!/usr/bin/perl -w

use FindBin;                # Find the script location
use lib "$FindBin::Bin/lib";# Add the script libdir to libs
use Molmed::Sisyphus::Libpath;

use strict;
use Getopt::Long;
use Molmed::Sisyphus::Common qw(mkpath);
use Molmed::Sisyphus::IndexCheck;

=pod

=head1 NAME

checkIndices.pl - Check if there seems to be something wrong with the indices provided

=head1 SYNOPSIS

 checkIndices.pl -help|-man
 checkIndices.pl -runfolder <path to runfolder> -demuxSummary <path to folder containing DemuxSummary files> 

=head1 OPTIONS

=over 4

=item -h|-help

prints out a brief help text.

=item -m|-man

Opens the manpage.

=item -runfolder 

Full path to runfolder of interest

=item -demuxSummary

Path to folder containing DemuxSummary files, e.g. '<path to runfolder>/Unaligned/Stats'

=item -debug

Print debugging information

=back

=head1 DESCRIPTION

Investigates if there are indices among Undetermined indices that appear significantly often (we set the threshold at 1% of all reads in lane).
Common causes are tested.   

=cut

# Parse options
my($help,$man) = (0,0);
my $DemuxSumPath = "";
my $rfPath = "";
our $debug = 0;

GetOptions('help|?'=>\$help,
            'man'=>\$man,
            'runfolder=s' => \$rfPath,
	        'demuxSummary=s' => \$DemuxSumPath,
	        'debug'=> \$debug,
	  ) or pod2usage(-verbose => 0);
pod2usage(-verbose => 1)  if ($help);
pod2usage(-verbose => 2)  if ($man);

unless(defined $rfPath && -e $rfPath){
    print STDERR "Runfolder not specified or does not exist\n";
    pod2usage(-verbose => 1);
    exit;
}

# Create a new sisyphus object for common functions
my $sisyphus = Molmed::Sisyphus::Common->new(PATH=>$rfPath, DEBUG=>$debug);
$rfPath = $sisyphus->PATH;

# Setting default DemuxSummaryPath
if (length($DemuxSumPath)==0){
    $DemuxSumPath = $rfPath . "/Unaligned/Stats";
}

my $sampleSheet = $sisyphus->readSampleSheet();
my $noOfSamples = $sisyphus->samplesPerLane(); 
my $numLanes = $sisyphus->laneCount();

my $failedIndexCheck = checkIndices($sisyphus, $DemuxSumPath, $noOfSamples, $numLanes, $debug); 

if($failedIndexCheck){

    print "\n";
    exit 1;

}
else{

    print "Undetermined indices OK!\n\n"

}

