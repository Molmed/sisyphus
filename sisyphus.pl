#!/usr/bin/perl -w

use FindBin;                # Find the script location
use lib "$FindBin::Bin/lib";# Add the script libdir to libs

use strict;
use POSIX ":sys_wait_h";
use Getopt::Long;
use Pod::Usage;
use File::Basename;
use Cwd qw(abs_path);

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

=item -miseq

Also upload the entire MiSeq runfolder to a subfolder in the runfolder on Uppmax

=item -ignoreQCResult

Proceed with the data processing, even though one or multiple QC criteria have failed.

=item -noUppmaxProcessing

Will not upload any data to Uppmax or start any jobs on Uppmax

=item -noSeqStatSync

Will not sync Seq-Summaries data

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
my $miseq = 0;
my $exec = 1;
my $wait = 1;
my $ignoreQCResult = 0;
my $noUppmaxProcessing = 0;
my $noSeqStatSync = 0;
my $force = 0;
our $debug = 0;
my $threads = `cat /proc/cpuinfo |grep "^processor"|wc -l`;
$threads = ($threads == 1) ?  1 :  int($threads/2);

my ($help,$man) = (0,0);

GetOptions('help|?'=>\$help,
	   'man'=>\$man,
	   'runfolder=s' => \$rfPath,
           'miseq!' => \$miseq,
	   'exec!' => \$exec,
	   'wait!' => \$wait,
	   'ignoreQCResult!' => \$ignoreQCResult,
	   'noUppmaxProcessing!' => \$noUppmaxProcessing,
	   'noSeqStatSync!' => \$noSeqStatSync,
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
my $rHost = "milou-b.uppmax.uu.se";
my $uProj = "a2009002";
my $rPath = "/proj/$uProj/private/nobackup/runfolders";
my $oPath = "/proj/$uProj/private/nobackup/OUTBOX";
my $aHost = "milou-b.uppmax.uu.se";
my $aPath = "/proj/$uProj/private/";
my $sHost = "localhost";
my $sPath = dirname($rfPath) . '/summaries';
my $anPath = $rfRoot . '/MiSeqAnalysis';
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

# Only allow the -miseq flag if this is a miseq run
unless (!$miseq || $sisyphus->machineType() eq 'miseq') {
    print STDERR "The -miseq flag can only be used for MiSeq run folders ('$rfPath' does not appear to be one)\n";
    pod2usage(-verbose => 1);
    exit;
}

# Get extra library path from config and save to a separate file
`touch $FindBin::Bin/PERL5LIB`;
if(defined $config->{PERL5LIB}){
    open(my $LIB, ">$FindBin::Bin/PERL5LIB") or die "Failed to write $FindBin::Bin/PERL5LIB: $!";
    foreach my $libPath (@{$config->{PERL5LIB}}){
	print $LIB "$libPath\n";
    }
    close($LIB);
}

# Set paths from config
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
if(defined $config->{ANALYSIS_PATH}){
    $anPath = abs_path($rfPath . '/' . $config->{ANALYSIS_PATH});
}

# Strip trailing slashes from paths
$rPath =~ s:/*$::;
$oPath =~ s:/*$::;
$aPath =~ s:/*$::;
$sPath =~ s:/*$::;
$anPath =~ s:/*$::;

# Set combined paths
my $targetPath = "$rHost:$rPath";
my $summaryPath = "$sHost:$sPath";
my $archivePath = "$aHost:$aPath";
my $rBin = "$rPath/$rfName/Sisyphus";
my $analysisPath = "$anPath/$rfName";

if($debug){
    print "\$rHost => $rHost\n";
    print "\$rPath => $rPath\n";
    print "\$sHost => $sHost\n";
    print "\$sPath => $sPath\n";
    print "\$aHost => $aHost\n";
    print "\$aPath => $aPath\n";
    print "\$oPath => $oPath\n";
    print "\$rfName => $rfName\n";
    print "\$anPath => $anPath\n";

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
	print STDERR "SampleSheet has errors. Please fix it. You do not have to abort!\nJust fix the file and the script will continue after sleeping 10 minutes from now.\n" unless($complete);
    }else{
	print STDERR "SampleSheet.csv is missing\n";
	$complete=0;
    }
    unless($complete) {
      print STDERR "Sleeping for 10 minutes\n";
      sleep 600;
    }
}

# Check that the MiSeq analysis folder has finished copying, wait until it finishes otherwise
if ($miseq) {
    print STDERR "Checking MiSeq Analysis folder for completion!\n\n";
    $complete = 0;
    until($complete) {
        if (! -e $analysisPath || ! -d $analysisPath) {
            print STDERR "Analysis folder does not exist, expects $analysisPath\n";
        }
        elsif (! -e "$analysisPath/TransferComplete.txt") {
            print STDERR "Indication that transfer of analysis results is complete is missing\n";
        }
        else {
            $complete = 1;
        }
        unless($complete) {
          print STDERR "Sleeping for 10 minutes\n";
          sleep 600;
        }
    }
}

die unless($complete);

print STDERR "Runfolder $rfPath ready to go!\n";

# Sleep 30 minutes as an additional precaution
sleep 1800 if($wait);

my $runInfo = $sisyphus->getRunInfo() || die "Failed to read RunInfo.xml from $rfPath\n";

# This (or rather the object method) will need changing when we have an example of a dual-index run
my $readMask = $sisyphus->createReadMask() || die "Failed to generate readMask";
my $posFormat = $sisyphus->positionsFormat();
my $machineType = $sisyphus->machineType();

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
   git --git-dir $FindBin::Bin/.git describe --tags
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

if ($machineType eq "hiseqx") {
    $includeTiles =~ s/,/ --tiles /g;

    if (-e "$fastqPath/Unaligned") {
        print STDERR "\n\nERROR: $fastqPath/Unaligned already exists\n\n";
        exit 1; 
    } else {
        mkdir "$fastqPath/Unaligned";
    }
    print $scriptFh <<EOF;

if [ ! -e "$rfPath/Unaligned" ]; then
   ln -s "$fastqPath/Unaligned" "$rfPath/Unaligned"
fi

$config->{BCL2FASTQ} -v 2>&1 | awk '{if(/^bcl2fastq/){print \$2}}' > $rfPath/bcl2fastq.version

echo "Demultiplexing/Converting to FastQ"

$config->{BCL2FASTQ} --input-dir '$rfPath/Data/Intensities/BaseCalls' --output-dir '$fastqPath/Unaligned' --use-bases-mask '$readMask' --barcode-mismatches '$mismatches' ${ignore} --tiles $includeTiles &> BclToFastq.log
check_errs \$? "bcl2fastq failed in $fastqPath/Unaligned"

EOF

    if(@excTiles > 0){
        my $excludeTiles = join ',', @excTiles;
        if (-e "$fastqPath/Excluded") {
            print STDERR "\n\nERROR: $fastqPath/Excluded already exists\n\n";
            exit 1; 
        } else {
            mkdir "$fastqPath/Excluded" unless -e "$fastqPath/Excluded";
        }
        print $scriptFh <<EOF;
echo "Setting up demultiplexing of excluded tiles"

EOF

        $excludeTiles =~ s/,/ --tiles /g;
        print $scriptFh <<EOF;

$config->{BCL2FASTQ} --input-dir '$rfPath/Data/Intensities/BaseCalls' --output-dir '$fastqPath/Excluded' --use-bases-mask '$readMask' --barcode-mismatches '$mismatches' ${ignore} --tiles --tiles $excludeTiles &> $rfPath/setupBclToFastqExcluded.err

if [ ! -e "$rfPath/Excluded" ]; then
   ln -s "$fastqPath/Excluded" "$rfPath/Excluded"
fi

EOF
        } 
    } else {
        print $scriptFh <<EOF;
if [ ! -e "$rfPath/Unaligned" ]; then
   ln -s "$fastqPath/Unaligned" "$rfPath/Unaligned"
fi

EOF

    print $scriptFh <<EOF;
configureBclToFastq.pl --input-dir '$rfPath/Data/Intensities/BaseCalls' --output-dir '$fastqPath/Unaligned' --sample-sheet '$rfPath/SampleSheet.csv' --use-bases-mask '$readMask' --mismatches '$mismatches' ${ignore} --positions-format $posFormat --fastq-cluster-count 0 --tiles $includeTiles &> $rfPath/setupBclToFastq.err
check_errs \$? "configureBclToFastq.pl failed"

EOF

    if(@excTiles > 0){
        my $excludeTiles = join ',', @excTiles;
        print $scriptFh <<EOF;
echo "Setting up demultiplexing of excluded tiles"

configureBclToFastq.pl --input-dir '$rfPath/Data/Intensities/BaseCalls' --output-dir '$fastqPath/Excluded' --sample-sheet '$rfPath/SampleSheet.csv' --use-bases-mask '$readMask' --mismatches 1 --positions-format $posFormat --fastq-cluster-count 0 --tiles $excludeTiles &> $rfPath/setupBclToFastqExcluded.err
check_errs \$? "configureBclToFastq.pl for excluded tiles failed"

check_errs \$? "bclt2fastq failed in $fastqPath/Excluded"

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

EOF

    if(@excTiles > 0){
        print $scriptFh <<EOF;

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
}
# Random string used for rsync dry-run.
my $rnd = time() . '.' . rand(1);

print $scriptFh <<EOF;

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
   git --git-dir "$rfPath/Sisyphus/.git" describe --tags > "$rfPath/Sisyphus/SISYPHUS_VERSION"
   check_errs \$? "Failed to get sisyphus version from $rfPath/Sisyphus/.git"
fi

EOF

# If uploading a MiSeq Analysis folder, tarball it and move it into the normal runfolder
if ($miseq) {
	print $scriptFh <<EOF;

if [ ! -e "$rfPath/MD5" ]; then
    mkdir -m 2770 $rfPath/MD5
    check_errs \$? "Failed to mkdir $rfPath/MD5"
fi

cd $anPath
check_errs \$? "Failed to cd to $anPath"

if [ -e "$rfName" ]; then

  echo -n "Checksumming files from $analysisPath"

  # List the contents of the MiSeq analysis folder, and calculate MD5 checksums
  find '$rfName' -type f | $FindBin::Bin/md5sum.pl $rfName > $rfPath/MD5/checksums.miseqrunfolder.md5
  check_errs \$? "FAILED"
  
  echo OK

  # Tarball the entire MiSeq analysis folder and move it under the runfolder
  echo -n "Tarballing MiSeq analysis folder '$analysisPath'"
  $FindBin::Bin/gzipFolder.pl '$rfName' '$rfPath/MD5/checksums.miseqrunfolder.md5'
  
  check_errs \$? "FAILED"
  
  echo OK
  
  echo -n "Move MiSeq analysis tarball to '$rfPath'"
  mv "$rfName.tar.gz" "$rfPath/MiSeq_Runfolder.tar.gz"
  check_errs \$? "FAILED"
  
  echo OK

# If the analysis runfolder does not exist but the tarball does, it's ok, we are just re-running the script
elif [ -e "$rfPath/MiSeq_Runfolder.tar.gz" ]; then
  echo -n "MiSeq analysis folder is missing, but the tarball exists. Everything is OK!"
  
# Else, the folders and arguments need to be verified
else
  check_errs 1 "Was expecting a MiSeq analysis runfolder: '$analysisPath', but did not find one"
  
fi
  
EOF

}

# Make the quick report
if (defined $config->{MAIL}) {
    print $scriptFh <<EOF;
echo Generating quick report for $config->{MAIL}
quickReport.pl -runfolder $rfPath -mail $config->{MAIL} -sender $config->{SENDER}
#Check if quick report could be generated.
check_errs \$? "Could not generate quickReport"

qcValidateRun.pl -runfolder $rfPath -mail $config->{MAIL} -sender $config->{SENDER}

EOF

unless($ignoreQCResult) {
    print $scriptFh <<EOF;
check_errs \$? "FAILED QC"
EOF
}
}

unless($noUppmaxProcessing) {
print $scriptFh <<EOF;


# Transfer files to UPPMAX
cd $rfRoot
check_errs \$? "Failed to cd to $rfRoot"

# Make a list of all the files that will be transferred,
# without actually doing it, for use by the checksumming
rsync -vrktp --dry-run --chmod=Dg+sx,ug+w,o-rwx --prune-empty-dirs --include-from '$FindBin::Bin/hiseq.rsync' '$rfName' '/$rnd' > '$rfName/rsync.log'

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

# Calculate md5 checksums of the transferred files
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
}

unless($noSeqStatSync) {
print $scriptFh <<EOF;
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
}
unless($noUppmaxProcessing) {
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

print $scriptFh <<EOF;
cd $rfRoot
check_errs \$? "Failed to cd to $rfRoot"

# Start extracting projects and archive data
# to manual start after inspection
START_OK=1
SLEEP=300
sleep 10
until [ \$START_OK = 0 ]; do
    echo -n "Starting extracting and archiving at UPPMAX "
    ssh $rHost "cd $rPath/$rfName; ./Sisyphus/aeacus-reports.pl -runfolder $rPath/$rfName $debugFlag";
    START_OK=\$?
    if [ \$START_OK -gt 0 ]; then
       echo "FAILED will retry in \$SLEEP seconds"
       sleep \$SLEEP
    fi
done
check_errs \$START_OK "FAILED"
echo OK

check_errs $? "FAILED to start aeacus-reports.pl in $rPath/$rfName at $rHost";

EOF
}

close $scriptFh;

chmod(0755, "$rfPath/sisyphus.sh");

if($exec){
    exec("$rfPath/sisyphus.sh");
}else{
    print "Batchscript for processing written to '$rfPath/sisyphus.sh'\n";
}

