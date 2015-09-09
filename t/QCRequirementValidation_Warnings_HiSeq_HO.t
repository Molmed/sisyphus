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

my $qcFile = $FindBin::Bin . '/qc_files/sisyphus_requirement_warning_qc.xml';

system("mkdir -p /tmp/sisyphus/$$/") == 0
  or die "Failed to create temporary dir /tmp/sisyphus/$$/ $!";

#Create temp folders
system("cp -a $testFolder /tmp/sisyphus/$$") == 0
  or die "Failed to copy testdata to /tmp/sisyphus/$$/ $!";
$testFolder = "/tmp/sisyphus/$$/" . basename($testFolder);
system("cp $qcFile $testFolder/") == 0
  or die "Failed to copy sisyphus_qc.xml to $testFolder/";
my $confFile  = $FindBin::Bin . '/../sisyphus.yml';
system("cp $confFile $testFolder/") == 0
  or die "Failed to copy sisyphus.yml to $testFolder/";


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
$qc->loadQCRequirement("$testFolder/sisyphus_requirement_warning_qc.xml");

#ok(!defined($qc->validateSequenceRun($sis,"$testFolder/quickReport.txt")), "QC returned ok");
my ($result, $warning) = $qc->validateSequenceRun($sis,"$testFolder/quickReport_warning.txt");
ok(!defined($result->{'5'}->{'1'}->{'numberOfCluster'}->{'res'}), "Pass:  Enough clusters");
ok($warning->{'5'}->{'1'}->{'numberOfCluster'}->{'res'} eq 139 , "Warning: Not enough clusters");
ok(!defined($result->{'6'}->{'1'}->{'unidentified'}->{'res'}), "Pass: Not to many undefined");
ok($warning->{'6'}->{'1'}->{'unidentified'}->{'res'} eq "7.7", "Warning: To many undefined");
ok(!defined($result->{'4'}->{'2'}->{'errorRate'}->{'res'}), "To high error rate");
ok($warning->{'4'}->{'2'}->{'errorRate'}->{'res'} eq "2.02", "To high error rate");
ok(!defined($result->{'8'}->{'2'}->{'sampleFraction'}->{'AID_H_JM_SpA_CO105_tag76'}->{'res'}), "Pass: Turn of pooling requirement");
ok($warning->{'8'}->{'2'}->{'sampleFraction'}->{'AID_H_JM_SpA_CO105_tag76'}->{'res'} eq "8.717", "Warning: Not enough data for sample");
ok(!defined($result->{'5'}->{'2'}->{'q30'}->{'res'}), "To low Q30 yield");
ok($warning->{'5'}->{'2'}->{'q30'}->{'res'} eq "10.99", "To low Q30 yield");

done_testing();
END{
#    system("rm -rf /tmp/sisyphus/$$");
}
