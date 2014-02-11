#!/usr/bin/perl -w

use FindBin;                # Find the script location
use lib "$FindBin::Bin/lib";# Add the script libdir to libs
use Molmed::Sisyphus::Libpath;

use strict;

use Getopt::Long;
use File::Basename;
use Molmed::Sisyphus::Common;


=pod

=head1 NAME

getSummary.pl - copy the Summary directory from a completed runfolder at UPPMAX

=head1 SYNOPSIS

 getSummary.pl -help|-man
 getSummary.pl -runfolder <runfolder>

=head1 OPTIONS

=over 4

=item -h|-help

prints out a brief help text.

=item -m|-man

Opens the manpage.

=item -runfolder

The runfolder to process.

=item -force

Download even if it already exists locally.

=head1 DESCRIPTION

getSummary.pl reads the config files sisyphus.yml from a runfolder and copies the
directory Summary from the runfolder at REMOTE_HOST:REMOTE_PATH.

If the folder already exists locally, no copy is made.

Before a copy is made, the folder is checked for the file summaryReport.html and
if the file is missing or younger than 1 hour, no copy is made.

If the runfolder is missing at the remote location, the file noSummary is created
in the local runfolder.

=cut

my $rfPath = undef;
my $force = 0;
my ($help,$man) = (0,0);

GetOptions('help|?'=>\$help,
           'man'=>\$man,
           'runfolder=s' => \$rfPath,
	   'force', \$force,
          ) or pod2usage(-verbose => 0);
pod2usage(-verbose => 1)  if ($help);
pod2usage(-verbose => 2)  if ($man);

unless(defined $rfPath && -e $rfPath){
    print STDERR "Runfolder not specified or does not exist\n";
    pod2usage(-verbose => 1);
    exit;
}

my $sisyphus = Molmed::Sisyphus::Common->new(PATH=>$rfPath, DEBUG=>0);
$rfPath = $sisyphus->PATH;
my $rfName = basename($rfPath);

unless($force){
    if(-e "$rfPath/Summary"){
	print "$rfPath/Summary already exists\n";
	exit;
    }elsif(-e "$rfPath/noSummary"){
	print "$rfPath/noSummary already exists\n";
    exit;
    }
}

my $config = $sisyphus->readConfig();
my $rHost = $config->{REMOTE_HOST};
my $rPath = $config->{REMOTE_PATH};

unless($rHost && $rPath){
    print "REMOTE_HOST or REMOTE_PATH not set in $rfPath/sisyphus.yml\n";
    exit;
}

# First check if runfolder exists on remote
my $remCheck = `ssh $rHost [ -d $rPath/$rfName ] && echo 1 || echo 0`;
unless($remCheck>0){ # Force remCheck to numeric
    print "$rfPath does not exist on remote\n";
    my @stat = stat $rfPath; # Get the local modtime of the runfolder
    my $now = time;
    if($now - $stat[9] > 3600*24*7){ # If the runfolder has not appeared at remote location in a week
	`touch "$rfPath/noSummary"`; # Stop looking for it
    }
	exit;
}


# Check date of Summary/summaryReport.html on remote host
# Use wildcard since the file might be gzipped
# Worst case, we get more than one modtime, but they should
# all be OK for this purpose
my $modTime = `ssh $rHost "[ -e $rPath/$rfName/Summary/summaryReport.html* ] && stat -c\%Y $rPath/$rfName/Summary/summaryReport.html* || echo 0"`;
chomp($modTime);
my $now = time;
print  "Modtime: $now - $modTime = ", $now - $modTime, "\n";

# Require modtime to be > 10 min old
if(defined $modTime && $modTime =~ m/\d/ && $modTime > 0 && $now - $modTime > 600){
    # Get the directory
    system( qq(rsync -av "$rHost:$rPath/$rfName/Summary" "$rfPath/") )==0
      or die "Failed to download $rPath/$rfName/Summary to $rfPath";
    # Also gunzip the html & xml files in the Summary
    gunzip("$rfPath/Summary");
    if(-e "$FindBin::Bin/../ProjMan/readResults.pl"){
	print "Inserting results in Project DB\t";
	if( system("$FindBin::Bin/../ProjMan/readResults.pl", $rfPath) == 0){
	    print "OK\n";
	}else{
	    print "FAILED\n";
	}
    }
}else{
    exit;
}

sub gunzip{
    my $dir = shift;
    opendir(my $dFh, $dir) or die "Failed to open $dir";
    while(my $f = readdir($dFh)){
	next if($f eq '.' || $f eq '..');
	if(-d "$dir/$f"){
	    gunzip("$dir/$f");
	}elsif($f =~ m/\.(ht|x)ml.gz/){
	    `gunzip -f "$dir/$f"`;
	}
    }
    closedir($dFh);
}
