#!/usr/bin/perl -w

use FindBin;                # Find the script location
use lib "$FindBin::Bin/lib";# Add the script libdir to libs

use strict;
use POSIX ":sys_wait_h";
use Getopt::Long;
use Pod::Usage;
use File::Basename;

use Molmed::Sisyphus::Common;

=pod

=head1 NAME

sisyphus.pl - Watch a runfolder and start processing it when it is completed

=head1 SYNOPSIS

 sisyphus.pl -help|-man
 sisyphus.pl -runfolder <runfolder> [-debug -noexec]

=head1 OPTIONS

=over 4

=item -h|-help

prints out a brief help text.

=item -m|-man

Opens the manpage.

=item -runfolder

The runfolder to process.

=item -noexec

Do not execute the generated batchscript

=item -nowait

Skip paranoid wait for runfolder completion. Just continue if RTAComplete.txt exists.

=item -force

Continue even if data is missing. Adds --ignore-missing-stats, --ignore-missing-bcl, --ignore-missing-control to bcl2fastq conversion.

=item -debug

Print debugging information

=back

The rest of the configuration is read from RUNFOLDER/sisyphus.yml. See example included in the sisyphus directory.

=head1 DESCRIPTION

Sisyphus.pl waits for completion of a runfolder and then generates and executes a shell script
for post processing the data.

The postprocessing includes the following steps:

=over 4

=item Conversion from bcl to fastq, including demultiplexing

=item Extraction of summary data to a separate folder

=item Transfer of selected files to UPPMAX

=item Fastq statistics collection

=item Extraction of projects for data delivery

=item Archiving

=back

=cut

my $rfPath = undef;
my $exec = 1;
my $wait = 1;
my $force = 0;
our $debug = 0;
my $threads = `cat /proc/cpuinfo |grep "^processor"|wc -l`;
$threads = $threads/2;

my ($help,$man) = (0,0);

GetOptions('help|?'=>\$help,
	   'man'=>\$man,
	   'runfolder=s' => \$rfPath,
	   'exec!' => \$exec,
	   'wait!' => \$wait,
	   'force!' => \$force,
	   'debug' => \$debug,
	   'j=i' => \$threads,
	  ) or pod2usage(-verbose => 0);
pod2usage(-verbose => 1)  if ($help);
pod2usage(-verbose => 2)  if ($man);

unless(defined $rfPath && -e $rfPath){
    print STDERR "Runfolder not specified or does not exist\n";
    pod2usage(-verbose => 1);
    exit;
}

# Pass debug to scripts with this flag
my $debugFlag='';
if($debug){
    $debugFlag = '-debug';
}

my $sisyphus = Molmed::Sisyphus::Common->new(PATH=>$rfPath, DEBUG=>$debug);
$rfPath = $sisyphus->PATH;
my $rfName = basename($rfPath);
my $rfRoot = dirname($rfPath);

# Set defaults
my $rHost = "biologin.uppmax.uu.se";
my $rPath = "/bubo/nobackup/a2009002/runfolders";
my $oPath = "/bubo/nobackup/a2009002/OUTBOX";
my $aHost = "biologin.uppmax.uu.se";
my $aPath = "/bubo/proj/a2009002/";
my $sHost = "localhost";
my $sPath = dirname($rfPath) . '/summaries';
my $uProj = "a2009002";
my $fastqPath = undef;
my $mismatches = '1:1:1:1:1:1:1:1';

# Read the sisyphus configuration and override the defaults
my $config = $sisyphus->readConfig();

# Setup scratch/fastq directory
if(defined $config->{FASTQ_PATH}){
    $fastqPath = "$config->{FASTQ_PATH}/$rfName";
    $sisyphus->mkpath($fastqPath);
    if($sisyphus->df($fastqPath) < 300e9 ){
	die "Too little space on fastq device $fastqPath";
    }
}elsif(-d "/data/scratch" && $sisyphus->df("/data/scratch") > 300e9){
    $fastqPath = "/data/scratch/$rfName";
    $sisyphus->mkpath($fastqPath);
}else{
    $fastqPath = "$rfPath";
}


if(defined $config->{REMOTE_HOST}){
    $rHost = $config->{REMOTE_HOST};
}
if(defined $config->{REMOTE_PATH}){
    $rPath = $config->{REMOTE_PATH};
}
if(defined $config->{OUTBOX_PATH}){
    $oPath = $config->{OUTBOX_PATH};
}
if(defined $config->{ARCHIVE_HOST}){
    $aHost = $config->{ARCHIVE_HOST};
}
if(defined $config->{ARCHIVE_PATH}){
    $aPath = $config->{ARCHIVE_PATH};
}
if(defined $config->{SUMMARY_HOST}){
    $sHost = $config->{SUMMARY_HOST};
}
if(defined $config->{SUMMARY_PATH}){
    $sPath = $config->{SUMMARY_PATH};
}
if(defined $config->{UPPNEX_PROJECT}){
    $uProj = $config->{UPPNEX_PROJECT};
}

# Strip trailing slashes from paths
$rPath =~ s:/*$::;
$oPath =~ s:/*$::;
$aPath =~ s:/*$::;
$sPath =~ s:/*$::;

# Set combined paths
my $targetPath = "$rHost:$rPath";
my $summaryPath = "$sHost:$sPath";
my $archivePath = "$aHost:$aPath";
my $rBin = "$rPath/$rfName/Sisyphus";

if($debug){
    print "\$rHost => $rHost\n";
    print "\$rPath => $rPath\n";
    print "\$sHost => $sHost\n";
    print "\$sPath => $sPath\n";
    print "\$aHost => $aHost\n";
    print "\$aPath => $aPath\n";
    print "\$oPath => $oPath\n";
    print "\$rfName => $rfName\n";

};

print STDERR "All set. Checking for runfolder completion!\n\n";

my $complete = 0;

until($complete||$force){
    $complete = $sisyphus->complete();
    unless($complete){
	print STDERR "Not complete. Going to sleep\n" if $debug;
	sleep 600;
	print STDERR "Trying again\n" if $debug;
    }
}

if($complete){
    print STDERR "Runfolder complete, checking for SampleSheet.csv\n";
}elsif($force){
    print STDERR "Runfolder NOT complete, continue anyway!\n";
}

$complete = 0;
until($complete){
    if(-e "$rfPath/SampleSheet.csv"){
	# Check sanity of sample sheet
	$complete = $sisyphus->fixSampleSheet("$rfPath/SampleSheet.csv");
	print "SampleSheet has errors. Please fix it. You do not have to abort!\nJust fix the file and the script will continue after sleeping 10 minutes from now.\n" unless($complete);
    }else{
	print "SampleSheet.csv is missing\n";
	$complete=0;
    }
    sleep 600 unless($complete);
}

die unless($complete);

print STDERR "Runfolder $rfPath ready to go!\n";

# Sleep 30 minutes as an additional precaution
sleep 1800 if($wait);

my $runInfo = $sisyphus->getRunInfo() || die "Failed to read RunInfo.xml from $rfPath\n";

# This (or rather the object method) will need changing when we have an example of a dual-index run
my $readMask = $sisyphus->createReadMask() || die "Failed to generate readMask";
my $posFormat = $sisyphus->positionsFormat();

# Identify tiles with too high error for exclusion
my $excludedTiles = $sisyphus->excludeTiles();
my @incTiles;
my @excTiles;
foreach my $lane (1..$sisyphus->laneCount){
    if(exists $excludedTiles->{$lane}){
	my $flowcellLayot = $runInfo->{xml}->{Run}->{FlowcellLayout};
	if(scalar(keys %{$excludedTiles->{$lane}}) == $runInfo->{tiles} + 2 ){ # There are two extra keys in the excludedTiles hash
	    # Exclude the whole lane
	    push @excTiles, "s_${lane}";
	    # And also add it to lanes that should not be delivered
	    $sisyphus->excludeLane($lane);
	}else{
	    for(my $surf=1; $surf<=$flowcellLayot->{SurfaceCount}; $surf++){
		for(my $swath=1; $swath<=$flowcellLayot->{SwathCount}; $swath++){
		    for(my $t=1; $t<=$flowcellLayot->{TileCount}; $t++){
			my $tile = sprintf("$surf$swath%02d", $t);
			if(exists $excludedTiles->{$lane}->{$tile}){
			    push @excTiles, "s_${lane}_$tile";
			}else{
			    push @incTiles, "s_${lane}_$tile";
			}
		    }
		}
	    }
	}
    }else{
	push @incTiles, "s_$lane";
    }
}

my $includeTiles = join ',', @incTiles;
my $ignore = '';
if($force){
    $ignore = '--ignore-missing-stats --ignore-missing-bcl --ignore-missing-control ';
}

# Create processing shellscript
open(my $scriptFh, '>', "$rfPath/sisyphus.sh") or die "Failed to create '$rfPath/sisyphus.sh':$!\n";
print $scriptFh <<EOF;
#!/bin/bash

PATH="$FindBin::Bin:$config->{CASAVA}:\$PATH"

check_errs()
{
  # Function. Parameter 1 is the return code
  # Para. 2 is text to display on failure.
  # Kill all child processes before exit.

  if [ "\${1}" -ne "0" ]; then
    echo "ERROR # \${1} : \${2}"
    for job in `jobs -p`
    do
	kill -9 \$job
    done
    exit \${1}
  fi
}

# Get Sisyphus version
echo -n "Sisyphus version: "
if [ -e "$FindBin::Bin/.git" ]; then
   git --git-dir $FindBin::Bin/.git describe
elif [ -e "$FindBin::Bin/SISYPHUS_VERSION" ]; then
   cat "$FindBin::Bin/SISYPHUS_VERSION"
else
   echo "unknown"
fi

# Run demultiplexing
cd $rfPath
check_errs \$? "Failed to cd to $rfPath"

echo "Setting up demultiplexing"

EOF

# Configure the per lane allowed barcode mismatch
if(exists $config->{MISMATCH}){
    my @mismatches = split /:/, $mismatches; # Init array with defaults
    foreach my $lane (keys %{$config->{MISMATCH}}){
        $mismatches[$lane-1]=$config->{MISMATCH}->{$lane};
    }
    $mismatches = join ':', @mismatches;
}

print $scriptFh <<EOF;
configureBclToFastq.pl --input-dir '$rfPath/Data/Intensities/BaseCalls' --output-dir '$fastqPath/Unaligned' --sample-sheet '$rfPath/SampleSheet.csv' --use-bases-mask '$readMask' --mismatches '$mismatches' ${ignore} --positions-format $posFormat --fastq-cluster-count 0 --tiles $includeTiles &> $rfPath/setupBclToFastq.err
check_errs \$? "configureBclToFastq.pl failed"

if [ ! -e "$rfPath/Unaligned" ]; then
   ln -s "$fastqPath/Unaligned" "$rfPath/Unaligned"
fi

EOF

if(@excTiles > 0){
    my $excludeTiles = join ',', @excTiles;
    print $scriptFh <<EOF;
echo "Setting up demultiplexing of excluded tiles"
configureBclToFastq.pl --input-dir '$rfPath/Data/Intensities/BaseCalls' --output-dir '$fastqPath/Excluded' --sample-sheet '$rfPath/SampleSheet.csv' --use-bases-mask '$readMask' --mismatches 1 --positions-format $posFormat --fastq-cluster-count 0 --tiles $excludeTiles &> $rfPath/setupBclToFastqExcluded.err
check_errs \$? "configureBclToFastq.pl for excluded tiles failed"

echo "Demultiplexing/Converting excluded tiles to FastQ"
cd '$fastqPath/Excluded'
check_errs \$? "Failed to cd to $fastqPath/Excluded"
make -j$threads &> BclToFastq.log
check_errs \$? "make failed in $fastqPath/Excluded"

if [ ! -e "$rfPath/Excluded" ]; then
   ln -s "$fastqPath/Excluded" "$rfPath/Excluded"
fi


EOF

}

print $scriptFh <<EOF;

echo "Demultiplexing/Converting to FastQ"
cd '$fastqPath/Unaligned'
check_errs \$? "Failed to cd to $fastqPath/Unaligned"
make -j$threads &> BclToFastq.log
check_errs \$? "make failed in $fastqPath/Unaligned"

# Copy $FindBin::Bin/ directory to the runfolder
# Both for archiving and usage at UPPMAX
if [ -e $rfPath/Sisyphus ]; then
    rm -rf $rfPath/Sisyphus
fi
echo -n "Copy $FindBin::Bin/ $rfPath/Sisyphus  "
cp -a $FindBin::Bin/ $rfPath/Sisyphus/
check_errs \$? "FAILED"
echo OK

# Save the sisyphus version
if [ -e "$rfPath/Sisyphus/.git" ]; then
   git --git-dir "$rfPath/Sisyphus/.git" describe > "$rfPath/Sisyphus/SISYPHUS_VERSION"
   check_errs \$? "Failed to get sisyphus version from $rfPath/Sisyphus/.git"
fi

# Transfer files to UPPMAX
cd $rfRoot
check_errs \$? "Failed to cd to $rfRoot"

# First make a list of all the files that will be transferred,
# without actually doing it, for use by the checksumming
rsync -vrktp --dry-run --chmod=Dg+sx,ug+w,o-rwx --prune-empty-dirs --include-from '$FindBin::Bin/hiseq.rsync' '$rfName' /tmp/ > '$rfName/rsync.log'

# Now do the actual transfer, loop until successful
rm -f $rfName/rsync-real.log
RSYNC_OK=1
SLEEP=300
until [ \$RSYNC_OK = 0 ]; do
    echo -n "rsync $rfPath $targetPath  "
    rsync -vrktp --chmod=Dg+sx,ug+w,o-rwx --prune-empty-dirs --include-from '$FindBin::Bin/hiseq.rsync' '$rfName' '$targetPath' >> '$rfName/rsync-real.log'
    RSYNC_OK=\$?
    if [ \$RSYNC_OK -gt 0 ]; then
       echo "FAILED will retry in \$SLEEP seconds"
       sleep \$SLEEP
    fi
done
check_errs \$RSYNC_OK "FAILED"
echo OK

echo "Setting permissions on remote copy"
PERM_OK=1
SLEEP=300
until [ \$PERM_OK = 0 ]; do
    echo -n "ssh $rHost chgrp -R --reference '$rPath' '$rPath/$rfName'; find '$rPath/$rfName' -type d -exec chmod 2770 {} \\; ";
    ssh $rHost "chgrp -R --reference '$rPath' '$rPath/$rfName'; find '$rPath/$rfName' -type d -exec chmod 2770 {} \\;"
    PERM_OK=\$?
    if [ \$PERM_OK -gt 0 ]; then
       echo "FAILED will retry in \$SLEEP seconds"
       sleep \$SLEEP
    fi
done
check_errs \$PERM_OK "FAILED"
echo OK

EOF

# Calculate md5 checksums of the transferred files
print $scriptFh <<EOF;
cd $rfRoot
check_errs \$? "Failed to cd to $rfRoot"
if [ ! -e "$rfPath/MD5" ]; then
    mkdir -m 2770 $rfPath/MD5
    check_errs \$? "Failed to mkdir $rfPath/MD5"
fi
echo -n "Checksumming files from $rfPath"
cat $rfPath/rsync.log | $FindBin::Bin/md5sum.pl $rfName > $rfPath/MD5/checksums.md5
check_errs \$? "FAILED"
echo OK

EOF

print $scriptFh <<EOF;

# And copy them to the target
RSYNC_OK=1
SLEEP=300
until [ \$RSYNC_OK = 0 ]; do
    echo -n "Copy checksums to $targetPath/$rfName/  "
    rsync -vrltp --chmod=Dg+sx,ug+w,o-rwx $rfPath/MD5 $targetPath/$rfName/
    RSYNC_OK=\$?
    if [ \$RSYNC_OK -gt 0 ]; then
       echo "FAILED will retry in \$SLEEP seconds"
       sleep \$SLEEP
    fi
done
check_errs \$RSYNC_OK "FAILED"
echo OK

# Extract the information to put in Seq-Summaries
cd $rfRoot
check_errs \$? "Failed to cd to $rfRoot"
RSYNC_OK=1
SLEEP=300
until [ \$RSYNC_OK = 0 ]; do
    echo -n "Extracting summary data  "
    rsync -vrktp --chmod=Dg+sx,ug+w,o-rwx --prune-empty-dirs --include-from  '$FindBin::Bin/summary.rsync' '$rfName' '$summaryPath' > '$rfPath/rsync.summary.log'
    RSYNC_OK=\$?
    if [ \$RSYNC_OK -gt 0 ]; then
       echo "FAILED will retry in \$SLEEP seconds"
       sleep \$SLEEP
    fi
done
check_errs \$RSYNC_OK "FAILED"
echo OK

EOF

# The rest of the processing is done at UPPMAX
print $scriptFh <<EOF;
cd $rfRoot
check_errs \$? "Failed to cd to $rfRoot"

# Only start calculating the fastq-stats and leave the report and extraction part
# to manual start after inspection
START_OK=1
SLEEP=300
until [ \$START_OK = 0 ]; do
    echo -n "Starting processing at UPPMAX "
    ssh $rHost "cd $rPath/$rfName; ./Sisyphus/aeacus-stats.pl -runfolder $rPath/$rfName $debugFlag";
    START_OK=\$?
    if [ \$START_OK -gt 0 ]; then
       echo "FAILED will retry in \$SLEEP seconds"
       sleep \$SLEEP
    fi
done
check_errs \$START_OK "FAILED"
echo OK




check_errs $? "FAILED to start aeacus-stats.pl in $rPath/$rfName at $rHost";

EOF

# Make the quick report
if(defined $config->{MAIL}){
    print $scriptFh "echo Generating quick report for $config->{MAIL}\n";
    print $scriptFh "quickReport.pl -runfolder $rfPath -mail $config->{MAIL}\n\n";
}

close $scriptFh;

chmod(0755, "$rfPath/sisyphus.sh");

if($exec){
    exec("$rfPath/sisyphus.sh");
}else{
    print "Batchscript for processing written to '$rfPath/sisyphus.sh'\n";
}

