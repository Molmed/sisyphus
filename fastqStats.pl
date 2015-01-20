#!/usr/bin/perl -w

use FindBin;                # Find the script location
use lib "$FindBin::Bin/lib";# Add the script libdir to libs
use Molmed::Sisyphus::Libpath;

use strict;
use Getopt::Long;
use Pod::Usage;
use File::Find;
use PerlIO::gzip;
use File::Basename;
use Digest::MD5;


use Molmed::Sisyphus::QStat;
use Molmed::Sisyphus::Common qw(mkpath);

=head1 NAME

fastqStats.pl - Calculate statistics on CASAVA 1.8 generated fastq-files

=head1 SYNOPSIS

 fastqFilter.pl -help|-man
 fastqFilter.pl -runfolder <runfolder> -lane <lane> [-debug]

=head1 OPTIONS

=over 4

=item -h|-help

prints out a brief help text.

=item -m|-man

Opens the manpage.

=item -runfolder

Runfolder to run statistics on.

=item -indir

Folder containing the demultiplexed project folders. Defaults to "runfolder/Unaligned"

=item -outdir

Root folder for writing the statistics. Defaults to "Statistics" at the same level as -indir.
That is, if indir is "runfolder/Unaligned", then -outdir defaults to "runfolder/Statistics"

=item -lane

Only process files from <lane> [default all lanes].
Multiple lanes are specifed as a space separated list,
  e.g. -lane 1 3 5 7

=item -debug

Print debugging information

=back

=head1 DESCRIPTION

fastqStats.pl calculates various statistics from the fastq-files.

Assumes that the fastq files only contain reads that passed
the chastity filter.

The statistics are saved in a folder as the fastq-file in
a zip-file that can be read by Molmed::Sisyphus::QStat.

All files from the same project are collected to one file
per tag, read and lane.

=cut

# parse options
my($help,$man) = (0,0);
my($rfPath,$lane,$inDir,$outDir) = (undef,[],undef,undef);
our($debug) = 0;

GetOptions('help|?'=>\$help,
           'man'=>\$man,
           'runfolder=s' => \$rfPath,
	   'lane=s{1,8}' => $lane,
	   'indir=s' => \$inDir,
	   'outdir=s' => \$outDir,
           'debug' => \$debug,
          ) or pod2usage(-verbose => 0);
pod2usage(-verbose => 1)  if ($help);
pod2usage(-verbose => 2)  if ($man);

unless( defined $rfPath && -e $rfPath ){
    print STDERR "Runfolder not specified or does not exist\n";
    pod2usage(-verbose => 1);
    exit;
}

# Process all lanes by default
if(@{$lane}<1){
    $lane = [1,2,3,4,5,6,7,8];
}

my $sisyphus = Molmed::Sisyphus::Common->new(PATH=>$rfPath, DEBUG=>$debug);

$rfPath = $sisyphus->PATH;
my $machineType = $sisyphus->machineType();

unless($inDir){
    $inDir = "$rfPath/Unaligned";
}
unless($outDir){
    $outDir = dirname($inDir) . '/Statistics';
}
unless(-e $outDir){
    my $tries=0;
    until(-e $outDir){
	mkpath($outDir,2770) or warn "Failed to create path '$outDir': $!\n";
	$tries++;
	die "Giving up creating '$outDir'\n" if($tries > 2);
    }
}

my @remaining=();
foreach my $l (@{$lane}){
    if(! (-e "$outDir/fastqStats-L$l.complete" || -e "$outDir/fastqStats-L$l.complete.gz")){
	push @remaining, $l;
    }else{
	print STDERR "Lane $l already completed\n";
    }
}

$lane = [@remaining];

# Initialize the random generator and use a random seed based upon the flowcell id
my $fcid = $sisyphus->fcId() || "ABC123CXX";
my $rseed = 0;
foreach my $c (split //, $fcid) {
    $rseed += ord($c);
}
srand($rseed);
print STDERR "Using random seed $rseed based on fcId $fcid\n";

my %files;
if($machineType eq "hiseqx") {
    find({wanted => sub{findFastqHiSeqX(\%files, $lane)}, no_chdir => 1}, $inDir);
} else {
    find({wanted => sub{findFastq(\%files, $lane)}, no_chdir => 1}, $inDir);
}

my %checkSums;
foreach my $project(keys %files){
    foreach my $sample(keys %{$files{$project}}){
	my %statistics;
	foreach my $file (@{$files{$project}->{$sample}}){
	    print STDERR "IN: $file\n";

	    my($lane,$read,$tag) = (0,0,'');
#	    if($file =~ m/_([ACTG]+)_L(\d{3})_R(\d)_\d{3}/){
	    # Dual index tags contains a hyphen
	    if($file =~ m/_([ACTG]+-?[ACGT]*)_L(\d{3})_R(\d)_\d{3}/){
		$tag = $1;
		$lane = $2 + 0;
		$read = $3;
	    }elsif($file =~ m/_(S\d+)_L(\d{3})_R(\d)_\d{3}/){
                $tag = $1;
                $lane = $2 + 0;
                $read = $3;
	    elsif($file =~ m/_L(\d{3})_R(\d)_\d{3}/){
		$lane = $1 + 0;
		$read = $2;
	    }else{
		die "Failed to match name of input file '$file'\n";
	    }

	    my $stat;
	    if(exists $statistics{$project}->{$sample}->{$lane}->{$tag}->{$read}){
		$stat = $statistics{$project}->{$sample}->{$lane}->{$tag}->{$read};
	    }else{
		my $offset = $sisyphus->qType($file);
#		my $seqCount = $sisyphus->sampleSize($lane, $project, $sample, $tag);
#		print STDERR "Number of sequences: $seqCount\n";
		my $maxSeqSamples = 1e6;
		my $samplingDensity = 0.1; #$seqCount>$maxSeqSamples ? $maxSeqSamples/$seqCount : 1;
		my $outDir2 = "$outDir/Project_$project/Sample_$sample";
		if($project eq 'Undetermined_indices'){
		    $outDir2 = "$outDir/$project/Sample_$sample";
		}
		$stat = Molmed::Sisyphus::QStat->new(OFFSET=>$offset,RUNFOLDER=>$sisyphus,
						     PROJECT=>$project,SAMPLE=>$sample,
						     LANE=>$lane, READ=>$read, TAG=>$tag,
						     OUTDIR=>"$outDir/Project_$project/Sample_$sample",
						     INFILE=>$file,
						     MAXSAMPLES=>$maxSeqSamples,
						     SAMPLING_DENSITY=>$samplingDensity,
						    );
		$statistics{$project}->{$sample}->{$lane}->{$tag}->{$read} = $stat;
	    }

	    my $fhIn;
	    my $fileUncompressed = $file;
	    if($file =~ m/\.gz$/){
		$fileUncompressed =~ s/\.gz$//;
                open($fhIn, "zcat $file |") or die "Failed to open '$file': $!\n";
	    }else{
		open($fhIn, "<", $file) or die "Failed to open '$file': $!\n";
	    }

	    my $fileSum;
	    if(defined $checkSums{$fileUncompressed}){
		$fileSum = $checkSums{$fileUncompressed};
	    }else{
		$fileSum = Digest::MD5->new;
		$checkSums{$fileUncompressed} = $fileSum;
	    }

	    # This is where the real action is
	    fastqStats($fhIn,$stat,$fileSum);

	    close($fhIn);
	}

	# Dump the statistics to a file in the output dir
	# for later use by the report generators
	print STDERR "Dumping statistics\n";
	foreach my $lane (keys %{$statistics{$project}->{$sample}}){
	    foreach my $tag (keys %{$statistics{$project}->{$sample}->{$lane}}){
		foreach my $stat (values %{$statistics{$project}->{$sample}->{$lane}->{$tag}}){
		    my $read = $stat->read();
		    my $sample = $stat->sample();
		    if($tag eq '' && $stat->outdir() =~ m/Undetermined_indices/){
			$tag = 'Undetermined';
		    }elsif($tag eq ''){
			$tag = 'NoIndex';
		    }
		    my $dumpFile = $stat->outdir() . "/${sample}_${tag}_L" . sprintf('%03d', ${lane}) . "_R${read}.statdump";
		    print STDERR "$dumpFile\n" if($debug);
		    $stat->saveData("$dumpFile.zip");
		    # Calc & store the checksum for the dump
		    my $sum = $sisyphus->getMd5("$dumpFile.zip", -noCache=>1);
		    $sisyphus->saveMd5("$dumpFile.zip", $sum);
		}
	    }
	}
    }
}

# Write out the MD5 checksums
print STDERR "Writing MD5 checksums\n";
foreach my $file (keys %checkSums){
    # This checksum is for the uncompressed data
    my $md5 = $checkSums{$file}->hexdigest();
    $sisyphus->saveMd5($file,$md5);
    # Also calc&store the checksum for the compressed file if not already done as it should be
    my $foo = $sisyphus->getMd5("$file.gz") if(-e "$file.gz");;
}

mkdir("$rfPath/Statistics") unless(-e "$rfPath/Statistics");
foreach my $l (@{$lane}){
    my $file = "$rfPath/Statistics/fastqStats-L$l.complete";
    `touch $file`;
    # Calc & store the checksum for the file
    my $sum = $sisyphus->getMd5($file, -noCache=>1);
    $sisyphus->saveMd5($file, $sum);
}
print STDERR "Filtering complete\n";

sub findFastq{
    my $files = shift;
    my $lanes = shift;
    my $file = $_;
    if($file =~ m/\.fastq(\.gz)?$/){
	foreach my $l (@{$lanes}){
	    if($file =~ m/_L00${l}_/){
		my @path = split '/', $file;
		my $project = $path[-3];
		$project =~ s/^Project_//;
		my $sample = $path[-2];
		$sample =~ s/^Sample_//;
		push @{$files{$project}->{$sample}}, $_;
	    }
	}
    }
}

sub findFastqHiSeqX{
    my $files = shift;
    my $lanes = shift;
    my $file = $_;
    if($file =~ m/\.fastq(\.gz)?$/){
        foreach my $l (@{$lanes}){
            if($file =~ m/.+\/(.+)_\w+_L00${l}_/){
                my @path = split '/', $file;
                my $shiftIndex = $path[-3] eq 'Unaligned' ?  1 : $path[-2] eq 'Unaligned' ? 2 : 0;
                my $sample = $1;
                my $project = $shiftIndex != 2 ? $path[-3 + $shiftIndex] : $sample;
                push @{$files{$project}->{$sample}}, $_;
            }
        }
    }
}

sub fastqStats{
    my $fhIn = shift;
    my $stat = shift || die "No stat object given\n";
    my $md5 = shift || die "No digest object given\n";

    while(<$fhIn>){
	my $head = $_;
	my $seq = <$fhIn>;
	my $head2 = <$fhIn>;
	my $qstring = <$fhIn>;
	$md5->add($head . $seq . $head2 . $qstring);

	# Header example
	# Indexed
	# @HWI-ST344:98:AB0B7FABXX:1:1101:1107:2052 1:N:0:CGATGT
	# Undetermined index
	# @HWI-ST344:113:D030AACXX:1:1101:1183:2039 1:N:0:

	# $head[10] is the actual index tag, including errors
#	chomp($head);
#	my @head = split /:| /, $head;
#	unless(defined $head[10]){
#	    $head[10] = '';
#	}

	chomp($qstring);
	$stat->addDataPoint($seq, $qstring);
    }
}
