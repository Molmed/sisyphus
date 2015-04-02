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
my $testFolder = $FindBin::Bin . '/miseq_qc';

my $qcFile = $FindBin::Bin . '/qc_files/sisyphus_override_pooling_requirement_qc.xml';
my $qcFileOrg  = $FindBin::Bin . '/qc_files/sisyphus_meet_requirement_qc.xml';

system("mkdir -p /tmp/sisyphus/$$/") == 0
  or die "Failed to create temporary dir /tmp/sisyphus/$$/ $!";

#Create temp folders
system("cp -a $testFolder /tmp/sisyphus/$$") == 0
  or die "Failed to copy testdata to /tmp/sisyphus/$$/ $!";
$testFolder = "/tmp/sisyphus/$$/" . basename($testFolder);
system("cp $qcFile $testFolder/") == 0
  or die "Failed to copy sisyphus_override_pooling_requirement_qc.xml to $testFolder/";
system("cp $qcFileOrg $testFolder/") == 0
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
my ($qcResult,$warnings) = $qc->validateSequenceRun($sis,"$testFolder/quickReport_override_not_enough_data_for_sample.txt");
ok($qcResult->{'1'}->{'1'}->{'sampleFraction'}->{'a1r2-4w'}->{'res'} eq "4.975", "Not enough data for sample");
ok($warnings->{'1'}->{'1'}->{'sampleFraction'}->{'a1r2-4w'}->{'res'} eq "4.975", "Not enough data for sample");
$qc->loadQCRequirement("$testFolder/sisyphus_override_pooling_requirement_qc.xml");
($qcResult,$warnings) = $qc->validateSequenceRun($sis,"$testFolder/quickReport_override_not_enough_data_for_sample.txt");
ok(!defined($qcResult), "Override pooling requirement");
ok(!defined($warnings), "Override pooling requirement");


done_testing();
END{
#    system("rm -rf /tmp/sisyphus/$$");
}
