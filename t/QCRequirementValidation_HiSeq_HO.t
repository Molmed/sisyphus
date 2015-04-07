#!/usr/bin/perl -w

use strict;
use warnings;
use Test::More;
use Test::Exception;

use File::Basename;
use FindBin;                # Find the script location
use lib "$FindBin::Bin/../lib";# Add the script libdir to libs

# Verify module can be included via "use" pragma
BEGIN { use_ok('Molmed::Sisyphus::QCRequirementValidation') };

# Verify module can be included via "require" pragma
require_ok( 'Molmed::Sisyphus::QCRequirementValidation' );
require_ok( 'Molmed::Sisyphus::Common' );

# Set up a temporary runfolder for testing
my $testFolder = $FindBin::Bin . '/hiseq_ho_qc';

my $qcFile = $FindBin::Bin . '/qc_files/sisyphus_meet_requirement_qc.xml'; 

system("mkdir -p /tmp/sisyphus/$$/") == 0
  or die "Failed to create temporary dir /tmp/sisyphus/$$/ $!";

#Create temp folders
system("cp -a $testFolder /tmp/sisyphus/$$") == 0
  or die "Failed to copy testdata to /tmp/sisyphus/$$/ $!";
$testFolder = "/tmp/sisyphus/$$/" . basename($testFolder);
system("cp $qcFile $testFolder/") == 0
  or die "Failed to copy sisyphus_meet_requirement_qc.xml to $testFolder/";


#Create objects used for MiSeq QC validation
my $sis = Molmed::Sisyphus::Common->new(PATH=>$testFolder);
isa_ok($sis, 'Molmed::Sisyphus::Common', "New sisyphus object with runfolder: " . $sis->PATH);
#Load run parameters
$sis->runParameters();
##Create QC validation object
my $qc = Molmed::Sisyphus::QCRequirementValidation->new();
isa_ok($qc, 'Molmed::Sisyphus::QCRequirementValidation', "New qcValidation object created");
##Loading QC requirement
$qc->loadQCRequirement("$testFolder/sisyphus_meet_requirement_qc.xml");

ok(!defined($qc->validateSequenceRun($sis,"$testFolder/quickReport.txt")), "QC returned ok");
my ($result, $warning) = $qc->validateSequenceRun($sis,"$testFolder/quickReport_not_enough_clusters.txt");
ok($result->{'5'}->{'1'}->{'numberOfCluster'}->{'res'} eq 139 , "Not enough clusters");
($result, $warning) = $qc->validateSequenceRun($sis,"$testFolder/quickReport_to_many_undefined.txt");
ok($result->{'6'}->{'1'}->{'unidentified'}->{'res'} eq "7.7", "To many undefined");
($result, $warning) = $qc->validateSequenceRun($sis,"$testFolder/quickReport_to_high_errorRate.txt");
ok($result->{'4'}->{'2'}->{'errorRate'}->{'res'} eq "2.02", "To high error rate");
($result, $warning) = $qc->validateSequenceRun($sis,"$testFolder/quickReport_not_enough_data_for_sample.txt");
ok($result->{'1'}->{'1'}->{'sampleFraction'}->{'AID_H_JM_SpA_CO105_tag76'}->{'res'} eq "8.717", "Not enough data for sample");
($result, $warning) = $qc->validateSequenceRun($sis,"$testFolder/quickReport_to_low_q30_yield.txt");
ok($result->{'5'}->{'2'}->{'q30'}->{'res'} eq "10.99", "To low Q30 yield");


done_testing();
END{
#    system("rm -rf /tmp/sisyphus/$$");
}
