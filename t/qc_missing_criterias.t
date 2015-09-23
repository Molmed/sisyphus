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

my $qcFileNOC = $FindBin::Bin . '/qc_files/sisyphus_missing_number_of_clusters_requirement_qc.xml';
my $qcFileU = $FindBin::Bin . '/qc_files/sisyphus_missing_unidentified_requirement_qc.xml';
my $qcFileQ30 = $FindBin::Bin . '/qc_files/sisyphus_missing_q30_requirement_qc.xml';
my $qcFileER = $FindBin::Bin . '/qc_files/sisyphus_missing_errorRate_requirement_qc.xml';

my $qcFileOrg  = $FindBin::Bin . '/../sisyphus_qc.xml';

system("mkdir -p /tmp/sisyphus/$$/") == 0
  or die "Failed to create temporary dir /tmp/sisyphus/$$/ $!";
my $confFile  = $FindBin::Bin . '/../sisyphus.yml';
system("cp $confFile $testFolder/") == 0
  or die "Failed to copy sisyphus.yml to $testFolder/";


#Create temp folders
system("cp -a $testFolder /tmp/sisyphus/$$") == 0
  or die "Failed to copy testdata to /tmp/sisyphus/$$/ $!";
$testFolder = "/tmp/sisyphus/$$/" . basename($testFolder);
my $confFile  = $FindBin::Bin . '/../sisyphus.yml';
system("cp $confFile $testFolder/") == 0
  or die "Failed to copy sisyphus.yml to $testFolder/";


system("cp $qcFileNOC $testFolder/sisyphus_mNOC_qc.xml") == 0
  or die "Failed to copy sisyphus_mNOC_qc.xml to $testFolder/";
system("cp $qcFileU $testFolder/sisyphus_mU_qc.xml") == 0
  or die "Failed to copy sisyphus_mU_qc.xml to $testFolder/";
system("cp $qcFileQ30 $testFolder/sisyphus_mQ30_qc.xml") == 0
  or die "Failed to copy sisyphus_mQ30_qc.xml to $testFolder/";
system("cp $qcFileER $testFolder/sisyphus_mER_qc.xml") == 0
  or die "Failed to copy sisyphus_mER_qc.xml to $testFolder/";


#Create objects used for MiSeq QC validation
my $sis = Molmed::Sisyphus::Common->new(PATH=>$testFolder);
$sis->runParameters();
isa_ok($sis, 'Molmed::Sisyphus::Common', "New sisyphus object with runfolder: " . $sis->PATH);
#Load run parameters
$sis->runParameters();
##Create QC validation object
my $qc = Molmed::Sisyphus::QCRequirementValidation->new();
isa_ok($qc, 'Molmed::Sisyphus::QCRequirementValidation', "New qcValidation object created");
##Loading QC requirement
$qc->loadQCRequirement("$testFolder/sisyphus_mNOC_qc.xml");
my ($result, $warning) = $qc->validateSequenceRun($sis,"$testFolder/quickReport.txt");
ok($result == $qc->SEQUENCED_NUMBER_OF_CLUSTERS_NOT_FOUND, "Passing missing number of clusters test");

$qc->loadQCRequirement("$testFolder/sisyphus_mU_qc.xml");
($result, $warning) = $qc->validateSequenceRun($sis,"$testFolder/quickReport.txt");
ok($result == $qc->SEQUENCED_UNIDENTIFIED_NOT_FOUND, "Passing missing number of unidentified test");

$qc->loadQCRequirement("$testFolder/sisyphus_mQ30_qc.xml");
($result, $warning) = $qc->validateSequenceRun($sis,"$testFolder/quickReport.txt");
ok($result == $qc->SEQUENCED_Q30_NOT_FOUND, "Passing missing Q30 test");

$qc->loadQCRequirement("$testFolder/sisyphus_mER_qc.xml");
($result, $warning) = $qc->validateSequenceRun($sis,"$testFolder/quickReport.txt");
ok($result == $qc->SEQUENCED_ERROR_RATE_NOT_FOUND, "Passing missing error rate test");

done_testing();
END{
#    system("rm -rf /tmp/sisyphus/$$");
}
