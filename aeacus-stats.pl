#!/usr/bin/perl -w

use FindBin;                # Find the script location
use lib "$FindBin::Bin/lib";# Add the script libdir to libs
use Molmed::Sisyphus::Libpath;

use strict;
use Getopt::Long;
use Pod::Usage;
use Cwd qw(abs_path cwd);
use File::Basename;

use Molmed::Sisyphus::Uppmax::SlurmJob;
use Molmed::Sisyphus::Common;

=pod

=head1 NAME

aeacus.pl - Post process a runfolder at UPPMAX

=head1 SYNOPSIS

 aeacus.pl -help|-man
 aeacus.pl -runfolder <runfolder> [-debug]

=head1 OPTIONS

=over 4

=item -h|-help

prints out a brief help text.

=item -m|-man

Opens the manpage.

=item -runfolder

The runfolder to process.

=item -debug

Print debugging information

=back

The rest of the configuration is read from RUNFOLDER/sisyphus.yml. See example included in the sisyphus directory.

=head1 DESCRIPTION

aeacus.pl submits postprocessing batchjobs to the cluster at UPPMAX. Which jobs to submit is
determined from the sisyphus.yml configuration file.

aeacus.pl is normally started remotely as the last step performed by sisyphus.pl

The postprocessing includes the following steps:

=over 4

=item Fastq statistics collection

=back

=cut

my $rfPath = undef;
our $debug = 0;
my ($help,$man) = (0,0);

umask(007);

GetOptions('help|?'=>\$help,
           'man'=>\$man,
           'runfolder=s' => \$rfPath,
           'debug' => \$debug,
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
my $sampleSheet = $sisyphus->readSampleSheet();
my $excludedTiles = $sisyphus->excludedTiles();

# Set short name for use in jobnames
my $rfShort = join('-', @{[split(/_/, $rfName)]}[0,3]);

# Set some defaults
my $uProj = 'a2009002';
my $uQos  = undef;
my $aPath = "/proj/$uProj";
my $oPath = "/proj/$uProj/private/nobackup/OUTBOX";
my $scriptDir = "$rfPath/slurmscripts";
my $skipLanes = [];

# Read the sisyphus configuration and override the defaults
my $config = $sisyphus->readConfig();
if(defined $config->{UPPNEX_PROJECT}){
    $uProj = $config->{UPPNEX_PROJECT};
}
if(defined $config->{UPPNEX_QOS}){
    $uQos = $config->{UPPNEX_QOS};
}
if(defined $config->{OUTBOX_PATH}){
    $oPath = $config->{OUTBOX_PATH};
}
if(defined $config->{ARCHIVE_PATH}){
    $aPath = $config->{ARCHIVE_PATH};
}
if(defined $config->{SKIP_LANES}){
    $skipLanes = $config->{SKIP_LANES};
}

# Strip trailing slashes from paths
$oPath =~ s:/*$::;
$aPath =~ s:/*$::;

# Fastq statistics
# One per lane
my %ffJobs;
my $numLanes = $sisyphus->laneCount();

unless(-e $scriptDir){
    $sisyphus->mkpath($scriptDir) or die "Failed to create scriptdir '$scriptDir': $!";
}

open(my $jidFh, '>', "$rfPath/slurmscripts/ffJobs") or die $!;
for(my $i=1; $i<=$numLanes; $i++){
    # Create a slurm job handler
    my $ffJob =
      Molmed::Sisyphus::Uppmax::SlurmJob->new(
					      DEBUG=>$debug,         # bool
					      SCRIPTDIR=>$scriptDir, # Directory for writing the script
					      EXECDIR=>$rfPath,      # Directory from which to run the script
					      NAME=>"FF_$i-$rfShort",# Name of job, also used in script name
					      PROJECT=>$uProj,       # project for resource allocation
					      TIME=>"0-08:00:00",    # Maximum runtime, formatted as d-hh:mm:ss
					      QOS=>$uQos,            # High priority
					      PARTITION=>'core'      # core or node (or devel));
					     );
    $ffJob->addCommand("$FindBin::Bin/fastqStats.pl -runfolder $rfPath -lane $i $debugFlag", "fastqStats.pl on lane $i FAILED");
    $ffJobs{$i} = $ffJob;
    print STDERR "Submitting FF_$i-$rfShort\t";
    $ffJob->submit();
    print STDERR $ffJob->jobId(), "\n";
    print $jidFh "$i\t" . $ffJob->jobId() . "\n";

    # Make sure to get the script md5 into the sisyphus cache,
    # otherwise any old checksum from a failed run might fail the
    # archiving
    my $scriptFile = $ffJob->scriptFile();
    print STDERR "$scriptFile\n";
    $sisyphus->saveMd5($scriptFile, $sisyphus->getMd5($scriptFile, -noCache=>1));
}
close($jidFh);
$sisyphus->saveMd5("$rfPath/slurmscripts/ffJobs", $sisyphus->getMd5("$rfPath/slurmscripts/ffJobs", -noCache=>1));

print STDERR "fastqStats started\n";
