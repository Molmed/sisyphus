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

my $qcFile = $FindBin::Bin . '/qc_files/sisyphus_no_errorRate_allowed_qc.xml';

system("mkdir -p /tmp/sisyphus/$$/") == 0
  or die "Failed to create temporary dir /tmp/sisyphus/$$/ $!";

#Create temp folders
system("cp -a $testFolder /tmp/sisyphus/$$") == 0
  or die "Failed to copy testdata to /tmp/sisyphus/$$/ $!";
$testFolder = "/tmp/sisyphus/$$/" . basename($testFolder);
system("cp $qcFile $testFolder/") == 0
  or die "Failed to copy sisyphus_no_errorRate_allowed_qc.xml to $testFolder/";


#Create objects used for MiSeq QC validation
my $sis = Molmed::Sisyphus::Common->new(PATH=>$testFolder);
isa_ok($sis, 'Molmed::Sisyphus::Common', "New sisyphus object with runfolder: " . $sis->PATH);
#Load run parameters
$sis->runParameters();
##Create QC validation object
my $qc = Molmed::Sisyphus::QCRequirementValidation->new();
isa_ok($qc, 'Molmed::Sisyphus::QCRequirementValidation', "New qcValidation object created");
##Loading QC requirement
$qc->loadQCRequirement("$testFolder/sisyphus_no_errorRate_allowed_qc.xml");
my ($result, $warning) = $qc->validateSequenceRun($sis,"$testFolder/quickReport_no_errorRate.txt");
ok(!defined($result), "Passing missing errorRate test");


done_testing();
END{
#    system("rm -rf /tmp/sisyphus/$$");
}
