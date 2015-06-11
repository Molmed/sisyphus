#!/usr/bin/perl -w

use strict;
use warnings;
use Test::More;
use Test::Exception;

use File::Basename;
use FindBin;                # Find the script location
use lib "$FindBin::Bin/../lib";# Add the script libdir to libs

# Verify module can be included via "use" pragma
BEGIN { use_ok('Molmed::Sisyphus::Common') };

# Verify module can be included via "require" pragma
require_ok( 'Molmed::Sisyphus::Common' );

# Set up a temporary runfolder for testing
my $testfolder1 = $FindBin::Bin . '/120224_SN866_0134_BC0H34ACXX';

system("mkdir -p /tmp/sisyphus/$$/") == 0
  or die "Failed to create temporary dir /tmp/sisyphus/$$/ $!";
system("cp -a $testfolder1 /tmp/sisyphus/$$") == 0
  or die "Failed to copy testdata to /tmp/sisyphus/$$/ $!";
$testfolder1 = "/tmp/sisyphus/$$/" . basename($testfolder1);

# Test creating a new object without params
dies_ok {Molmed::Sisyphus::Common->new()} "New Common object without params died as expected ";

# Test creating a new object with path only
my $sis = Molmed::Sisyphus::Common->new(PATH=>$testfolder1);
isa_ok($sis, 'Molmed::Sisyphus::Common', "New Common object with only path");

# Test creating a new object with params
$sis = Molmed::Sisyphus::Common->new(PATH=>$testfolder1,THREADS=>8,VERBOSE=>1,DEBUG=>1);
isa_ok($sis, 'Molmed::Sisyphus::Common', "New QStat object with params");
is($sis->PATH, $testfolder1, "Path set");

# Test SampleSheet fixup
ok($sis->fixSampleSheet("$testfolder1/samplesheet1")==0, "Samplesheet1 has duplicate tags");
ok($sis->fixSampleSheet("$testfolder1/samplesheet2")==0, "Samplesheet2 has wrong FCID");
ok($sis->fixSampleSheet("$testfolder1/samplesheet3")==1, "Samplesheet3 is ok");
ok(-e "$testfolder1/samplesheet3.org.1", "Samplesheet3 was modified");
ok($sis->fixSampleSheet("$testfolder1/samplesheet3")==1, "Samplesheet3 is still ok");

ok($sis->excludeLane(1), "Excluded lane 1");
ok($sis->excludeLane(2), "Excluded lane 2");
ok($sis->excludeLane(1), "Excluded lane 1");
ok($sis->excludeLane(2), "Excluded lane 2");
ok($sis->excludeLane(3), "Excluded lane 3");
ok($sis->excludeLane(3), "Excluded lane 3");

#
# Test MD5 sum functions and file locking
#

opendir(DH, "$testfolder1") or die "Couldn't open dir: $testfolder1";
my @dirFiles = grep ! /^\./, readdir(DH); #ignore hidden files
closedir(DH);

my $md5;
my @children;
my $numberOfFiles = @dirFiles;
$sis->mkpath("$testfolder1/MD5", 2770);

foreach my $file (@dirFiles) {
    my $pid = fork();
    if ($pid) {
        #parent
        push @children, $pid;
    }
    elsif ($pid==0) {
        #child
        $md5 = $sis->getMd5("$testfolder1/$file", -noCache=>1);
        $sis->saveMd5("$testfolder1/$file", $md5);
        exit 0;
    }
    else {
        die "Couldn't fork: $!\n";
    }
}

foreach my $pid ( @children ) {
    waitpid($pid, 0);
}

open my $fh, '<', "$testfolder1/MD5/sisyphus.md5" or die "Could not open sisyphus.md5!\n";
my $lineOK = 0;
while (my $line = <$fh>){
    if ($line =~ m/^[a-f0-9]{32}\h\h120224_SN866_0134_BC0H34ACXX\.*/g){
        $lineOK++;    
    }
}
close $fh;

ok($lineOK == $numberOfFiles, "MD5 sums have been written in parallel");

done_testing();

# Clean up before exit
END{
#    system("rm -rf /tmp/sisyphus/$$");
}
