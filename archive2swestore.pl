#!/usr/bin/perl -w

use FindBin;
use lib "$FindBin::Bin/lib";# Add the script libdir to libs

use strict;
use Getopt::Long;
use Pod::Usage;
use File::Basename;
use Digest::MD5;
use YAML::Tiny;
use Cwd qw(abs_path cwd);

use Molmed::Sisyphus::Kalkyl::SlurmJob;

=head1 NAME

archive2swestore.pl - Archive a runfolder to SweStore and verify the archive

=head1 SYNOPSIS

 archive2swestore.pl -help|-man
 archive2swestore.pl -runfolder <runfolder> -config <sisyphus.yml> [-debug]

=head1 OPTIONS

=over 4

=item -h|-help

prints out a brief help text.

=item -m|-man

Opens the manpage.

=item -runfolder

The the archived runfolder to copy to SweStore.

=item -config

yml-config file to read options from. Normally the file sisyphus.yml in the original runfolder.

=item -ipath

The iRODS root directory for the runfolder archive at SweStore

=item -tmpdir

The directory to use for temporary downloads during verification.

=item -proj

Slurm account to use if submitting batch jobs

=item -verifyOnly

Skip uploading and just verify the archive, assuming it is already at SweStore.

=item -debug

Print debugging information

=back

=head1 DESCRIPTION

archive2swestore.pl is a script for uploading and verifying a runfolder archive
to SweStore using iRODS.

First the archive is uploaded to SweStore using irsync and then all files
are downloaded and verified against their md5 checksums as stored in the
checksum files in the archived runfolder.

If upload is performed, then the verification will be delayed by submitting
a new slurm-job with start time four days in the future.

If a file fails to verify it will be re-transferred up to three times before giving up.

If any file fails to verify after three tries, the script will stop and exit with an error.

=head1 FUNCTIONS

=cut

# Store how we were called, bc we might need it again
my $scriptCommand = join(" ", "$FindBin::Bin/$FindBin::RealScript", @ARGV);

# Parse options
my($help,$man) = (0,0);
my($srcDir,$tmpPath,$iPath,$verifyOnly,$proj,$config) = (undef,undef,undef,0,undef,undef);
our($debug) = 0;

GetOptions('help|?'=>\$help,
	   'man'=>\$man,
	   'runfolder=s' => \$srcDir,
	   'config=s' =>\$config,
	   'tmpdir=s' => \$tmpPath,
	   'verifyOnly' =>\$verifyOnly,
	   'ipath=s'=>\$iPath,
	   'proj' =>\$proj,
	   'debug' => \$debug,
	  ) or pod2usage(-verbose => 0);
pod2usage(-verbose => 1)  if ($help);
pod2usage(-verbose => 2)  if ($man);

unless(defined $srcDir && -e $srcDir){
    print STDERR "Runfolder not specified or does not exist\n";
    pod2usage(-verbose => 1);
    exit;
}
$srcDir = abs_path($srcDir);

my $yml;
if(defined $config && -e $config){
    $yml = YAML::Tiny->read($config) or die "Failed to read '$config'";
    $yml = $yml->[0];
}

unless(defined $iPath){
    if(defined $yml->{SWESTORE_PATH}){
	$iPath = $yml->{SWESTORE_PATH};
    }else{
	print STDERR "iRODS path must be specified\n";
	pod2usage(-verbose => 1);
	exit;
    }
}

unless(defined $proj){
    if(defined $yml->{UPPNEX_PROJECT}){
	$proj = $yml->{UPPNEX_PROJECT};
    }else{
	print STDERR "UPPNEX project must be specified\n";
	pod2usage(-verbose => 1);
	exit;
    }
}

unless(defined $tmpPath){
    if(defined $yml->{TEMP_PATH}){
	$tmpPath = $yml->{TEMP_PATH};
    }else{
	print STDERR "Temp path must be specified\n";
	pod2usage(-verbose => 1);
	exit;
    }
}

$tmpPath = "$tmpPath/$$";
$tmpPath =~ s:/+:/:g;
unless(-e $tmpPath){
    system("mkdir -p $tmpPath")==0 or die "Failed to create $tmpPath";
}

my $rfName = basename($srcDir);
my $md5file = abs_path("$srcDir/$rfName.archive.md5");
unless(-e $md5file){
    die "MD5 file $md5file does not exist";
}

$iPath =~ s:/$::g;

# First upload to SweStore, unless told otherwise
unless($verifyOnly){
    # Get the year and month for use in dir name
    my @time = localtime(time); # ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)
    my $month = ($time[5] + 1900) . '-' . sprintf('%02d', $time[4]);
    if($srcDir =~ m/(1\d)([01]\d)[0123]\d_/){
	$month = "20$1-$2";
    }
    system('imkdir', '-p', "$iPath/$month");
    # Do the actual upload, try three times before giving up
    my $tries = 0;
    my $failed = 1;
    until($tries > 3 || $failed==0){
	$tries++;
	$failed = system("irsync", "-v", "-r", $srcDir, "i:$iPath/$month/$rfName");
    }
    # Die if we failed after multiple attempts
    die "Failed to upload to SweStore" if($failed);

    # Do not verify immediately, wait for the files
    # to migrate from local cache to Swestore
    my $scriptDir = "$srcDir/../../ArchiveScripts";
    unless(-e $scriptDir){
	mkdir($scriptDir)
	    or die "Failed to create '$scriptDir': $!";
	mkdir("$scriptDir/logs")
	    or die "Failed to create '$scriptDir/logs': $!";
    }

   $scriptDir = abs_path($scriptDir);
    my $execPath = abs_path("$srcDir/..");
    my @sTime = localtime(time() + (3600*24*4));
    $sTime[4]++; # Months are zero based from localtime
    my $sTime = sprintf('%02d:%02d %02d/%02d/%02d', $sTime[2],$sTime[1],$sTime[4],$sTime[3], ($sTime[5] - 100));

    my $job =
	Molmed::Sisyphus::Kalkyl::SlurmJob->new(
	    DEBUG=>$debug,         # bool
	    SCRIPTDIR=>$scriptDir, # Directory for writing the script
	    EXECDIR=>$execPath,    # Directory from which to run the script
	    NAME=>"SwSt-$rfName",  # Name of job, also used in script name
	    PROJECT=>$proj,        # project for resource allocation
	    TIME=>"1-00:00:00",    # Maximum runtime, formatted as d-hh:mm:ss
	    STARTTIME=>"$sTime",   # Defer job until
	    PARTITION=>'core'      # core or node (or devel));
	);
    $job->addCommand("$scriptCommand --verifyOnly -ipath '$iPath/$month'", "archive2swestore on $rfName FAILED");
    print STDERR "Submitting SwSt-$rfName starting at $sTime\t";
    $job->submit();
    print STDERR $job->jobId(), "\n";

    # Now exit and let the verification be done later
    exit;
}

# Now verify the files in the uploaded archive
chdir($tmpPath);
open(my $md5fh, $md5file) or die "Failed to open $md5file: $!";
my @seen = verifyMd5($md5fh, $iPath) or die "Failed to verify $md5file\n";
close($md5fh);

# Older versions of archiving only has the fastq.gz files in the compressed.md5 file
if(-e "$srcDir/$rfName.compressed.md5"){
    my $fqfile = abs_path("$srcDir/$rfName.compressed.md5");
    # So grep them from it and skip the rest
    open(my $fqfh,'-|', "grep fastq.gz $fqfile") or die "Failed to open $fqfile: $!";
    push @seen, verifyMd5($fqfh, $iPath) or die "Failed to verify $md5file\n";
    close($fqfh);
}

unless(grep(/fastq\.gz/, @seen) > 0){
    print "WARNING: No fastq.gz files seen during verification!\n";
    print STDERR "WARNING: No fastq.gz files seen during verification!\n";
}

print "All files verified\n";

system("rmdir $tmpPath");

sub verifyMd5{
  my $md5fh = shift;
  my $iPath = shift;
  my $digest = Digest::MD5->new;
  my @seen;

  while(<$md5fh>){
    chomp;
    my($md5, $path)=split /  /, $_;
    push @seen, $path;
    unless(checkFile(0, $srcDir, $digest, $md5, $path, $iPath)){
      die "Failed to verify $path ($md5)";
    }
  }
  return @seen;
}

sub checkFile{
  my $i=shift;
  my $srcDir = shift;
  my $digest = shift;
  my $md5 = shift;
  my $path = shift;
  my $iPath = shift;
  if($i>3){
    print "$path FAILED\n";
    exit 1;
  }

  if(getFile($i, $path, $iPath)){
    if(verifyFile($digest, $md5, $path)){
      return 1;
    }elsif($i>3){
	print "$path FAILED\n";
	exit 1;
    }else{
      if(putFile($i, $srcDir, $path, $iPath)){
	return checkFile($i+1, $srcDir, $digest, $md5, $path, $iPath);
      }else{
	print "$path FAILED\n";
	exit 1;
      }
    }
  }elsif(putFile($i, $srcDir, $path, $iPath)){
    return(checkFile($i+1, $srcDir, $digest, $md5, $path, $iPath));
  }
  return 0;
}

sub putFile{
  my $i=shift;
  my $srcDir = shift;
  my $path = shift;
  my $iPath = shift;

  print STDERR "Trying to upload $path\n";

  my $srcPath = abs_path(dirname($srcDir) . "/$path");
  if(-e $srcPath){
      if(system('irm','-f', "$iPath/$path") ==0 && system('iput', '-f', "$srcPath", "$iPath/$path")==0){
	  return pushFile("$iPath/$path", 0);
      }elsif( system('iput', '-f', "$srcPath", "$iPath/$path")==0 ){
	  return pushFile("$iPath/$path", 0);
      }elsif($i<3){
	  return(putFile($i+1, $srcDir, $path, $iPath));
      }
  }else{
      die "$srcPath does not exists for re-upload";
  }
  print STDERR "Failed to upload $iPath/$path\n";
  return 0;
}

sub pushFile{
    my $file = shift;
    my $i=shift;

    # Push the file to remote Swestore
    if(system('irepl', '-R', 'swestoreArchResc', $file)==0){
	return 1;
    }elsif($i<3){
	return(pushFile($file, $i+1));
    }
    print STDERR "Failed to push $file to remote\n";
    return 0;
}

sub removeLocalCache{
    my $file = shift;
    my $i=shift;

    my @list = split(/\n/, `ils -l $file`);

    unless(grep /swestoreArchResc/, @list){
	unless(pushFile($file, 0)){
	    return 0;
	}
    }

    my $retval = 1;
    foreach my $path (@list){
	$path =~ s/^\s+//;
	my @p = split /\s+/, $path;

	# Remove local cache copies
	if($p[2] eq 'swestoreArchCacheRes'){
	    if(system('itrim', '-S', 'swestoreArchCacheRes', '-N', 1, '-n', $p[1], $file)==0){
		$retval=1;
	    }elsif($i<3){
		return(removeLocalCache($file, $i+1));
	    }else{
		print STDERR "Failed to remove $file from cache\n";
		$retval=0;
		last;
	    }
	}
    }
    return $retval;
}

sub getFile{
  my $i=shift;
  my $path = shift;
  my $iPath = shift;

  # Make sure to remove file from local cache before download
  if(removeLocalCache("$iPath/$path", 0)){
      if(system('iget', '-f', "$iPath/$path")==0){
	  return 1;
      }elsif($i<3){
	  print STDERR "Download failed, trying again $path\n";
	  return(getFile($i+1, $path,$iPath));
      }
  }
  return 0;
}

sub verifyFile{
  my $digest = shift;
  my $md5 = shift;
  my $path = shift;

  my $tmpFile = basename($path);
  open(my $tmpFh, $tmpFile) or die "Failed to open $tmpFile: $!";
  binmode($tmpFh);
  my $sum = $digest->addfile($tmpFh)->hexdigest;
  if($sum eq $md5){
    print "$path\tOK\n";
    system('rm', $tmpFile)==0 or die "Failed to rm $tmpFile: $!";
    return 1;
  }
  return 0;
}
