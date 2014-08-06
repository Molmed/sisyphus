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

uploadEntireMiSeqFolder.pl - Watch a runfolder and start processing it when it is completed

=head1 SYNOPSIS

 uploadEntireMiSeqFolder.pl -help|-man
 uploadEntireMiSeqFolder.pl -runfolder <runfolder> [-debug -noexec]

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
my $rHost = "milou-b.uppmax.uu.se";
my $uProj = "a2009002";
my $rPath = "/proj/$uProj/private/nobackup/runfolders";
my $oPath = "/proj/$uProj/private/nobackup/OUTBOX";
my $aHost = "milou-b.uppmax.uu.se";
my $aPath = "/proj/$uProj/private/";
my $sHost = "localhost";
my $sPath = dirname($rfPath) . '/summaries';
my $fastqPath = undef;
my $mismatches = '1:1:1:1:1:1:1:1';

# Read the sisyphus configuration and override the defaults
my $config = $sisyphus->readConfig();

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
	print "SampleSheet.csv found\n";
	$complete = 1;
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

# Create processing shellscript
open(my $scriptFh, '>', "$rfPath/uploadEntireMiSeqFolder.sh") or die "Failed to create '$rfPath/uploadEntireMiSeqFolder.sh':$!\n";
print $scriptFh <<EOF;
#!/bin/bash

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




# Transfer files to UPPMAX
cd $rfRoot
check_errs \$? "Failed to cd to $rfRoot"
EOF

my $rnd = time() . '.' . rand(1);

print $scriptFh <<EOF;

# First make a list of all the files that will be transferred,
# without actually doing it, for use by the checksumming
echo -n "rsync dry-run"
rsync -vrtp --dry-run --chmod=Dg+sx,ug+w,o-rwx --exclude-from '$FindBin::Bin/miseqentirerunfolder.rsync' '$rfName' '/$rnd' > '$rfName/rsync.miseqrunfolder.log'

# Now do the actual transfer, loop until successful
rm -f $rfName/rsync-real.miseqrunfolder.log
RSYNC_OK=1
SLEEP=300
until [ \$RSYNC_OK = 0 ]; do
    echo -n "rsync $rfPath $targetPath/$rfName/MiSeq_Runfolder/"
    ssh $rHost mkdir -p $rPath/$rfName/MiSeq_Runfolder;
    rsync -vrtp --chmod=Dg+sx,ug+w,o-rwx --exclude-from '$FindBin::Bin/miseqentirerunfolder.rsync' '$rfName' '$targetPath/$rfName/MiSeq_Runfolder/' >> '$rfName/rsync-real.miseqrunfolder.log'
    RSYNC_OK=\$?
    if [ \$RSYNC_OK -gt 0 ]; then
       echo "FAILED will retry in \$SLEEP seconds"
       sleep \$SLEEP
    fi
done
check_errs \$RSYNC_OK "FAILED"
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
cat $rfPath/rsync.miseqrunfolder.log | $FindBin::Bin/md5sum.pl $rfName > '$rfPath/MD5/checksums.miseqrunfolder.md5'
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

close $scriptFh;

chmod(0755, "$rfPath/uploadEntireMiSeqFolder.sh");

if($exec){
    exec("$rfPath/uploadEntireMiSeqFolder.sh");
}else{
    print "Batchscript for processing written to '$rfPath/uploadEntireMiSeqFolder.sh'\n";
}

