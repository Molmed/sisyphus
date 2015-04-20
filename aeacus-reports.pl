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

=item Extraction of projects for data delivery

=item Generation of global report

=item Archiving

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
my $uQos = undef;
my $aPath = "/proj/$uProj";
my $iPath = "/ssUppnexZone/proj/$uProj";
my $oPath = "$rfPath/Projects";
my $tmpdir = "/proj/a2009002/private/nobackup/tmp/$$";
my $scriptDir = "$rfPath/slurmscripts";
my $skipLanes = [];
my $email = undef;

# Read the sisyphus configuration and override the defaults
my $config = $sisyphus->readConfig();
if(defined $config->{UPPNEX_PROJECT}){
    $uProj = $config->{UPPNEX_PROJECT};
}
if(defined $config->{UPPNEX_QOS}){
    $uQos = $config->{UPPNEX_QOS};
}
if(defined $config->{OUTBOX_PATH} && $config->{OUTBOX_PATH} !~ /\s*default\s*/i){
    $oPath = $config->{OUTBOX_PATH};
}
if(defined $config->{ARCHIVE_PATH}){
    $aPath = $config->{ARCHIVE_PATH};
}
if(defined $config->{SWESTORE_PATH}){
    $iPath = $config->{SWESTORE_PATH};
}
if(defined $config->{TMPDIR}){
    $tmpdir = $config->{TMPDIR};
}
if(defined $config->{SKIP_LANES}){
    $skipLanes = $config->{SKIP_LANES};
}
if(defined $config->{MAIL}){
    $email = $config->{MAIL};
}

# Strip trailing slashes from paths
$oPath =~ s:/*$::;
$aPath =~ s:/*$::;

# Fastq statistics
# One per lane
my %ffJobs;
my $numLanes = $sisyphus->laneCount();

open(my $jidFh, '<', "$rfPath/slurmscripts/ffJobs") or die $!;
while(<$jidFh>){
    chomp;
    my($l,$j) = split /\t/, $_;
    $ffJobs{$l} = $j;
}

# Extract data to OUTBOX
# One per project
my %projJobs;

foreach my $proj (keys %{$sampleSheet}){
    # Create a slurm job handler
    my $projJob =
      Molmed::Sisyphus::Uppmax::SlurmJob->new(
					       DEBUG=>$debug,         # bool
					       SCRIPTDIR=>$scriptDir, # Directory for writing the script
					       EXECDIR=>$rfPath,      # Directory from which to run the script
					       NAME=>"$proj-$rfShort",# Name of job, also used in script name
					       PROJECT=>$uProj,       # project for resource allocation
					       TIME=>"0-06:00:00",    # Maximum runtime, formatted as d-hh:mm:ss
					       QOS=>$uQos,            # High priority
					       PARTITION=>'core',      # core or node (or devel));
                 MAIL_USER=>$email,
                 MAIL_TYPE=>'FAIL'
					      );
    foreach my $lane (keys (%{$sampleSheet->{$proj}})){
	$projJob->addDep($ffJobs{$lane}) if exists($ffJobs{$lane});
    }
    $projJob->addCommand("module load uppmax");
    $projJob->addCommand("module load gnuplot");
    $projJob->addCommand("umask 007");
    my $cmd = "$FindBin::Bin/extractProject.pl -runfolder $rfPath -project '$proj' -outdir '$oPath/$proj' $debugFlag";
    foreach my $lane (@{$skipLanes}){
      $cmd .= " -skip $lane";
    }
    $projJob->addCommand($cmd, "extractProject.pl on $proj FAILED");
    print STDERR "Submitting $proj-$rfShort\t";
    $projJob->submit({queue=>1});
    $projJobs{$proj} = $projJob;
    print STDERR $projJob->jobId(), "\n";
    # Make sure to get the script md5 into the sisyphus cache,
    # otherwise any old checksum from a failed run might fail the
    # archiving
    my $scriptFile = $projJob->scriptFile();
    print STDERR "$scriptFile\n";
    # If an old script was created the MD5 might be saved, so make sure to overwrite that
    $sisyphus->saveMd5($scriptFile, $sisyphus->getMd5($scriptFile, -noCache=>1));
}

# Global report
# Depend on all other jobs
# Create a slurm job handler
my $repJob =
  Molmed::Sisyphus::Uppmax::SlurmJob->new(
                                           DEBUG=>$debug,         # bool
                                           SCRIPTDIR=>$scriptDir, # Directory for writing the script
                                           EXECDIR=>$rfPath,      # Directory from which to run the script
                                           NAME=>"Rep-$rfShort", # Name of job, also used in script name
                                           PROJECT=>$uProj,       # project for resource allocation
                                           TIME=>"0-10:00:00",    # Maximum runtime, formatted as d-hh:mm:ss
                                           QOS=>$uQos,            # High priority
                                           PARTITION=>'core',     # core or node (or devel));
                                           MAIL_USER=>$email,
                                           MAIL_TYPE=>'FAIL'
                                          );
foreach my $job (values %projJobs){
    $repJob->addDep($job);
}
$repJob->addCommand("module load uppmax");
$repJob->addCommand("module load gnuplot");
$repJob->addCommand("umask 007");
$repJob->addCommand("$FindBin::Bin/generateReport.pl -runfolder $rfPath $debugFlag", "generateReport.pl on $rfPath FAILED");
print STDERR "Submitting Rep-$rfShort\t";
$repJob->submit({queue=>1});
print STDERR $repJob->jobId(), "\n";
# Make sure to get the script md5 into the sisyphus cache,
# otherwise any old checksum from a failed run might fail the
# archiving
my $scriptFile = $repJob->scriptFile();
print STDERR "$scriptFile\n";
# If an old script was created the MD5 might be saved, so make sure to overwrite that
$sisyphus->saveMd5($scriptFile, $sisyphus->getMd5($scriptFile, -noCache=>1));



# Archive
# Depend on report generation
# Create a slurm job handler
my $archJob =
  Molmed::Sisyphus::Uppmax::SlurmJob->new(
					   DEBUG=>$debug,         # bool
					   SCRIPTDIR=>$scriptDir, # Directory for writing the script
					   EXECDIR=>$rfPath,      # Directory from which to run the script
                                           NAME=>"Arch-$rfShort", # Name of job, also used in script name
					   PROJECT=>$uProj,       # project for resource allocation
					   TIME=>"2-00:00:00",    # Maximum runtime, formatted as d-hh:mm:ss
					   PARTITION=>'core',      # core or node (or devel))
					   CORES=>'2',
             MAIL_USER=>$email,
             MAIL_TYPE=>'FAIL'
					  );
$archJob->addDep($repJob);
$archJob->addCommand("module load uppmax");
$archJob->addCommand("module load irods/swestore");
$archJob->addCommand("umask 007");

# Add year and month to outdir if not already included
unless($aPath =~ m/201\d-[0123]\d$/){
    if($sisyphus->RUNFOLDER =~ m/(1\d)([01]\d)[0123]\d_/){
	$aPath .= "/20$1-$2";
    }
}
unless($iPath =~ m/201\d-[0123]\d$/){
    if($sisyphus->RUNFOLDER =~ m/(1\d)([01]\d)[0123]\d_/){
	$iPath .= "/20$1-$2";
    }
}

$archJob->addCommand("$FindBin::Bin/archive.pl -runfolder $rfPath -outdir '$aPath' -swestore $debugFlag", "archive.pl on $rfPath FAILED");
print STDERR "Submitting Arch-$rfShort\t";
$archJob->submit({queue=>1});
print STDERR $archJob->jobId(), "\n";
# Make sure to get the script md5 into the sisyphus cache,
# otherwise any old checksum from a failed run might fail the
# archiving
$scriptFile = $archJob->scriptFile();
print STDERR "$scriptFile\n";
# If an old script was created the MD5 might be saved, so make sure to overwrite that
$sisyphus->saveMd5($scriptFile, $sisyphus->getMd5($scriptFile, -noCache=>1));


print STDERR "Done\n";
