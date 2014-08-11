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
use Digest::MD5;

use Molmed::Sisyphus::Common qw(mkpath);


=head1 NAME

archive.pl - Archive a runfolder

=head1 SYNOPSIS

 archive.pl -help|-man
 archive.pl -runfolder <runfolder> -outdir <outdir> [-debug]

=head1 OPTIONS

=over 4

=item -h|-help

prints out a brief help text.

=item -m|-man

Opens the manpage.

=item -runfolder

The runfolder to pack.

=item -outdir

The directory to create the archive copy in.

=item -verifyOnly

Assume the archiving has already been done and only do the verification.

=item -swestore

Start archive2swestore.pl when done

=item -debug

Print debugging information

=back

=head1 DESCRIPTION

archive.pl is a script for creating a copy of runfolder suitable for archival.
All files except those in a compressed format like png and jpeg are compressed
with gzip and the checksums of both original and compressed files are written
to special files. The files are copied to the target and verified.

Two archives are created, one a tar-archive of all files except the fastq-files,
and one with the project folders suitable for delivery to clients.

This results in the following structure:

121120_SN866_0192_BD1H31ACXX/
121120_SN866_0192_BD1H31ACXX/121120_SN866_0192_BD1H31ACXX.tar
121120_SN866_0192_BD1H31ACXX/Projects/LE-0082/
121120_SN866_0192_BD1H31ACXX/Projects/LE-0082/Report.tar.gz
121120_SN866_0192_BD1H31ACXX/Projects/LE-0082/Sample_123/
121120_SN866_0192_BD1H31ACXX/Projects/LE-0082/Sample_123/123_TTAGGC_L008_R1_001.fastq.gz

This requires that extract_project has already been run with the outbox set to <runfolder>/Projects/!

=head1 FUNCTIONS

=cut

# Parse options
my($help,$man) = (0,0);
my($rfPath,$outDir,$verifyOnly,$swestore) = (undef,undef,0,0);
our($debug) = 0;

GetOptions('help|?'=>\$help,
	   'man'=>\$man,
	   'runfolder=s' => \$rfPath,
	   'outdir=s' => \$outDir,
	   'verifyOnly' =>\$verifyOnly,
	   'swestore' =>\$swestore,
	   'debug' => \$debug,
	  ) or pod2usage(-verbose => 0);
pod2usage(-verbose => 1)  if ($help);
pod2usage(-verbose => 2)  if ($man);

unless(defined $rfPath && -e $rfPath){
    print STDERR "Runfolder not specified or does not exist\n";
    pod2usage(-verbose => 1);
    exit;
}

unless(defined $outDir){
    print STDERR "Output directory must be specified\n";
    pod2usage(-verbose => 1);
    exit;
}

# Create a new sisyphus object for common functions
my $sisyphus = Molmed::Sisyphus::Common->new(PATH=>$rfPath, DEBUG=>$debug);
$rfPath = $sisyphus->PATH;
$outDir =~ s:/+$::;

# Add the year and month to the outdir if not already included
unless($outDir =~ m/201\d-[0123]\d$/){
    if($sisyphus->RUNFOLDER =~ m/(1\d)([01]\d)[0123]\d_/){
	$outDir .= "/20$1-$2";
    }
}

$outDir = "$outDir/" . $sisyphus->RUNFOLDER;

# Make outDir absolute, if it is not already
$outDir = abs_path($outDir) unless( $outDir =~ m(^/) );

my $runfolder = $sisyphus->RUNFOLDER;
my %checksums = (ORIGINAL=>{}, COMPRESSED=>{});

unless($verifyOnly){
  # First create the output runfolder
  if(-e $outDir){
    warn "$outDir already exists\n";
    my $i=1;
    while(-e "$outDir.old.$i"){
      $i++;
    }
    warn "Renaming it to $outDir.old.$i\n";
    rename($outDir, "$outDir.old.$i");
  }

  mkpath($outDir,2770) or die "Failed to create output runfolder '$outDir': $!\n";


  # check that all projects have been processed
  my $sampleSheet = $sisyphus->readSampleSheet();
  foreach my $proj (keys %{$sampleSheet}){
    unless(-e "$rfPath/Statistics/Project_$proj/extractProject.complete" || -e "$rfPath/Statistics/Project_$proj/extractProject.complete.gz"){
      die "$proj has not been processed, will not archive!"
    }
  }

  # First make one big tar-file of everything except fastq-files and the Projects-dir.
  archiveRunfolder($sisyphus, \%checksums, $outDir);

  # Then make one tar-file per project containing reports and plots
  my %projMd5fh;
  foreach my $proj (keys %{$sampleSheet}){
    my $sums = { ORIGINAL=>{}, COMPRESSED=>{} };
    archiveProjectReports($proj, $sisyphus, $sums, $outDir);
    foreach my $src (qw(ORIGINAL COMPRESSED)){
      my $md5fh;
      if($src eq 'ORIGINAL'){
	open($md5fh, '>', "$outDir/Projects/$proj/$runfolder.original.md5") or die "Failed to open '$outDir/$runfolder/Projects/$proj/$runfolder.original.md5': $!";
      }else{
	open($md5fh, '>', "$outDir/Projects/$proj/$runfolder.compressed.md5") or die "Failed to open '$outDir/$runfolder/Projects/$proj/$runfolder.compressed.md5': $!";
      }
      $projMd5fh{$proj}->{$src} = $md5fh;
      foreach my $key (keys %{$sums->{$src}}){
	$checksums{$src}->{$key} = $sums->{$src}->{$key};
	(my $file = $key) =~ s:^$rfPath/Projects/::;
	print $md5fh "$sums->{$src}->{$key}  $file\n";
      }
    }
  }
  
  # Archive the MiSeq_Runfolder.tar.gz if it exist.
  if(-e "MiSeq_Runfolder.tar.gz") {
    $sisyphus->copy("MiSeq_Runfolder.tar.gz", $outDir, {VERIFY=>1,LINK=>1,RELATIVE=>0});
    $sisyphus->copy("MD5/checksums.miseqrunfolder.md5","$outDir/checksums.miseqrunfolder.org.md5", {VERIFY=>1,LINK=>1,RELATIVE=>0});
  }

  # Then copy/link the fastq-files. If the file exists in both the project directory
  # and the Unaligned/Excluded directory, archive only the copy in the project directory
  # Write the skipped files to a list
  my $skipped = archiveFastq($sisyphus, \%checksums, $outDir, [keys %{$sampleSheet}], \%projMd5fh);
  open(my $skFh, '>', "$outDir/$runfolder.skipped.txt") or die "Failed to open '$outDir/$runfolder.skipped.txt': $!";
  print $skFh "# Files skipped because they are identical to an already included file\n";
  foreach my $key (keys %{$skipped}){
    (my $file1 = $key) =~ s/^$rfPath/$runfolder/;
    (my $file2 = $skipped->{$key}) =~ s/^$rfPath/$runfolder/;
    print $skFh "$file1\t$file2\n";
  }
  close($skFh);

  open(my $orgFh, '>', "$outDir/$runfolder.original.md5") or die "Failed to open '$outDir/$runfolder.original.md5': $!";
  foreach my $key (keys %{$checksums{ORIGINAL}}){
    (my $file = $key) =~ s/^$rfPath/$runfolder/;
    print $orgFh "$checksums{ORIGINAL}->{$key}  $file\n";
  }
  close($orgFh);

  open(my $compFh, '>', "$outDir/$runfolder.compressed.md5") or die "Failed to open '$outDir/$runfolder.compressed.md5': $!";
  foreach my $key (keys %{$checksums{COMPRESSED}}){
    (my $file = $key) =~ s/^$rfPath/$runfolder/;
    print $compFh "$checksums{COMPRESSED}->{$key}  $file\n";
  }
  close($compFh);

  print STDERR "Archiving done, starting verification\n";
} # end unless $verifyOnly

# First verify that all files that should be archived are included in
# the (compressed) checksums file

# Begin by reading the file we just wrote
my %compressedMd5;
open(my $compFh, '<', "$outDir/$runfolder.compressed.md5") or die "Failed to read '$outDir/$runfolder.compressed.md5': $!";
while(<$compFh>){
  chomp;
  my($md5,$path)=split /  /, $_;
  $compressedMd5{$path} = $md5;
}

# Let a sub check the original dirtree against the list of files
verifyFileList($sisyphus, \%compressedMd5, $outDir);

# Now verify that we can read all (exept fastq) files from the tar-files created
my %archiveMd5;
if(verifyTarFiles($outDir, \%compressedMd5, \%archiveMd5)){
    print STDERR "Tar files passed OK\n";
}else{
    print STDERR "Tar files FAILED\n";
    exit 1;
}

# If we have come this far, make a new MD5-file for tar- and fastq-files
print STDERR "Writing archive MD5-sums\n";
open(my $archFh, '>', "$outDir/$runfolder.archive.md5") or die "Failed to open '$outDir/$runfolder.archive.md5': $!";
foreach my $key (keys %archiveMd5){
  my $file = $key;
  $file =~ s:$outDir:$runfolder:;
  print $archFh "$archiveMd5{$key}  $file\n";
}
close($archFh);


print STDERR "$runfolder archive verified\n";


# Now kick off a script to upload to SweStore and verify the upload
# But first we have to unpack ourself if we were started from
# the Sisyphus dir in the runfolder
find(\&_gunzipScriptBin, $FindBin::Bin);

if(-e "$rfPath/sisyphus.yml.gz"){
    system("gunzip $rfPath/sisyphus.yml.gz")==0 or die "Failed to gunzip '$rfPath/sisyphus.yml.gz': $!";
}

if($swestore){
    my $debugFlag = '';
    $debugFlag = '-debug', if($debug);
    print STDERR "Starting archive2swestore.pl with\n";
    print STDERR qq($FindBin::Bin/archive2swestore.pl -runfolder $outDir -config $rfPath/sisyphus.yml $debugFlag\n);
    exec ($FindBin::Bin."/archive2swestore.pl",
	  '-runfolder', $outDir,
	  '-config', "$rfPath/sisyphus.yml",
	  $debugFlag);
    # Remaining options should be read from sisyphus.yml
}


# Sub for gunzip of Sisyphus directory
sub _gunzipScriptBin{
    if(m/\.pl\.gz/){
	system('gunzip', $_)==0 or die;
	s/\.gz$//;
	system('chmod','+x', $_)==0 or die;
    }elsif(m/\.pm\.gz/){
	system('gunzip', $_)==0 or die;
    }
}


=pod

=head2 verifyTarFiles()

 Title   : verifyTarFiles()
 Usage   : verifyTarFiles($outDir, \%checksums)
 Function: Read all tar-files from an archive directory and verify against the checksums
 Example :
 Returns : nothing
 Args    : The archive directory to start in
           A hashref with the expected files. Path as key, checksum as value

=cut

sub verifyTarFiles{
    my $archDir = shift;
    my $checksums = shift;
    my $archiveMd5 = shift; # Used to store checksums for the archive files

    my $ok = 1;

    # Make a reverse copy of the checksum hash
    my %fileSums;
    foreach my $file (keys %{$checksums}){
	push @{$fileSums{$checksums->{$file}}}, $file;
    }

    # Assume basename of dir is runfolder name
    my $rfName = basename($archDir);

    # There should be a tar file for the runfolder
    my $rfTar = "$archDir/$rfName.tar";
    unless(-e $rfTar){
	die "$rfTar does not exist";
    }

    print STDERR "Verifying $rfTar ...\n";
    if(verifyTar($rfTar,undef,\%fileSums, $archiveMd5, $rfName)){
      print STDERR "$rfTar\tOK\n";
    }else{
	print STDERR "$rfTar\tFAILED\n";
	$ok = 0;
    }

    opendir(my $projDir, "$archDir/Projects/");
    foreach my $proj ( grep {!/^\.{1,2}$/} readdir($projDir) ){
	print STDERR "Verifying $archDir/Projects/$proj/$rfName.tar ...\n";
	if(verifyTar("$archDir/Projects/$proj/$rfName.tar", "$rfName/Projects", \%fileSums, $archiveMd5, $rfName)){
	    print STDERR "$archDir/Projects/$proj/$rfName.tar\tOK\n";
	}else{
	    print STDERR "$archDir/Projects/$proj/$rfName.tar\tFAILED\n";
	    $ok = 0;
	}
    }

    # The remaining files in %fileSums should be single files which we will check
    # after upload to SweStore, so just check that they exist
    # Make a reverse lookup on the checksums

    my @missing;
    foreach my $sum (keys %fileSums){
	unless(grep /^SEEN$/, @{$fileSums{$sum}}){
	    foreach my $file (@{$fileSums{$sum}}){
		next if($file eq 'SEEN');
		if(-e "$archDir/../$file"){
		    # Save the checksum for single files
		    $archiveMd5->{$file} = $checksums->{$file};
		}else{
		    push @missing, $file;
		}
	    }
	}
    }
    if(@missing){
      print STDERR "The following files are missing from the archive\n";
      print STDERR join "\n", @missing;
      print STDERR "\n";
      $ok = 0;
    }else{
      print STDERR "All files were included\n";
    }
    return $ok;
}


sub verifyTar{
    my $tarFile = shift;
    my $dirName = shift;
    my $fileSums = shift;
    my $archiveMd5 = shift;
    my $rfName = shift;
    my $ok = 1;

    open(my $tarFh, '-|', qq(tar xf $tarFile --to-command 'echo -n "\$TAR_FILENAME\t"; md5sum')) or die $!;#'$FindBin::Bin/verifyTarHelper.sh'") or die $!;
    while(<$tarFh>){
	chomp;
	s/  -$//;
	my($f,$sum) = split /\t/, $_;
#	print STDERR "$f -- $sum\n";
	$f = "$dirName/$f" if(defined $dirName);
	if(exists $fileSums->{$sum} && grep /^$f$/, @{$fileSums->{$sum}}){
	    push @{$fileSums->{$sum}}, 'SEEN';
	}else{
	    print STDERR "Checksum for $f does not exist\n";
	    $ok = 0;
	}
    }

    if($ok){
      open(my $fh, $tarFile) or die "Failed to open $tarFile: $!";
      my $sum = Digest::MD5->new->addfile($fh)->hexdigest;
      $archiveMd5->{$tarFile} = $sum;
      close($fh);
    }
    return $ok;
}

=pod

=head2 verifyFileList()

 Title   : verifyFileList()
 Usage   : verifyFileList($sisyphus, \%checksums)
 Function: Recurse the runfolder and verify that all files are included in the checksums hash
 Example :
 Returns : nothing
 Args    : A Sisyphus::Common object for the runfolder to archive
           A hashref with the expected files. Path as key, checksum as value

=cut

sub verifyFileList{
    my $sisyphus = shift;
    my $checksums = shift;

    # Make a copy of all filenames
    my %files;
    @files{keys %{$checksums}} = ();

    # Make a reverse lookup on the checksums
    my %revSums;
    @revSums{values %{$checksums}} = ();

    my $rfPath = $sisyphus->PATH;
    my $dirMask = dirname($rfPath);

    # This should delete all entries in %files that are present in the runfolder
    # So files should be empty when sub returns
    my @missed = verifyRecurseRunfolder($rfPath,$dirMask,\%files);

    if(keys %files > 0){
	print STDERR "Found files in checksum file that are missing from runfolder\n";
	print STDERR join("\n", keys %files), "\n";
	exit 1;
    }

    my @skipped;
    foreach my $file (@missed){
	# Skip the sisyphus md5-sum files
	next if($file=~ m:MD5/[^/]+\.md5$:);

	# If the checksum exists in the list we got, then this file
	# is included with another name
	# Sisyphus should have the checksum in cache, so we hopefully
	# do not have the overhead of calculating it here
	my $md5 = $sisyphus->getMd5($file);
	next if(exists $revSums{$md5});
	push @skipped, $file;
    }
    if(@skipped){
      print STDERR "The following files are skipped from the archive\n";
      print join "\n", @skipped;
      print "\n---END SKIPPED---\n\n";
    }

}

=pod

=head2 verifyRecurseRunfolder()

 Title   : verifyRecurseRunfolder()
 Usage   : verifyRecurseRunfolder($dirPath, $dirMask, \%files)
 Function: Recurse the runfolder and verify remove any seen files from the %files hash
 Example :
 Returns : a list of files that are not present in the %files hash
 Args    : A directory to start in
           A directory mask to remove from the path for finding the hash key
           A hashref with the expected files. Path as key

=cut

sub verifyRecurseRunfolder{
    my $dir = shift;
    my $dirMask = shift;
    my $files = shift;

    my @missed;

    opendir(my $dh, $dir) or die;
    foreach my $file ( grep {!/^\.{1,2}$/} readdir($dh) ){
	if(-d "$dir/$file"){
	    push @missed, verifyRecurseRunfolder("$dir/$file", $dirMask, $files);
	}else{
	    my $path = "$dir/$file";
	    $path =~ s:^$dirMask/*::;
	    if(exists $files->{$path}){
		delete $files->{$path};
	    }else{
		push @missed, $path;
	    }
	}
    }
    return @missed;
}



=pod

=head2 archiveRunfolder()

 Title   : archiveRunfolder
 Usage   : archiveRunfolder($sisyphus, \%checksums, $outDir)
 Function: Recursively archive the contentes of runfolder $inDir to $outDir
           But skip the fastq.gz files
 Example :
 Returns : nothing
 Args    : A Sisyphus::Common object for the runfolder to archive
           A hashref for saving checksums of the archived files
           The absolute path of the output directory

=cut

sub archiveRunfolder{
  my $sisyphus = shift;
  my $checksums = shift;
  my $outDir = shift;
  my $rfPath = $sisyphus->PATH;
  my $rfName = $sisyphus->RUNFOLDER;

  my $dirMask = dirname($rfPath);
  my $tarFile = "$outDir/$rfName.tar";
  $tarFile =~ s:/+:/:g; # Remove multiple slashes

  open(my $tarPipe, qq(| tar cf "$tarFile" --no-recursion -C "$dirMask" --files-from -) )
    or die qq(Failed to open tarpipe 'tar cf "$tarFile" --no-recursion -C "$dirMask" --files-from -'\n\t$!\n);

  compressMiSeqRunFolder($rfPath, $checksums, $sisyphus, $dirMask);

  recurseRunfolder($rfPath, $tarPipe, $checksums, $sisyphus, $dirMask);
}

=pod

=head2 recurseRunfolder()

 Title   : recurseRunfolder
 Usage   : recurseRunfolder($dir, $tarFh, \%checksums, $sisyphus, $dirMask)
 Function: Recurse a runfolder and write all files to be included to the open
           tar pipe/filehandle.
 Example :
 Returns : nothing
 Args    : The path to recurse from
           An open filehandle for writing filenames to tar
           A hashref for saving checksums of the archived files
           A Sisyphus::Common object for the runfolder to archive
           The part of the path to remove from the file's path

=cut

sub recurseRunfolder {
  my $dir = shift;
  my $tarPipe = shift;
  my $checksums = shift;
  my $sisyphus = shift;
  my $dirMask = shift;

  if(basename($dir) eq 'MD5'){
    print STDERR "Skipping MD5 dir '$dir'\n" if($debug);
    return;
  }

  if(basename($dir) eq 'Projects'){
    print STDERR "Skipping Projects dir '$dir'\n" if($debug);
    return;
  }

  if(basename($dir) eq 'MiSeq_Runfolder'){
    print STDERR "Skipping MiSeq_Runfolder dir '$dir'\n" if($debug);
    return;
  }

  opendir(my $dh, $dir) or die;
  foreach my $file ( grep {!/^\.{1,2}$/} readdir($dh) ){

    # Skip fastq files
    next if($file =~ m/\.fastq(\.gz)?$/);

    if(-d "$dir/$file"){
      # Recurse into sub directories
      recurseRunfolder("$dir/$file", $tarPipe, $checksums, $sisyphus, $dirMask);
    }else{
      # Skip archiving logs from sbatch, as this might be written to
      # by self
      if( !($dir =~ m:slurmscripts/log: && $file =~ /^Arch-.*\.log/i) && !($file =~/MiSeq_Runfolder\.tar\.gz/)){
	addFile($dir, $file, $tarPipe, $checksums, $sisyphus, $dirMask);
      }
    }
  }
  closedir($dh);
}

=pod

=head2 addFile()

 Title   : addFile
 Usage   : addFile($dir, $file, $tarFh, \%checksums, $sisyphus, $dirMask)
 Function: Make sure the file is compressed and get the checksum, then
           write the file path to be included to the open tar pipe/filehandle.
 Example :
 Returns : nothing
 Args    : The directory path of the file
           The filename
           An open filehandle for writing filenames to tar
           A hashref for saving checksums of the archived files
           A Sisyphus::Common object for the runfolder to archive
           The part of the path to remove from the file's path

=cut

sub addFile{
  my $inDir = shift;
  my $file = shift;
  my $tarPipe = shift;
  my $checksums = shift;
  my $sisyphus = shift;
  my $dirMask = shift;

  # Compress files if necessary, skip compressing the reports and checksums and README in the project dir
  if($file =~ m/\.(png|jpg|jpeg|zip)$/i ||
     $file =~ m/(summary)?report.(htm|xm|xs)l/i ||
     "$inDir/$file"=~m:Projects/.*/(checksums|README|.*\.md5):){
    $checksums->{ORIGINAL}->{"$inDir/$file"} = $sisyphus->getMd5("$inDir/$file");
    $checksums->{COMPRESSED}->{"$inDir/$file"} = $sisyphus->getMd5("$inDir/$file");
  }elsif($file =~ m/\.(gz|bz2)$/i){
    $checksums->{COMPRESSED}->{"$inDir/$file"} = $sisyphus->getMd5("$inDir/$file");
    (my $original = $file) =~ s/\.(gz|bz2)$//i;
    my $md5 = $sisyphus->getMd5("$inDir/$original", -skipMissing=>1);
    if(defined $md5){
      $checksums->{ORIGINAL}->{"$inDir/$original"} = $md5;
    }else{
      $checksums->{ORIGINAL}->{"$inDir/$file"} = $sisyphus->getMd5("$inDir/$file");
    }
  }elsif(! -l "$inDir/$file"){ # Do not checksum symlinks
    $checksums->{ORIGINAL}->{"$inDir/$file"} = $sisyphus->getMd5("$inDir/$file");
    $file = $sisyphus->gzip("$inDir/$file"); # Gzip returns abs path
    $file =~ s:^$inDir/::; # Make $file relative again
    $checksums->{COMPRESSED}->{"$inDir/$file"} = $sisyphus->getMd5("$inDir/$file");
  }

  my $path = "$inDir/$file";
  $path =~ s:^$dirMask/*::;
  print $tarPipe "$path\n" || die "Failed to write $path to tarPipe";
}


=pod

=head2 archiveProjectReports()

 Title   : archiveProjectReports
 Usage   : archiveProjectReports($proj,$sisyphus,\%checksums, $outDir)
 Function: Archive the contentes of the report for $proj
 Example :
 Returns : A hashref with md5sums of the included files
 Args    : The name of the project to include
           A Sisyphus::Common object for the runfolder to archive
           A hashref for saving checksums of the archived files
           The absolute path of the output directory

=cut

sub archiveProjectReports{
    my $proj = shift;
    my $sisyphus = shift;
    my $checksums = shift;
    my $outDir = shift;
    my $rfPath = $sisyphus->PATH;
    my $rfName = $sisyphus->RUNFOLDER;

    my $dirMask = "$rfPath/Projects/";
    my $tarFile = "$outDir/Projects/$proj/$rfName.tar";
    $tarFile =~ s:/+:/:g; # Remove multiple slashes

    unless(-e dirname($tarFile)){
	mkpath(dirname($tarFile), 2770);
    }

    open(my $tarPipe, qq(| tar cf "$tarFile" --no-recursion -C "$dirMask" --files-from -) )
	or die qq(Failed to open tarpipe 'tar cf "$tarFile" --no-recursion -C "$dirMask" --files-from -'\n\t$!\n);

    recurseProjectReports("$rfPath/Projects/$proj", $tarPipe, $checksums, $sisyphus, $dirMask);
}

sub recurseProjectReports{
  my $dir = shift;
  my $tarPipe = shift;
  my $checksums = shift;
  my $sisyphus = shift;
  my $dirMask = shift;

  opendir(my $dh, $dir) or die "Failed to open $dir: $!";
  foreach my $file ( grep {!/^\.{1,2}$/} readdir($dh) ){

    # Skip fastq files
    next if($file =~ m/\.fastq(\.gz)?$/);

    if(-d "$dir/$file"){
	# Recurse into sub directories
	recurseProjectReports("$dir/$file", $tarPipe, $checksums, $sisyphus, $dirMask);
    }else{
	addFile($dir, $file, $tarPipe, $checksums, $sisyphus, $dirMask);
    }
  }
  closedir($dh);
}

=pod

=head2 archiveFastq()

 Title   : archiveFastq
 Usage   : archiveFastq($sisyphus,\%checksums, $outDir, $projects, $projMd5fh)
 Function: Add the fastq files to the archive. Only include one copy of each file,
           regardless of location. Priority is given the files located in project
           directories.
 Example :
 Returns : A hashref with md5sums of the included files
 Args    : A Sisyphus::Common object for the runfolder to archive
           A hashref for saving checksums of the archived files
           The absolute path of the output directory
           An arrayref of the project directories
           A hashref with open filehandles for each projects checksum files, project as key

=cut

sub archiveFastq{
    my $sisyphus = shift;
    my $checksums = shift;
    my $outDir = shift;
    my $projects = shift;
    my $projMd5fh = shift;

    my $rfPath = $sisyphus->PATH;
    my $rfName = $sisyphus->RUNFOLDER;

    my $skipped = {};

    # Start with the fastq-files in the Projects folder
    # And keep track of which we have already seen
    my %seen;
    foreach my $dir (@{$projects}, "Unaligned", "Excluded"){
	my $sums = {COMPRESSED=>{}, ORIGINAL=>{}};
	if($dir eq "Unaligned"||$dir eq "Excluded"){
	    next unless(-e "$rfPath/$dir");
	    recurseFastq($sisyphus, "$rfPath/$dir", "$outDir/$dir", $sums, \%seen, $skipped);
	}else{
	    next unless(-e "$rfPath/Projects/$dir");
	    recurseFastq($sisyphus, "$rfPath/Projects/$dir", "$outDir/Projects/$dir", $sums, \%seen, $skipped);
	}
	foreach my $src (qw(ORIGINAL COMPRESSED)){
	    foreach my $key (keys %{$sums->{$src}}){
		unless($dir eq "Unaligned" || $dir eq "Excluded"){
		    (my $file = $key) =~ s:^$rfPath/Projects/::;
		    print {$projMd5fh->{$dir}->{$src}} "$sums->{$src}->{$key}  $file\n";
		}
		$checksums->{$src}->{$key} = $sums->{$src}->{$key};
	    }
	}
    }
    return($skipped);
}

sub recurseFastq{
    my $sisyphus = shift;
    my $indir = shift;
    my $outdir = shift;
    my $checksums = shift;
    my $seen = shift;
    my $skipped = shift;
    my $rfName = $sisyphus->RUNFOLDER;
    my $rfPath = $sisyphus->PATH;

    opendir(my $dh, $indir) or die;
    foreach my $file ( grep {!/^\.{1,2}$/} readdir($dh) ){
	if(-d "$indir/$file"){
	    # Recurse into sub directories
	    recurseFastq($sisyphus, "$indir/$file", "$outdir/$file", $checksums, $seen, $skipped);
	}elsif($file =~ m/\.fastq(\.gz)?$/){
	    my $srcMd5 = $sisyphus->getMd5("$indir/$file");
	    if(exists $seen->{"$file-$srcMd5"} && $seen->{"$file-$srcMd5"}){
		$skipped->{"$indir/$file"} = $seen->{"$file-$srcMd5"};
	    }else{
		my ($target,$md5) = $sisyphus->copy("$indir/$file", $outdir, {VERIFY=>1,LINK=>1,RELATIVE=>0});
		$seen->{"$file-$srcMd5"} = "$indir/$file";
		if($file=~m/\.gz$/){
		    $checksums->{COMPRESSED}->{"$indir/$file"} = $md5;
		}
		(my $orgFile = $file) =~ s/\.gz$//;
		my $orgSum = $sisyphus->getMd5("$indir/$orgFile", -skipMissing=>1);
		if(defined $orgSum){
		    $checksums->{ORIGINAL}->{"$indir/$orgFile"} = $orgSum;
		}
	    }
	}
    }
    closedir($dh);
}

=pod

=head2 compressMiSeqRunFolder()

 Title   : compressMiSeqRunFolder
 Usage   : compressMiSeqRunFolder()($dir, $tarPipe, \%checksums, $sisyphus, $dirMask)
 Function: Compress the MiSeq_Runfolder if it exists. 
 Example :
 Return  : nothing
 Args    : The directory path of the file
           An open filehandle for writing filenames to tar
           A hashref for saving checksums of the archived files
           An open filehandle for writing filenames to tar
           A Sisyphus::Common object for the runfolder to archive
           The part of the path to remove from the file's path

=cut

sub compressMiSeqRunFolder{
    my $inDir = shift;
    my $checksums = shift;
    my $sisyphus = shift;
    my $dirMask = shift;

    my $file = 'MiSeq_Runfolder';
    my $md5Sum = 'MD5/checksums.miseqrunfolder.md5';

    if(-e  "$inDir/$file.tar.gz") {
	print "Compressed MiSeq_Runfolder already exists!\n";
	return;
    }

    if( -d "$inDir/$file"){
        $file = $sisyphus->gzipFolder("$file","$inDir/$md5Sum"); # Gzip returns abs path
        $file =~ s:^$inDir/::; # Make $file relative again
        $checksums->{COMPRESSED}->{"$inDir/$file"} = $sisyphus->getMd5("$inDir/$file");
    }
}
