#!/usr/bin/perl -w

use FindBin;                # Find the script location
use lib "$FindBin::Bin/lib";# Add the script libdir to libs
use Molmed::Sisyphus::Libpath;

use strict;
use Getopt::Long;
use Pod::Usage;
use Cwd qw(abs_path cwd);
use File::Basename;
use File::Find;

use Molmed::Sisyphus::Common qw(mkpath);


=head1 NAME

unpack.pl - Unpack a previously archived runfolder

=head1 SYNOPSIS

 unpack.pl -help|-man
 unpack.pl -indir <archive> -outdir <outdir> [-debug]

=head1 OPTIONS

=over 4

=item -h|-help

prints out a brief help text.

=item -m|-man

Opens the manpage.

=item -indir

The runfolder archive to unpack.

=item -outdir

The directory to create the unpacked copy in.

=item -verify

If set, verify the unpacked files against the stored checksums.

=item -uncompress

If set, uncompress all gzip files except fastq/sequence.txt-files.

=item -uncompress-seq

If set, uncompress the fastq/sequence.txt-files.

=item -uncompress-all

If set, uncompress all gzip files.

=item -debug

Print debugging information

=back

=head1 DESCRIPTION

unpack.pl is a script for restoring a working copy of a runfolder archived with archive.pl.
All gzipped files except the fastq/sequence.txt-files are uncompressed and verified
against their checksums in <runfolder>.original.md5 or <runfolder>.compressed.md5,
depending on if they are decompressed or not.

=cut

# Parse options
my($help,$man) = (0,0);
my($inDir,$outDir,$verify,$uncompress,$ucSeq,$ucAll) = (undef,undef,1,0,0,0);
our($debug) = 0;

GetOptions('help|?'=>\$help,
           'man'=>\$man,
           'indir=s' => \$inDir,
           'outdir=s' => \$outDir,
           'verify' => \$verify,
           'uncompress' => \$uncompress,
           'uncompress-seq' => \$ucSeq,
           'uncompress-all' => \$ucAll,
	   'debug' => \$debug
          ) or pod2usage(-verbose => 0);
pod2usage(-verbose => 1)  if ($help);
pod2usage(-verbose => 2)  if ($man);

unless(defined $inDir && -e $inDir){
    print STDERR "Runfolder not specified or does not exist\n";
    pod2usage(-verbose => 1);
    exit;
}

unless(defined $outDir){
    print STDERR "Output directory must be specified\n";
    pod2usage(-verbose => 1);
    exit;
}

if($ucAll){
    $uncompress = 1;
    $ucSeq = 1;
}

# Remember where we are now, then change wd to $outDir
my $wdOrg = cwd();
chdir($outDir) or die;

# Get & create the target path
my $rfPath = $outDir . getRfName($inDir);

# First check if a folder with that name already exists
if(-e $rfPath){
    warn "$rfPath already exists\n";
    my $i=1;
    while(-e "$rfPath.old.$i"){
	$i++;
    }
    warn "Renaming it to $rfPath.old.$i\n";
    rename($rfPath, "$rfPath.old.$i");
}

# Now create the output runfolder
mkpath($rfPath,2770) or die "Failed to create output runfolder '$rfPath': $!\n";

# Get a sisyphus object for the "new" runfolder
my $sisyphus = Molmed::Sisyphus::Common->new(PATH=>$rfPath, DEBUG=>$debug);
my $runfolder = $sisyphus->RUNFOLDER;

# Extract all files from the archive
find({wanted=>sub{unpackArch($sisyphus)},no_chdir=>1}, $inDir);

# Copy the MD5 files to the MD5 dir
unless(-e "$outDir/$runfolder/MD5"){
    mkdir("$outDir/$runfolder/MD5") or die;
}
system("cp", "-a", glob("$inDir/*.md5"), "$outDir/$runfolder/MD5");

if($uncompress || $ucSeq || $verify){
    if($uncompress || $ucSeq){
	print STDERR "Uncompressing and verifying...\n";
    }else{
	print STDERR "Verifying...\n";
    }
    find({wanted=>sub{unCompress($sisyphus,$uncompress,$ucSeq,$verify)},no_chdir=>1}, $sisyphus->PATH);
}

print STDERR "Completed\n";

sub unCompress{
    my $sisyphus = shift;
    my $uncompress = shift;
    my $ucSeq = shift;
    my $verify = shift;
    my $file = $File::Find::name;
    return unless(-f $file);
    return if($file =~ m/\.md5$/);
    if($file =~ m/(sequence\.txt|fastq)\.gz$/){
	if($ucSeq){
	    print "$file\n" unless($verify);
	    system("gunzip", "-N", $file)==0 or die "Failed to uncompress $file\n";
	    $file =~ s/\.gz$//;
	}
    }elsif($file =~ m/\.gz$/){
	if($uncompress){
	    print "$file\n" unless($verify);
	    system("gunzip", "-N", $file)==0 or die "Failed to uncompress $file\n";
	    $file =~ s/\.gz$//;
	}
    }
    if($verify){
	my $md5Org = $sisyphus->getMd5($file);
	my $md5New = $sisyphus->getMd5($file, -noCache=>1);
	if($md5Org eq $md5New){
	    print STDERR "$file OK\n";
	}else{
	    die "$file FAILED\n";
	}
    }
}

sub getRfName{
    my $inDir = shift;
    opendir(INDIR, $inDir);
    while(my $f = readdir(INDIR)){
	if($f =~ s/\.archive.md5//){
	    closedir(INDIR);
	    return($f);
	}
    }
    die "Unable to determine runfolder name\n";
}

sub unpackArch{
    my $sisyphus = shift;
    my $file = $File::Find::name;
    return if(-d $file);
    if($file =~ m/\.tar$/){
        system("tar xvf $file") == 0 or die "Failed to unpack $file\n";
    }elsif($file !~ m/.md5$/){
	print STDERR "$file\n";
        $sisyphus->copy($file, cwd() . '/' . $sisyphus->RUNFOLDER, {VERIFY=>0,RELATIVE=>1});
    }
}
