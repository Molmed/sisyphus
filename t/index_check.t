#!/usr/bin/perl -w

use strict;
use warnings;
use Test::More;
use Test::Exception;
use Carp;
use File::Basename;
use FindBin;                # Find the script location
use lib "$FindBin::Bin/../lib";# Add the script libdir to libs
use File::Find;
use Molmed::Sisyphus::Common;

# Verify module can be included via "use" pragma
BEGIN { use_ok('Molmed::Sisyphus::IndexCheck') };

# Verify module can be included via "require" pragma
require_ok( 'Molmed::Sisyphus::IndexCheck' );

my $testfolder = $FindBin::Bin . '/index_check_files';

# Create a new sisyphus object for common functions
my $sisyphus = Molmed::Sisyphus::Common->new(PATH=>$testfolder);

my $sampleSheet = $sisyphus->readSampleSheet();
my $noOfSamples = $sisyphus->samplesPerLane();
my $numLanes = $sisyphus->laneCount();
my $result;
my @testCases = ("Stats_ok", "Stats_revcomp", "Stats_switched", "Stats_comp", "Stats_rev", "Stats_readerror", "Stats_mismatch", "Stats_switchedrevcomp");

my @expectedResult = (0,1,1,1,1,0,0,1);

my @expectedOut = ("", "The reverse complement of index", "It appears that CTCTCTAT is present in Samplesheet among Index2",
                    "The complement of index", "The reverse of index", "contains read errors. OK!", "is one mismatch from being a correct index", 
                    "The reverse complement of index ATAGAGAG is present in SampleSheet among Index2.");

my @testDescription = ("Undetermined looks good", "Undetermined contains reverse complement of provided index",
                        "Undetermined contains i7 index that should be i5", "Undetermined contains complement of provided index",
                        "Undetermined contains reverse of provided index", "Undetermined contains index with read errors", 
                        "Undetermined contains index one mismatch from being provided index", "Undetermined contains i7 index that should be i5 and is reverse complemented"); 
                     
for my $testNo (0 .. 7){
    open (my $LOG, '>', "$testfolder/log.txt");
    select $LOG;
    $result = checkIndices($sisyphus, "$testfolder/$testCases[$testNo]", $noOfSamples, $numLanes, 0);
    close $LOG;
    ok($result == $expectedResult[$testNo] && checkLog("log.txt",$expectedOut[$testNo]), $testDescription[$testNo]);
}

sub checkLog{
    my $log = shift;
    my $expectedOutput = shift; 
    open my $fh, '<', "$testfolder/$log" or die "Could not open $log!\n";
    my $lineOK = 0;
    while (my $line = <$fh>){
        if ($line =~ $expectedOutput){
            $lineOK = 1;
        }
    }

    close $fh;
    return $lineOK;
}

END{
    system("rm $testfolder/log.txt");
}

done_testing();
