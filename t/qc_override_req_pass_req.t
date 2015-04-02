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

my $qcFilePass = $FindBin::Bin . '/qc_files/sisyphus_override_requirement_pass_qc.xml';
my $qcFileWarning = $FindBin::Bin . '/qc_files/sisyphus_override_requirement_warning_qc.xml';
my $qcFileOrg  = $FindBin::Bin . '/qc_files/sisyphus_meet_requirement_qc.xml';

system("mkdir -p /tmp/sisyphus/$$/") == 0
  or die "Failed to create temporary dir /tmp/sisyphus/$$/ $!";

#Create temp folders
system("cp -a $testFolder /tmp/sisyphus/$$") == 0
  or die "Failed to copy testdata to /tmp/sisyphus/$$/ $!";
$testFolder = "/tmp/sisyphus/$$/" . basename($testFolder);
system("cp $qcFilePass $testFolder/") == 0
  or die "Failed to copy sisyphus_override_requirement_pass_qc.xml to $testFolder/";
system("cp $qcFileWarning $testFolder/") == 0
  or die "Failed to copy sisyphus_override_requirement_warning_qc.xml to $testFolder/";
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
my ($qcResult, $warning) = $qc->validateSequenceRun($sis,"$testFolder/quickReport_override_qc_req.txt");

ok($qcResult->{'1'}->{'1'}->{'numberOfCluster'}->{'res'} eq "139", "To few number of clusters");
ok($qcResult->{'1'}->{'2'}->{'numberOfCluster'}->{'res'} eq "139", "To few number of clusters");
ok($qcResult->{'1'}->{'1'}->{'unidentified'}->{'res'} eq "6.0", "To much unidentified");

ok($qcResult->{'2'}->{'1'}->{'q30'}->{'res'} eq "10", "To low Q30 yield");
ok($qcResult->{'2'}->{'2'}->{'q30'}->{'res'} eq "10", "To low Q30 yield");

ok($qcResult->{'3'}->{'1'}->{'errorRate'}->{'res'} eq "2.1", "To high errorRate");

ok($qcResult->{'4'}->{'2'}->{'unidentified'}->{'res'} eq "7.5", "To much unidentified");

ok($qcResult->{'5'}->{'2'}->{'unidentified'}->{'res'} eq "7.7", "To much unidentified");

ok($qcResult->{'7'}->{'2'}->{'sampleFraction'}->{'SLE_H_FF_pool140_tag3'}->{'res'} == 0, "Found sample without data");

ok($qcResult->{'8'}->{'2'}->{'sampleFraction'}->{'SLE_H_FF_pool141_tag12'}->{'res'} == 0, "Found sample without data");

$qc = Molmed::Sisyphus::QCRequirementValidation->new();
$qc->loadQCRequirement("$testFolder/sisyphus_override_requirement_pass_qc.xml");
($qcResult, $warning) = $qc->validateSequenceRun($sis,"$testFolder/quickReport_override_qc_req.txt");
#Passing override
ok(!defined($qcResult->{'1'}->{'1'}->{'numberOfCluster'}->{'res'}), "Pass: To few number of clusters overrided");
ok(!defined($qcResult->{'1'}->{'2'}->{'numberOfCluster'}->{'res'}), "Pass: To few number of clusters overrided");
ok(!defined($qcResult->{'1'}->{'1'}->{'unidentified'}->{'res'}), "Pass: To much unidentified overrided");

ok(!defined($qcResult->{'2'}->{'1'}->{'q30'}->{'res'}), "Pass: To low Q30 yield overrided");
ok(!defined($qcResult->{'2'}->{'2'}->{'q30'}->{'res'}), "Pass: To low Q30 yield overrided");

ok(!defined($qcResult->{'3'}->{'1'}->{'errorRate'}->{'res'}), "Pass: To high errorRate overrided");

ok(!defined($qcResult->{'4'}->{'2'}->{'unidentified'}->{'res'}), "Pass: To much unidentified overrided");

ok(!defined($qcResult->{'5'}->{'2'}->{'unidentified'}->{'res'}), "Pass: To much unidentified overrided");

ok(!defined($qcResult->{'7'}->{'2'}->{'sampleFraction'}->{'SLE_H_FF_pool140_tag3'}->{'res'}), "Pass: Found sample without data overrided");

ok(!defined($qcResult->{'8'}->{'2'}->{'sampleFraction'}->{'SLE_H_FF_pool141_tag12'}->{'res'}), "Pass: Found sample without data overrided");

ok($qcResult->{'2'}->{'2'}->{'unidentified'}->{'res'} eq "3.0", "Pass: Lowering pass for unidentified");
ok($qcResult->{'3'}->{'1'}->{'q30'}->{'res'} eq "21.2", "Pass: Increasing Q30 yield req");
ok($qcResult->{'5'}->{'2'}->{'numberOfCluster'}->{'res'} eq "217", "Pass: Increasing number of req cluster");
ok($qcResult->{'6'}->{'1'}->{'errorRate'}->{'res'} eq "0.32", "Pass: Lowering allowed error rate");

#Warning override
$qc = Molmed::Sisyphus::QCRequirementValidation->new();
$qc->loadQCRequirement("$testFolder/sisyphus_override_requirement_warning_qc.xml");
($qcResult, $warning) = $qc->validateSequenceRun($sis,"$testFolder/quickReport_override_qc_req.txt");

ok(!defined($qcResult->{'1'}->{'1'}->{'numberOfCluster'}->{'res'}), "Pass: To few number of clusters overrided");
ok($warning->{'1'}->{'1'}->{'numberOfCluster'}->{'res'} eq "139", "Warning: To few number of clusters overrided");
ok(!defined($qcResult->{'1'}->{'2'}->{'numberOfCluster'}->{'res'}), "To few number of clusters overrided");
ok($warning->{'1'}->{'2'}->{'numberOfCluster'}->{'res'} eq "139", "Warning: To few number of clusters overrided");
ok(!defined($qcResult->{'1'}->{'1'}->{'unidentified'}->{'res'}), "To much unidentified overrided");

ok(!defined($qcResult->{'2'}->{'1'}->{'q30'}->{'res'}), "Pass: To low Q30 yield overrided");
ok($warning->{'2'}->{'1'}->{'q30'}->{'res'} eq "10" , "Warning: To low Q30 yield overrided");
ok(!defined($qcResult->{'2'}->{'2'}->{'q30'}->{'res'}), "Pass: To low Q30 yield overrided");
ok($warning->{'2'}->{'2'}->{'q30'}->{'res'} eq "10" , "Warning: To low Q30 yield overrided");

ok(!defined($qcResult->{'3'}->{'1'}->{'errorRate'}->{'res'}), "Pass: To high errorRate overrided");
ok($warning->{'3'}->{'1'}->{'errorRate'}->{'res'} eq "2.1" , "Warning: To high errorRate overrided");

ok(!defined($qcResult->{'4'}->{'2'}->{'unidentified'}->{'res'}), "Pass: To much unidentified overrided");
ok($warning->{'4'}->{'2'}->{'unidentified'}->{'res'} eq "7.5", "Warning: To much unidentified overrided");

ok(!defined($qcResult->{'5'}->{'2'}->{'unidentified'}->{'res'}), "Pass: To much unidentified overrided");
ok(!defined($warning->{'5'}->{'2'}->{'unidentified'}->{'res'}), "Warning: To much unidentified overrided");

ok(!defined($qcResult->{'7'}->{'2'}->{'sampleFraction'}->{'SLE_H_FF_pool140_tag3'}->{'res'}), "Pass: Found sample without data overrided");
ok($qcResult->{'8'}->{'2'}->{'sampleFraction'}->{'SLE_H_FF_pool141_tag12'}->{'res'} eq "0" , "Warning: Found sample without data overrided");

done_testing();
END{
#    system("rm -rf /tmp/sisyphus/$$");
}

