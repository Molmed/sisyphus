#!/usr/bin/perl -w

use strict;
use warnings;
use Test::More;
use Test::Exception;

use File::Basename;
use FindBin;                # Find the script location
use File::Find;

my $testfolder = $FindBin::Bin . '/index_check_files';

my $sisyphusPath = $FindBin::Bin;

$sisyphusPath =~ s/sisyphus\/t/sisyphus/g;

my $checkIndicesPath = "";

find(\&pathforCheckIndices, $sisyphusPath);

my $perlbrew;

sub pathforCheckIndices{
    my $file = $_;
    if ($file =~ /checkIndices.pl/){
        $checkIndicesPath = $File::Find::name; 
    }
    if ($checkIndicesPath =~ /\/home\/travis/){
        
        $perlbrew = split(":", $ENV{'PERLBREW_PATH'})[1];

        $checkIndicesPath = "$perlbrew/perl $checkIndicesPath";
    }
}



my $result1 = system("$checkIndicesPath -runfolder $testfolder -demuxSummary $testfolder/Stats_ok > $testfolder/log1.txt");
my $result2 = system("$checkIndicesPath -runfolder $testfolder -demuxSummary $testfolder/Stats_revcomp > $testfolder/log2.txt");
my $result3 = system("$checkIndicesPath -runfolder $testfolder -demuxSummary $testfolder/Stats_switched > $testfolder/log3.txt");
my $result4 = system("$checkIndicesPath -runfolder $testfolder -demuxSummary $testfolder/Stats_comp > $testfolder/log4.txt");
my $result5 = system("$checkIndicesPath -runfolder $testfolder -demuxSummary $testfolder/Stats_rev > $testfolder/log5.txt");
my $result6 = system("$checkIndicesPath -runfolder $testfolder -demuxSummary $testfolder/Stats_readerror > $testfolder/log6.txt");
my $result7 = system("$checkIndicesPath -runfolder $testfolder -demuxSummary $testfolder/Stats_mismatch > $testfolder/log7.txt");
my $result8 = system("$checkIndicesPath -runfolder $testfolder -demuxSummary $testfolder/Stats_switchedrevcomp > $testfolder/log8.txt");

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

# Results are divided by 256 because system() returns exit value * 256
ok($result1/256 == 0 && checkLog("log1.txt","Undetermined indices OK!"), "Undetermined looks good");
ok($result2/256 == 1 && checkLog("log2.txt","The reverse complement of index"), "Undetermined contains reverse complement of provided index");
ok($result3/256 == 1 && checkLog("log3.txt","It appears that CTCTCTAT is present in Samplesheet among Index2"), "Undetermined contains i7 index that should be i5");
ok($result4/256 == 1 && checkLog("log4.txt","The complement of index"), "Undetermined contains complement of provided index");
ok($result5/256 == 1 && checkLog("log5.txt","The reverse of index"), "Undetermined contains reverse of provided index");
ok($result6/256 == 0 && checkLog("log6.txt","contains read errors. OK!"), "Undetermined contains index with read errors.");
ok($result7/256 == 0 && checkLog("log7.txt","is one mismatch from being a correct index"), "Undetermined contains index one mismatch from being provided index.");
ok($result8/256 == 1 && checkLog("log8.txt","The reverse complement of index ATAGAGAG is present in SampleSheet among Index2."), "Undetermined contains i7 index that should be i5 and is reverse complemented");

END{
    system("rm $testfolder/log*.txt");
}

done_testing();
