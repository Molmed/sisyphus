package Molmed::Sisyphus::Common;

use base 'Exporter';
our @EXPORT_OK = ('mkpath');

use strict;
use Molmed::Sisyphus::Libpath;
use Carp;
use Cwd qw(abs_path cwd);
use Digest::MD5;
use File::Basename;
use XML::Simple;
use File::Copy ();
use PerlIO::gzip;
use FindBin;
use YAML::Tiny;
use File::Find;
#use Hash::Util;
use File::Path 'rmtree';
use Fcntl qw(:flock SEEK_END :mode); # Import LOCK_*, mode and SEEK_END constants

our $AUTOLOAD;

=pod

=head1 NAME

Molmed::Sisyphus::Common - Common functions for operating on runfolder data.

=head1 SYNOPSIS

use Molmed::Sisyphus::Common;

my $sisyphus =  Molmed::Sisyphus::Common->new(
  PATH=>$rfPath,
  THREADS=>$nThreads,
  VERBOSE=>$verbose,
  DEBUG=>$debug
 );

=head1 DESCRIPTION

This module contains some common functions for scripts in the Sisyphus suite.

=head1 CONSTRUCTORS

=head2 new()

=over 4

=item PATH

The path to the runfolder to work on.

=item THREADS

Number of threads to use for threading applications (pigz).

=item VERBOSE

Print information on what is done.

=item DEBUG

Print debug information.

=back

=cut

sub new{
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = {@_};

    # Check the path
    unless(defined $self->{PATH} &&  -e $self->{PATH}){
	die "Runfolder path must be specified and a valid path\n";
    }
    $self->{PATH} = abs_path($self->{PATH});
    $self->{RUNFOLDER} = basename($self->{PATH});

    if(defined $self->{DEBUG}){
	$self->{VERBOSE} = 1;
    }

    if(! exists $self->{THREADS}){
	$self->{THREADS} = 8;
    }

    bless ($self, $class);
    return $self;
}

sub AUTOLOAD {
    my $self = shift;
    my $type = ref($self)
        or confess "$self is not an object";

    return if $AUTOLOAD =~ /::DESTROY$/;

    my $name = $AUTOLOAD;
    $name =~ s/.*://;   # strip fully-qualified portion
    $name =~ tr/a-z/A-Z/; # Use uppercase

    unless ( exists $self->{$name} ) {
        confess "Can't access `$name' field in class $type";
    }
    return $self->{$name};
}

=head1 SELECTORS

The following selectors are available:

=over

=item PATH - The full path to the runfolder, including the runfolder name

=item RUNFOLDER - The name of the runfolder, excluding the path

=item DEBUG - bool

=item VERBOSE - bool

=back

=cut

=pod

=head2 convertHiSeqXOutputFolder()

 Title   : convertHiSeqXOutputFolder
 Usage   : $sisyphus->convertHiSeqXOutputFolder()
 Function: convert the output folder created by bcl2fastq 2.15 into
           the format created by bcl2fastq 1.8
 Example :
 Returns :
 Args    : none

=cut

sub convertHiSeqXOutputFolder{
    my $self = shift;
    #Input and output directory for data
    my $unaligned = "$self->{PATH}/Unaligned";
    confess "Failed to find folder $unaligned\n" unless -e $unaligned;

    #Import the sampleSheet, will be used to process the files.
    my $sampleSheet = $self->readSampleSheet();
    my $sampleSheetHeader = $self->getSampleSheetHeader();

    my $projectPrefix = "Project_";
    my $samplePrefix = "Sample_";
    my $sampleLanePrefix = "Sample_lane";
    my $undeterminedFolder = "Undetermined_indices";
    my $basecallStatsPrefix = "Basecall_Stats_";
    
    #Create a list of all files and folders in the input directory.
    opendir(DH, $unaligned) or die "Couldn't open dir: $unaligned!";
    my @files = readdir(DH);
    closedir(DH);
    #Loop through all found files/folders.
    foreach my $file (@files) {
        #Ignore folders that will be created by this function. The expected input folder shouldn't
        #contain any of these folders.
        if($file =~/^\.*$|^Undetermined_indices$|^Project_.*$|^sisyphus-temp$|^Basecall_Stats/) {
            next;
        } elsif($file =~ /Undetermined_S[0-9]*_L([0-9]*)_R[1|2|3]{1}_[0-9]{3}\.fastq\.gz/) {
            #All fastq files that only contain unidentified reads will be moved into a folder named
            #Sample_lane"index", which will be located inside a folder named Undetermined_indices.
            my $laneId = $1;
            $laneId =~ s/^[0]+//g;
            $laneId =~ s/^[0]+//g;
            #Create the folder if it doesn't exist.
            mkdir "$unaligned/$undeterminedFolder" unless -e "$unaligned/$undeterminedFolder";
            mkdir "$unaligned/$undeterminedFolder/$sampleLanePrefix$laneId" unless -e "$unaligned/$undeterminedFolder/$sampleLanePrefix$laneId";
            #Move the file.
            File::Copy::move("$unaligned/$file","$unaligned/$undeterminedFolder/$sampleLanePrefix$laneId/")
                or die "Couldn't move $unaligned/$file into $unaligned/$undeterminedFolder/$sampleLanePrefix$laneId/";
        } elsif($file =~ /^Stats$|^Reports$/) {
            #Statistics and reports will be placed in a folder named Basecall_Stats_"flowcellId".
            #Create folder
            mkdir "$unaligned/$basecallStatsPrefix" . $self->fcId() unless -e "$unaligned/$basecallStatsPrefix" . $self->fcId();
            #Move folder
            File::Copy::move("$unaligned/$file","$unaligned/$basecallStatsPrefix" . $self->fcId() . "/$file");
        } else {
            #Process a project folder and rename it with prefix "Project_"
            my $newFile = $projectPrefix . "" . $file;
            #Rename the folder.
            File::Copy::move("$unaligned/$file","$unaligned/$newFile");
            #Folders with Sample_Name that differ from Sample_ID will be placed in a
            #additional subfolder and will be have to be processed seperatly.
            my $subSetSampleSheetIdNotEqualToName;
            my $subSetSampleSheetIdEqualToName;
            #Extract the entries that belong to the current project.
            foreach my $laneKeys (keys %{$sampleSheet->{$file}}) {
               foreach my $indexKey (keys %{$sampleSheet->{$file}->{$laneKeys}}) {
                   if($sampleSheet->{$file}->{$laneKeys}->{$indexKey}->{'SampleName'} eq $sampleSheet->{$file}->{$laneKeys}->{$indexKey}->{'SampleID'}) {
                      $subSetSampleSheetIdEqualToName->{$laneKeys} = $sampleSheet->{$file}->{$laneKeys};
                    } else {
                       $subSetSampleSheetIdNotEqualToName->{$laneKeys} = $sampleSheet->{$file}->{$laneKeys};
                    }
                }
            }
            #Variable used to store entries from SampleSheet.
            my %sampleSheetRowsToPrint;

            #Find all folders and files in project folder.
            opendir(DH, "$unaligned/$newFile") or die "Couldn't open dir: $unaligned/$newFile!";
            my @projectFiles = readdir(DH);
            closedir(DH);

            #Loop through all found files/folders.
            foreach my $projectFile (@projectFiles) {
                #Ignore files and folders named with prefix "Sample_", output folder should't contain this prefix
                if($projectFile !~/^\.*$|^Sample_/) {
                    #Move and rename fastq file and save the entry from the SampleSheet.
                    if($projectFile  =~ /fastq$|fastq.gz$/) {
                        $self->processHiSeqXProjectFile($subSetSampleSheetIdEqualToName,
                                                  %sampleSheetRowsToPrint,
                                                  "$unaligned/$newFile",
                                                  $projectFile,
                                                  "$unaligned/$newFile");
                    } else {
                        #Enter subfolder and process the content.
                        opendir(DH, "$unaligned/$newFile/$projectFile") or die "Couldn't open dir: $unaligned/$newFile/$projectFile!";
                        my @subProjectFiles = readdir(DH);
                        closedir(DH);

                        foreach my $subProjectFile (@subProjectFiles) {
                            if($subProjectFile !~/^\.*$/) {
                                #Move and rename fastq file and save the entry from the SampleSheet.
                                if($subProjectFile  =~ /fastq$|fastq.gz$/) {
                                    $self->processHiSeqXProjectFile($subSetSampleSheetIdNotEqualToName,
                                                              \%sampleSheetRowsToPrint,
                                                              "$unaligned/$newFile/$projectFile",
                                                              $subProjectFile,
                                                              "$unaligned/$newFile");
                                }
                            }
                        }
                        #Remove the subfolder.
                        rmdir "$unaligned/$newFile/$projectFile"
                    }
                }
           }

           #Print the extracted SampleSheet entries to the Sample_"Name" folder.
           foreach my $sample (keys %sampleSheetRowsToPrint) {
               my $sampleFile = "$unaligned/$newFile/$samplePrefix" . $sample . "/SampleSheet.csv";
               open SAMPLESHEET, "> $sampleFile" or die "Couldn't open output file: $sampleFile!";
               print SAMPLESHEET $sampleSheetHeader;
               foreach my $lane (sort keys %{$sampleSheetRowsToPrint{$sample}}) {
                   foreach my $number (sort keys %{$sampleSheetRowsToPrint{$sample}->{$lane}}) {
                       print SAMPLESHEET $sampleSheetRowsToPrint{$sample}->{$lane}->{$number};
                   }
               }
               close(SAMPLESHEET);
           }
       }
   }
}

=pod

=head2 processHiSeqXProjectFile()

 Title   : processHiSeqXProjectFile
 Usage   : $sisyphus->processHiSeqXProjectFile()
 Function: process a provided fastq file,
              rename it,
              move it
             and save the SampleSheet entry.
 Example :
 Returns :
 Args    : none

=cut

sub processHiSeqXProjectFile {
    my $self = shift;
    my $subsetSampleSheet = shift;
    my $outputSampleSheet = shift;
    my $inputDir = shift;
    my $projectFile = shift;
    my $outputDir = shift;

    #Extract information from fastq file
    my ($name, $number, $lane, $read, $part) = ($projectFile =~ m/^(.*)_S([0-9]*)_(L[0-9]{3})_(R[123]{1})_([0-9]{3})\.fastq\.gz$/g);
    my $shortLaneId = $lane;
    $shortLaneId =~ s/^L0*//g;
    my $found = 0;

    #Fastq files will be stored in a folder with name "Sample_"+SAMPLENAME
    my $dir = "$outputDir/Sample_$name";

    mkdir $dir unless -e $dir;

    #Find Sample and index combination in SampleSheet, move and rename fastq-file.
    foreach my $indexKey (keys %{$subsetSampleSheet->{$shortLaneId}}) {
        if($subsetSampleSheet->{$shortLaneId}->{$indexKey}->{'SampleName'} eq $name &&
            $subsetSampleSheet->{$shortLaneId}->{$indexKey}->{'SampleNumber'} == $number) {
            my $newFastqFile = $subsetSampleSheet->{$shortLaneId}->{$indexKey}->{'SampleName'} . "_" .
                               $subsetSampleSheet->{$shortLaneId}->{$indexKey}->{'Index'} . "_" .
                               $lane . "_" . $read . "_001.fastq.gz";
            $found = 1;
            $outputSampleSheet->{$name}->{$shortLaneId}->{$number} =
                $subsetSampleSheet->{$shortLaneId}->{$indexKey}->{'Row'} . "\n";
            File::Copy::move("$inputDir/$projectFile","$dir/$newFastqFile");
        }
    }
    die "Couldn't find sample in SampleSheeet $name!\n" if($found == 0);
}

=pod

=head1 FUNCTIONS

=head2 gzip()

 Title   : gzip
 Usage   : $sis->gzip($file)
 Function: Compress the file $file in dir $srcDir with gzip,
           verify and then delete the old file. The checksum
           of the compressed file is saved to RF/MD5/sisyphus.md5
           if the file is located in the runfolder.
 Example :
 Returns : new filename of gzipped file (absolute path)
 Args    : file path (absolute or relative to runfolder)

=cut

sub gzip{
    my $self = shift;
    my $file = shift;
    my $recurse = shift || 0;

    print "gzip: Getting abs path for $file\n" if($self->{DEBUG});
    my $absFile = abs_path($file);
    if(-e $absFile){
	$file = $absFile;
    }else{
	$absFile = abs_path($self->PATH . "/$file");
	if(-e $absFile){
	    $file=$absFile;
	}else{
	    confess "Failed to get abs path for $file\n";
	}
    }
    print "$file\n" if($self->{DEBUG});

    # Get the checksum of original file while it exists
    my $md5Orig = $self->getMd5($file);

    if(-e "$file.gz"){
	print "$file.gz already exists\n" if($self->{DEBUG});
    }else{
	print STDERR "gzipping '$file'\n" if($self->{DEBUG});
	my @stat = stat($file);
	my $pig = system("pigz -n -T -p $self->{THREADS} -c '$file'> '$file.gz'");
	if($pig){ # pigz failed
	    unlink("$file.gz") if(! $self->{DEBUG} && -e "$file.gz" && -e "$file");
	    system("gzip -n -c '$file'> '$file.gz'")==0 or confess "Failed to gzip $file\n";
	}
    }

    print STDERR "verifying $file.gz\n" if($self->{DEBUG});
    open(my $fh, '-|', "zcat '$file.gz'") || die "Failed to read '$file.gz': $!\n";
    print STDERR "Checksumming $file.gz\n" if($self->{DEBUG});
    my $md5New = $self->getMd5($fh); # Checksum of uncompressed file
    close($fh);

    if($md5New eq $md5Orig){
	# Compress & Uncompress successful
	# Now we can delete the original file
#	(my $trashFile = $file) =~ s:/([^/]+)$:/trash.$1:;
#	rename($file,"$trashFile");
	print STDERR "Removing original file '$file'\n" if($self->{DEBUG});
	unlink($file);

	# Get and save the md5 of the compressed file if it is in the runfolder
	if($file =~ m/^$self->{PATH}/){
	    # Avoid cache since an old compressed file might linger there
	    # get with noCache will skip saving, so be explicit about that
	    my $md5 = $self->getMd5("$file.gz", -noCache=>1);
	    $self->saveMd5("$file.gz",$md5);
	}

    }else{
	print STDERR "Failed to verify '$file' expected '$md5Orig'\n";
	if($recurse > 1){
	    die "Failed to verify $file $recurse times. Giving up\n";
	}
	$self->gzip($file,$recurse+1);
    }
    return("$file.gz");
}

=pod

=head2 gzipFolder()

 Title   : gzipFolder
 Usage   : $sis->gzipFolder($file)
 Function: Compress the folder $file in dir $srcDir with gzip,
           verify and then delete the old folder. The checksum
           of the compressed file is saved to RF/MD5/sisyphus.md5.
 Example :
 Returns : new filename of gzipped file (absolute path)
 Args    : file path (absolute or relative to runfolder)

=cut


sub gzipFolder{
    my $self = shift;
    my $file = shift;
    my $md5sumFile = shift;

    print "gzip: Getting abs path for $file\n" if($self->{DEBUG});
    my $dirPath = dirname(abs_path($file));
    print "File abs path for $file: $dirPath\n" if($self->{DEBUG});
    unless(-e "$dirPath/$file"){
	$dirPath = $self->PATH;
	print "Self dir path for $file: $dirPath\n" if($self->{DEBUG});
	unless(-e "$dirPath/$file"){
	    confess "Failed to get abs path for $file\n";
	}
    }
    print "$dirPath/$file\n" if($self->{DEBUG});

    if(-e "$dirPath/$file.tar.gz"){
	print "$dirPath/$file.tar.gz already exists\n" if($self->{DEBUG});
    }else{
	die "$dirPath/$file is not a folder!\n" if(! -d "$dirPath/$file");
	my @stat = stat("$dirPath/$file");
	my $pig = system("tar -cC $dirPath $file | pigz -n -T -p $self->{THREADS} -c > '$dirPath/$file.tar.gz'");
	if($pig){ # pigz failed
	    unlink("$dirPath/$file.tar.gz") if(! $self->{DEBUG} && -e "$dirPath/$file.tar.gz" && -e "$dirPath/$file");
	    system("tar -zcf '$dirPath/$file.tar.gz' -C '$dirPath' '$file'")==0 or confess "Failed to gzip $dirPath/$file\n";
	}
    }
    
    print "verifying $dirPath/$file.tar.gz\n" if($self->{DEBUG});
    
    my $md5Hash = $self->getMd5ForArchiveContent("$dirPath/$file");
    open(MD5SUM, $md5sumFile) or die "Couldn't open md5 file for $md5sumFile!\n";

    print "Validating MD5 for each file in the compressed archive '$dirPath/$file'\n" if($self->{DEBUG});
    while(<MD5SUM>)
    {
	if(!/^\n/)
	{
		chomp;
		my ($md5, $path) = split(/\t|\s+/,$_,2);

		if(!defined($md5Hash->{$path}))
		{
			print "Removing $file.tar.gz since the content doesn't match the stored md5 sums!\n";
			unlink $file;
			die "MD5 path not found in org file ($path)!\n";
		}
		elsif(!($md5Hash->{$path} eq $md5))
		{
			print "Removing $file.tar.gz since the content doesn't match the stored md5 sums!\n";
			die "MD5 doesn't match org file ($path), $md5!=$md5Hash->{$path}!\n";
		}
		delete $md5Hash->{$path};
	}
    }
    close(MD5SUM);
    if((scalar keys %{$md5Hash}) > 0) {
        if($self->{DEBUG}) {
		print "Removing $file.tar.gz since the content doesn't match the stored md5 sums!\n";
		unlink $file;
		print "Extra files in provided md5 list:\n";
		foreach (keys  %{$md5Hash}) {
			print "$_\t$md5Hash->{$_}\n";
		}
	}
    	die "Provided md5 checklist file contains more files than the compressed archive!\n" if((scalar keys %{$md5Hash}) > 0);
    }
   
    # Compress & Uncompress successful
    # Now we can delete the original folder
    print STDERR "Removing original file '$dirPath/$file'\n" if($self->{DEBUG});
    rmtree  "$dirPath/$file" or die "Couldn't remove folder $dirPath/$file!\n";

    # Get and save the md5 of the compressed file if it is in the runfolder
    # Avoid cache since an old compressed file might linger there
    # get with noCache will skip saving, so be explicit about that
    my $md5 = $self->getMd5("$file.tar.gz", -noCache=>1);
    $self->saveMd5("$file.tar.gz",$md5);

    return("$file.tar.gz");
}


=pod

=head2 getMd5()

 Title   : getMd5
 Usage   : $sis->getMd5($file|$fh, -noCache=>0, -skipMissing=>0)
 Function: Calculates the md5 checksum for a file or open filehandle
 Example :
 Returns : md5 checksum
 Args    : file path (absolute or relative to the runfolder) or filehandle,
           flag for use of cache: Do not use cache if flag is set.
           flag for handling of missing files: Do not die if file is missing.

=cut


sub getMd5{
    my $self = shift;
    my $file = shift;
    my %args = @_;
    my $noCache = 0;
    if($args{'-noCache'}){
	$noCache = 1;
    }
    my $skipMissing = 0;
    if($args{'-skipMissing'}){
	$skipMissing = 1;
    }
    my $fh;

    unless(defined $file){
	confess "File not defined\n";
    }

    if(ref($file) eq 'GLOB'){
        $fh = $file;
    }else{
	print "getMd5: Getting abs path for $file\n" if($self->{DEBUG});
	my $absFile = abs_path($file) || "";
	if(-e $absFile || -e "$absFile.gz"){
	    $file = $absFile;
	}else{
	    $absFile = abs_path($self->PATH . "/$file") || "";
	    if(-e $absFile || -e "$absFile.gz"){
		$file=$absFile;
	    }elsif(-e $self->PATH . "/$file" || -e $self->PATH . "/$file.gz" ){
		$file =~ s:^$self->RUNFOLDER::;
		$file = $self->PATH . "/$file";
	    }elsif(-e dirname($self->PATH) . "/$file" || -e dirname($self->PATH) . "/$file.gz"){
		# Runfolder name was already included in the file path, but not absolute
		$file = dirname($self->PATH) . "/$file";
	    }else{
		warn "Failed to get abs path for $file\n" if($self->{DEBUG});
		unless($file =~ m:^/:){ # Add runfolder unless it is already absolute
		    $file = $self->PATH . "/$file";
		}
	    }
	}
	$file =~ s:/+:/:; # Remove duplicate slashes
	print "$file\n" if($self->{DEBUG});

	# Check if we already have the md5 in cache
	unless($noCache){
	    unless(defined $self->{CHECKSUMS}){
		$self->readMd5sums();
	    }
	    if(defined $self->{CHECKSUMS}->{$file}){
		return $self->{CHECKSUMS}->{$file};
	    }
	}
	# Otherwise open the file, if it exists
	if(-e $file){
	    open($fh, '<', "$file") || die "Failed to read '$file': $!\n";
	}elsif(-e "$file.gz"){
	    open($fh, '-|', "zcat $file.gz") || die "Failed to read '$file.gz': $!\n";
	}else{
	    if($skipMissing){
		warn "Failed to get checksum for '$file'\n" if($self->DEBUG);
		return undef;
	    }else{
		confess "Failed to get checksum for '$file'\n";
	    }
	}
    }

    binmode($fh);

    my $sum = Digest::MD5->new->addfile($fh)->hexdigest;

    unless(ref($file) eq 'GLOB'){
	close($fh);
	# Write the checksum to file if the file is in the runfolder
	unless($noCache){
	    if($file =~ m/^$self->{PATH}/){
		$self->saveMd5($file,$sum);
	    }
	    $self->{CHECKSUMS}->{$file} = $sum;
	}
    }
    return ($sum);
}

=pod

=head2 getMd5ForArchiveContent()

 Title   : getMd5ForArchiveContent
 Usage   : $sis->getMd5ForArchiveContent($file|$fh, -noCache=>0, -skipMissing=>0)
 Function: Calculates the md5 checksum for all files found inside archive (tar.gz)
 Example :
 Returns : hash ref with path as key and md5 as value
 Args    : file path (absolute or relative to the runfolder) or filehandle,

=cut


sub getMd5ForArchiveContent{
    my $self = shift;
    my $file = shift;
    my %args = @_;

    my $fh;

    unless(defined $file){
	confess "File not defined\n";
    }
  
    my $tempfolder = "tmp." . time;
    mkdir $tempfolder;	
	
    my $tar = system("tar -zxf  $file.tar.gz -C $tempfolder");
    if($tar){ # pigz failed
       rmtree $tempfolder or die "Couldn't remove folder: $tempfolder!\n";
       die "Couldn't extract archive content $file into $tempfolder!\n";
    }
    
    my $md5sumList;
	
    open($fh, '-|', "find $tempfolder -type f -print0 | xargs -0 md5sum") || die "Failed archive read '$tempfolder': $!\n";	    
    while(<$fh>)
    {
	chomp;
	my ($md5,$path) = split(/\t|\s+/,$_,2);
	$path =~ s/$tempfolder\///g;
	$md5sumList->{$path} = $md5;
    }
    close($fh);
    rmtree $tempfolder or die "Couldn't remove folder: $tempfolder!\n";
    print "md5 calculated for all files in archive $file!\n" if($self->{DEBUG});
    return $md5sumList;
}

=pod

=head2 md5Dir()

 Title   : md5Dir
 Usage   : $sis->md5Dir($dir, -noCache=>1, -save=>1)
 Function: Recursively calculates the md5 checksums for all files in a directory 
 Example :
 Returns : hash with md5 checksums, filename relative to $dir as key, checksum as value
 Args    : directory path (absolute or relative to the runfolder),
           flag for use of cache: Do not use cache if flag is set.
           flag for saving to cache: Save the calculated checksums to cache if flag is set.

=cut


sub md5Dir{
  my $self = shift;
  my $dir = shift;
  my %args = @_;
  my $noCache = 0;
  if($args{'-noCache'}){
    $noCache = 1;
  }
  my $save = 0;
  if($args{'-save'}){
    $save = 1;
  }

  unless(defined $dir){
    confess "File not defined\n";
  }
  my $absDir;
  if($dir =~ m(^/) ){
    $absDir = $dir;
  }elsif(-e $self->PATH . "/$dir"){
    $absDir = $self->PATH . "/$dir";
  }else{
    die "'$dir' not absolute and not relative to the runfolder '" . $self->PATH . "'";
  }

  my %checksums;
  opendir(my $dfh, $absDir) or die "Failed to open '$absDir': $!";
  foreach my $file (grep /^[^\.]/, readdir($dfh)){
    if(-d "$absDir/$file"){
      my $chks = $self->md5Dir("$absDir/$file", -noCache=>$noCache, -save=>$save);
      @checksums{keys %{$chks}} = values %{$chks};
    }else{
      my $md5 = $self->getMd5("$absDir/$file", -noCache=>$noCache);
      $self->saveMd5("$absDir/$file", $md5) if($save);
      $checksums{"$absDir/$file"} = $md5;
    }
  }
  return \%checksums;
}

=pod

=head2 saveMd5()

 Title   : saveMd5
 Usage   : $sis->saveMd5($file,$sum)
 Function: Writes the checksum of $file to $runfolder/MD5/sisyphus.md5
 Example :
 Returns : nothing
 Args    : Absolute file path, md5 checksum

=cut


sub saveMd5{
    my $self = shift;
    my $file = shift;
    my $sum = shift;
    $file = abs_path($file);
    my $rfPath = $self->{PATH};

    my $absFile = $file;
    $file =~ s:^$rfPath/::;
    my $runfolder = basename($rfPath);

    $self->mkpath("$rfPath/MD5",2770);
    print STDERR "Writing MD5 for '$file'\n" if($self->{DEBUG});
    open(my $md5fh, ">>", "$rfPath/MD5/sisyphus.md5") or die "Failed to open $rfPath/MD5/sisyphus.md5:$!\n";
    flock($md5fh, LOCK_EX) || confess "Failed to lock $rfPath/MD5/sisyphus.md5:$!\n";
    print $md5fh "$sum  $runfolder/$file\n";
    flock($md5fh, LOCK_UN);
    close($md5fh);

    # Update the cache, if used, with the new(?) checksum for this file
    if(exists $self->{CHECKSUMS}){
	$self->{CHECKSUMS}->{$absFile} = $sum;
    }
}

=pod

=head2 readMd5sums()

 Title   : readMd5sums
 Usage   : $sis->readMd5sums()
 Function: reads files with md5 checksums in $runfolder/MD5/ and stores them in a hash with filename as key.
 Example :
 Returns : nothing
 Args    : none

=cut

sub readMd5sums{
    my $self = shift;
    my $rfPath = $self->{PATH};
    my $rfParent = dirname($rfPath);
    my %md5data;
    if(-e "$rfPath/MD5"){
        opendir(MD5DIR, "$rfPath/MD5/") or die "Failed to open MD5-directory '$rfPath/MD5': $!\n";
        foreach my $file (readdir(MD5DIR)){
            if($file=~m/\.md5(\.gz)?$/ && $file !~ /^checksums\.miseqrunfolder\.md5(\.gz)?$/){
		my $inFh;
		if($file =~ m/\.gz/){
		    open($inFh, '-|', "zcat $rfPath/MD5/$file") or die "Failed to open MD5-file '$rfPath/MD5/$file': $!\n";
		}else{
		    open($inFh, '<', "$rfPath/MD5/$file") or die "Failed to open MD5-file '$rfPath/MD5/$file': $!\n";
		}

                while(<$inFh>){
                    chomp;
                    my($key,$path) = split(/\s+/, $_, 2);
		    # Change the path from relative (including runfolder) to absolute
                    $md5data{"$rfParent/$path"} = $key;
                }
                close($inFh);
            }
        }
    }
    print STDERR keys(%md5data) + 0, " checksums found\n" if($self->{DEBUG});
    $self->{CHECKSUMS} = \%md5data;
}

=pod

=head2 tileCount()

 Title   : tileCount
 Usage   : $sis->tileCount()
 Function: Returns the expected number of tiles per lane
 Example :
 Returns : number of tiles
 Args    : none

=cut

sub tileCount{
    my $self = shift;
    if( my $runInfo = $self->getRunInfo() ){
	return($runInfo->{tiles});
    }
    return undef;
}

=pod

=head2 version()

 Title   : version
 Usage   : $sis->version()
 Function: Returns the sisyphus version as determined from Git
 Example :
 Returns : Version of sisyphus
 Args    : none

=cut

sub version{
    my $self = shift;

    if(defined $self->{VERSION}){
	return $self->{VERSION};
    }
    my $class = ref($self);
    my $version = $class::VERSION;

    if(-e "$FindBin::Bin/.git"){
	$version = `git --git-dir $FindBin::Bin/.git describe --tags`;
    }elsif(-e "$FindBin::Bin/SISYPHUS_VERSION"){
	$version = `cat "$FindBin::Bin/SISYPHUS_VERSION"`;
    }
    chomp($version);
    $self->{VERSION} = $version;
    return $self->{VERSION};
}

=pod

=head2 getCSversion()

 Title   : getCSversion
 Usage   : $sis->getCSversion()
 Function: Reads the Control Software version from the runfolder
 Example :
 Returns : Version of HCS/MCS
 Args    : none

=cut

sub getCSversion{
    my $self = shift;
    my $rfPath = $self->{PATH};
    if(defined $self->{HCSVERSION}){
	return $self->{HCSVERSION};
    }

    my $runParams = $self->runParameters();
    return undef unless($runParams);

    $self->{CSVERSION} = $runParams->{Setup}->{ApplicationVersion};
    return $self->{CSVERSION};
}

=pod

=head2 getRTAversion()

 Title   : getRTAversion
 Usage   : $sis->getRTAversion()
 Function: Reads the RTA version from the runfolder
 Example :
 Returns : Version of RTA
 Args    : none

=cut

sub getRTAversion{
    my $self = shift;
    my $rfPath = $self->{PATH};
    if(defined $self->{RTAVERSION}){
	return $self->{RTAVERSION};
    }

    my $runParams = $self->runParameters();
    return undef unless($runParams);

    if(exists $runParams->{RTAVersion}){
	$self->{RTAVERSION} = $runParams->{RTAVersion};
    }elsif(exists $runParams->{Setup}->{RTAVersion}){
	$self->{RTAVERSION} = $runParams->{Setup}->{RTAVersion};
    }else{
	$self->{RTAVERSION} = '';
    }
    return $self->{RTAVERSION};
}

=pod

=head2 getBcl2FastqVersion()

 Title   : getBcl2FastqVersion
 Usage   : $sis->getBcl2FastqVersion()
 Function: Reads the bcl2fast version from the runfolder
 Example :
 Returns : Version of bcl2fastq
 Args    : none

=cut

sub getBcl2FastqVersion{
    my $self = shift;
    my $rfPath = $self->{PATH};
    if(defined $self->{BCL2FASTQVERSION}){
	return $self->{BCL2FASTQVERSION};
    }

    my $file = "$rfPath/bcl2fastq.version";
    if(-e $file){
	open FILE, $file or die "Failed to open $file!\n";
	$self->{BCL2FASTQVERSION} = <FILE>;
	close(FILE);
    }elsif(-e "$file.gz"){
	open(FILE, '<:gzip', "$file.gz") || confess "Failed to open $file.gz\n";
	$self->{BCL2FASTQVERSION} = <FILE>;
	close(FILE);
    }
    
    return $self->{BCL2FASTQVERSION};
}


=pod

=head2 getCasavaVersion()

 Title   : getCasavaVersion
 Usage   : $sis->getCasavaVersion()
 Function: Reads the CASAVA version from the runfolder
 Example :
 Returns : Version of CASAVA
 Args    : none

=cut

sub getCasavaVersion{
    my $self = shift;
    my $rfPath = $self->{PATH};
    if(defined $self->{CASAVAVERSION}){
	return $self->{CASAVAVERSION};
    }

    my $xml = "$rfPath/Unaligned/DemultiplexConfig.xml";
    my $dmConfig;
    if(-e $xml){
	$dmConfig = XMLin($xml) || confess "Failed to read $xml\n";
    }elsif(-e "$xml.gz"){
#	my $fh = IO::File->new();
#	$fh->open("$xml.gz", ':gzip') || confess "Failed to open $xml.gz\n";
#	$dmConfig = XMLin($fh);
	open(my $xfh, '<:gzip', "$xml.gz") || confess "Failed to open $xml.gz\n";
	local $/='';
	my $str = <$xfh>;
	local $/="\n";
	$dmConfig = XMLin($str);
    }
    if(defined $dmConfig){
	$self->{CASAVAVERSION} = $dmConfig->{Software}->{Version};
	return $self->{CASAVAVERSION};
    }
    return undef;
}


=pod

=head2 getFlowCellVersion()

 Title   : getFlowCellVersion()
 Usage   : $sis->getFlowCellVersion()
 Function: Reads the flow cell version from the runfolder
 Example :
 Returns : Flow cell version string
 Args    : none

=cut

sub getFlowCellVersion{
    my $self = shift;
    my $rfPath = $self->{PATH};
    if(defined $self->{FCVERSION}){
	return $self->{FCVERSION};
    }

    my $runParams = $self->runParameters();
    return undef unless($runParams);

    $self->{FCVERSION} = $runParams->{Setup}->{Flowcell};
    return $self->{FCVERSION};
}


=pod

=head2 getSBSversion()

 Title   : getSBSversion()
 Usage   : $sis->getSBSversion()
 Function: Reads the SBS version from the runfolder
 Example :
 Returns : SBS version string
 Args    : none

=cut

sub getSBSversion{
    my $self = shift;
    my $rfPath = $self->{PATH};
    if(defined $self->{SBSVERSION}){
	return $self->{SBSVERSION};
    }

    my $runParams = $self->runParameters();
    return undef unless($runParams);

    $self->{SBSVERSION} = $runParams->{Setup}->{Sbs};
    return $self->{SBSVERSION};
}

=pod

=head2 getClusterKitVersion()

 Title   : getClusterKitVersion()
 Usage   : $sis->getClusterKitVersion()
 Function: Reads the cluster kit version from the runfolder
 Example :
 Returns : Cluster kit version string
 Args    : none

=cut

sub getClusterKitVersion{
    my $self = shift;
    my $rfPath = $self->{PATH};
    if(defined $self->{CKVERSION}){
	return $self->{CKVERSION};
    }

    my $runParams = $self->runParameters();
    return undef unless($runParams);

    if(defined $runParams->{Setup}->{Pe}){
	$self->{CKVERSION} = $runParams->{Setup}->{Pe};
    }else{
	$self->{CKVERSION} = "Unknown";
    }
    return $self->{CKVERSION};
}

=pod

=head2 getRunInfo()

 Title   : getRunInfo
 Usage   : $sis->getRunInfo($rfPath)
 Function: Reads data from $rfPath/RunInfo.xml
 Example :
 Returns : hashref with info
 Args    : none

=cut

sub getRunInfo{
    my $self = shift;
    my $rfPath = $self->{PATH};

    if(defined $self->{RUNINFO}){
	return $self->{RUNINFO};
    }

    my $cycles = 0;
    my $surfaces = 0;
    my $swaths = 0;
    my $tiles = 0;
    my $indexed = 0;
    my @reads;

    if(! -e "$rfPath/RunInfo.xml") {
      if ( -e "$rfPath/RunInfo.xml.gz"){
        `gunzip -N "$rfPath/RunInfo.xml.gz"`;
      }
      else {
        die "Could not find $rfPath/RunInfo.xml[.gz] (required)\n";
      }
    }
    
    my $runInfo = XMLin("$rfPath/RunInfo.xml", ForceArray=>['Read']) || confess "Failed to read RunInfo\n";
    return undef unless($runInfo);

    if(ref $runInfo->{Run}->{Reads}->{Read} eq 'ARRAY'){
	my $i=0;
        foreach my $read (@{$runInfo->{Run}->{Reads}->{Read}}){
	    $i++;
	    if(exists $read->{NumCycles}){ # HiSeq
		push @reads, { 'id'=>$i,'first'=>$cycles, 'last'=>$cycles + $read->{NumCycles}-1, 'index'=>$read->{IsIndexedRead} }; #Change to 0 based index
		$cycles += $read->{NumCycles};
		$indexed = 1 if($read->{IsIndexedRead} eq 'Y');
	    }else{
		confess "Failed to get NumCycles for read from RunInfo.xml\n";
	    }
        }
    }

    if(exists $runInfo->{Run}->{FlowcellLayout}->{SurfaceCount}){
        $surfaces = $runInfo->{Run}->{FlowcellLayout}->{SurfaceCount};
    }elsif($runInfo->{Run}->{Instrument} eq 'HWI-EAS178'){
	$surfaces = 1; # GA
    }else{
        die "SurfaceCount missing from $rfPath/RunInfo.xml\n";
    }

    if(exists $runInfo->{Run}->{FlowcellLayout}->{SwathCount}){
        $swaths = $runInfo->{Run}->{FlowcellLayout}->{SwathCount};
    }elsif($runInfo->{Run}->{Instrument} eq 'HWI-EAS178'){
	$swaths = 1; # GA
    }else{
        die "SwathCount missing from $rfPath/RunInfo.xml\n";
    }

    if(exists $runInfo->{Run}->{FlowcellLayout}->{TileCount}){
        $tiles = $runInfo->{Run}->{FlowcellLayout}->{TileCount};
    }elsif($runInfo->{Run}->{Instrument} eq 'HWI-EAS178'){
	$tiles = 120; # GA
    }else{
        die "TileCount missing from $rfPath/RunInfo.xml\n";
    }

    my $totalTiles = $surfaces * $swaths * $tiles;

    # If no info found, set value unreachable
    unless($cycles>0){
        $cycles = 10000;
    }
    unless($totalTiles>0){
        $totalTiles = 10000;
    }

    if($self->{DEBUG}){
        print STDERR "Expecting $cycles cycles\n";
        print STDERR "Expecting $surfaces surfaces/lane\n";
        print STDERR "Expecting $swaths swaths/lane\n";
        print STDERR "Expecting $tiles tiles/swath\n";
        print STDERR "Expecting $totalTiles tiles/lane\n";
        print STDERR "Indexed: $indexed\n";
	print STDERR "Reads: \n";
	  for(my $i=0; $i<@reads; $i++){
	      my $read = $reads[$i];
	      print STDERR "\t Read " . ($i+1). "\n";
	      foreach my $k (sort keys %{$read}){
		  print STDERR "\t\t $k: $read->{$k}\n"
	      }
	  }
    }

    my $retval = {cycles=>$cycles,tiles=>$totalTiles, indexed=>$indexed, reads=>\@reads, xml=>$runInfo};
    # Only cache if all info is present
    unless($totalTiles==10000 || $cycles==10000){
	$self->{RUNINFO}=$retval;
    }
    return($retval);
}

=pod

=head2 copy()

 Title   : copy
 Usage   : my($target, $md5) = $sis->copy($file,$dir,{VERIFY=>1,RELATIVE=>1})
 Function: Copies $file in runfolder to $dir while preserving folder structure
 Example : $sis->copy("Data/Intensities/config.xml", "outdir")
 Returns : array with the absolute path and verified md5 checksum of the written file
 Args    : the source file absolute or relative to source runfolder,
           root of target directory,
           hashref with options:
           VERIFY: bool, if true verify the copy with md5 checksums [1]
           RELATIVE: bool, if true preserve path relative to source dir [0]
           LINK: bool, try creating a hard link instead of copy, fall back to copy if link fails [0]

=cut

sub copy{
    my $self = shift;
    my $file = shift;
    my $tDir = shift;
    my $verify = 1;
    my $keepPath = 0;
    my $link = 0;

    if(@_){
	my $options = shift;
	$verify = $options->{VERIFY} if(defined $options->{VERIFY});
	$keepPath = $options->{RELATIVE} if(defined $options->{RELATIVE});
	$link = $options->{LINK} if(defined $options->{LINK});
    }

    $self->mkpath($tDir,2770) unless(-e $tDir);

    $tDir = abs_path($tDir);
    my $src = $file;
    my $rfPath = $self->PATH;
    if($file =~ m/^$rfPath/){
	$file =~ s/^$rfPath//;
	$file =~ s:^/+::;
    }elsif($file !~ m:^/:){ # Assume relative path to be relative to runfolder
	$src = $rfPath . "/$file";
    }

    $file =~ s:/+:/:;

    unless(-e $src){
	confess "Sourcefile does not exist: '$src'\n";
    }

    my $target = "$tDir/" . basename($src);
    if($keepPath){
	my $runfolder = $self->RUNFOLDER;
	$target = $src;
	if($target =~ m/$rfPath/){
	    $target =~ s/^.*$rfPath/$tDir/;
	}elsif($target =~ m/$runfolder\//){
	    $target =~ s/^.*$runfolder/$tDir/;
	}elsif( $target =~ s:/.*/(Config|Data|Diag|InterOp|Logs|PeriodicSaveRates|Recipe|Sisyphus)/:$tDir/$1/: ){
	    # Try to use the dirnames at the first level of the runfolder to remove the leading dirs
	}else{
	    $target = "$tDir/" . basename($src);
	}
    }

    $self->clonePath(dirname($src),dirname($target));

    my $copy = 1;
    my $md5sum;
    if($link){
	$copy = system('ln',$src,$target);
	# If link succeeds, copy will be set to zero
	if($copy==0){ # If link was successful, src and target are the same file
	    $md5sum=$self->getMd5($src);
	}
    }
    if($copy){ # If link failed, copy is still true
	File::Copy::cp($src,$target) || confess "Failed to copy $src to $target: $!\n";
	# Preserve timestamps
	my @sStat = stat($src);
	utime @sStat[8,9], $target;
	if($verify){
	    $md5sum = $self->getMd5($target);
	    unless($self->getMd5($src) eq $md5sum){
		my $msg = "Failed to verify copy" . "\n  $src " . $self->getMd5($src) . "\n  $target " . $md5sum . "\n";
		confess $msg;
	    }
	}
    }
    return($target,$md5sum);
}

=pod

=head2 clonePath()

 Title   : clonePath
 Usage   : $sis->clonePath($dir1,$dir2)
 Function: Recursively creates the directory path dir2, using the permissions of dir1.
           The permissions will be copied from dir1 to dir2 for the sub path
           that is identical between the two paths.
 Example :
 Returns : true on success
 Args    : none

=cut

sub clonePath{
    my $self = shift;
    my $src = shift;
    my $target = shift;
    my $srcParent = dirname($src);
    my $targetParent = dirname($target);

    unless(-e $target){
	# Recurse until the paths differ
	unless(-e $targetParent){
	    if(basename($srcParent) eq basename($targetParent)){
		$self->clonePath($srcParent,$targetParent);
	    }
	}

	my @dStat = stat($src);
	my $dPerm = sprintf('%05o', S_IMODE($dStat[2]));
	system("mkdir", '-p', '-m', $dPerm, $target)==0 || confess "Failed to create dir $target: $!\n";
    }
    return 1;
}

=pod

=head2 readSampleSheet()

 Title   : readSampleSheet
 Usage   : $sis->readSampleSheet()
 Function: Reads data from $rfPath/Samples.csv
 Example :
 Returns : hashref with info
 Args    : none

=cut

sub readSampleSheet{
    my $self = shift;
    my $rfPath = $self->PATH;
    # Boldly assuming CASAVA 1.8, skipping legacy cruft from old demultiplexing
    my $sheetPath = "$rfPath/SampleSheet.csv";
    my %sampleSheet;

    # Get the flowcell id
    my $fcId = $self->fcId();

    #Expected file format is
    #FCID,Lane,SampleID,SampleRef,Index,Description,Control,Recipe,Operator,SampleProject
    my $sheet;
    if(-e "$sheetPath.gz" && ! -e $sheetPath){
	open($sheet, '<:gzip', "$sheetPath.gz") or die "Failed to open $sheetPath.gz: $!\n";
    }else{
	open($sheet, '<', $sheetPath) or die "Failed to open $sheetPath: $!\n";
    }
    if($self->machineType eq 'hiseqx') {
        while(<$sheet>){
            if(m/^\[Data\]/) {
                my $row = <$sheet>;
                chomp($row);
                $row=~ s/[\012\015]*$//;
                my @columns = split(/,/,$row);
                my $length = @columns;
                my $columnMap;
                for( my $i = 0; $i < $length; $i++) {
                    $columnMap->{$columns[$i]} = $i;
                }
                my $sampleCounter;
                while(<$sheet>){
                    if(/^#/){
                        next;
                    }
                    my $dataRow = $_;
                    chomp($dataRow);
                    $dataRow=~ s/[\012\015]*$//;
                    my @r = split /,/, $dataRow;
                    $r[$columnMap->{'index'}] = 'unknown' if($r[$columnMap->{'index'}] !~ m/^[ACGT-]+$/); # Use 'unknown' for unspecified index tags
                    unless($r[6] =~ m/^y/i){ # Skip the controls
                        
			if(defined($sampleCounter->{$r[$columnMap->{'Lane'}]})){
                                $sampleCounter->{$r[$columnMap->{'Lane'}]}++;
                        }
                        else{
                                 $sampleCounter->{$r[$columnMap->{'Lane'}]} = 1;
                        }

			#Save information in hash
                        $sampleSheet{$r[$columnMap->{'Sample_Project'}]}->{$r[$columnMap->{'Lane'}]}->{$r[$columnMap->{'index'}]} =
                            {'SampleID'=>$r[$columnMap->{'Sample_ID'}],
                             'SampleName'=>$r[$columnMap->{'Sample_Name'}],
                             'Index'=>$r[$columnMap->{'index'}],
                             'Description'=>$r[$columnMap->{'Description'}],
                             'SampleWell'=>$r[$columnMap->{'Sample_Well'}],
                             'SampleNumber'=>$sampleCounter->{$r[$columnMap->{'Lane'}]},
                             'SamplePlate'=>$r[$columnMap->{'Sample_Plate'}],
                             'Lane'=>$r[$columnMap->{'Lane'}],
                             'SampleProject'=>$r[$columnMap->{'Sample_Project'}],
                             'Row'=>$dataRow};
                        # Extract some extras from the description
                        # The format used is KEY1:value1;KEY2:value2...
                        while($r[$columnMap->{'Description'}] =~ m/([^:]*):([^;]*)[;\s]*/g){
                           $sampleSheet{$r[$columnMap->{'Sample_Project'}]}->{$r[$columnMap->{'Lane'}]}->{$r[$columnMap->{'index'}]}->{$1} = $2;
                       }
                   }
               }
           }
       }
    } else {
        while(<$sheet>){
           if(m/^$fcId,/i){
               next if(m/^#/); # Skip comments
               my $row = $_;
               chomp($row);
               $row=~ s/[\012\015]*$//; # Strip CR & LF
               my @r = split /,/, $row;
               $r[4] = 'Undetermined' unless($r[4] =~ m/\S/); # Use 'Undetermined' for unspecified index tags
               unless($r[6] =~ m/^y/i){ # Skip the controls
                    # Use project + lane + index tag   as keys
                    $sampleSheet{$r[9]}->{$r[1]}->{$r[4]} = {'SampleID'=>$r[2],'SampleRef'=>$r[3],'Index'=>$r[4],
                                                             'Description'=>$r[5],'Control'=>$r[6], 'Lane'=>$r[1],
                                                             'SampleProject'=>$r[9], 'Row'=>$row};
                    # Extract some extras from the description
                    # The format used is KEY1:value1;KEY2:value2...
                    while($r[5] =~ m/([^:]*):([^;]*)[;\s]*/g){
                        $sampleSheet{$r[9]}->{$r[1]}->{$r[4]}->{$1} = $2;
                   }
                }
            }
        }
    }
    return(\%sampleSheet);
}

=pod

=head2 getSampleSheetHeader()

 Title   : getSampleSheetHeader
 Usage   : $sis->getSampleSheetHeader()
 Function: Reads header data from $rfPath/Samples.csv
 Example :
 Returns : hashref with info
 Args    : none

=cut

sub getSampleSheetHeader{
    my $self = shift;
    my $rfPath = $self->PATH;
    # Boldly assuming CASAVA 1.8, skipping legacy cruft from old demultiplexing
    my $sheetPath = "$rfPath/SampleSheet.csv";
    my $sampleSheetHeader = undef;

    # Get the flowcell id
    my $fcId = $self->fcId();

    #Expected file format is
    #FCID,Lane,SampleID,SampleRef,Index,Description,Control,Recipe,Operator,SampleProject
    my $sheet;
    if(-e "$sheetPath.gz" && ! -e $sheetPath){
       open($sheet, '<:gzip', "$sheetPath.gz") or die "Failed to open $sheetPath.gz: $!\n";
    }else{
       open($sheet, '<', $sheetPath) or die "Failed to open $sheetPath: $!\n";
    }
    if($self->machineType eq 'hiseqx') {
        LOOP: while(<$sheet>){
            if(m/^\[Data\]/) {
                $sampleSheetHeader .= $_;
                last;
            }else {
                if(!defined($sampleSheetHeader)){
                    $sampleSheetHeader = $_;
                } else {
                    $sampleSheetHeader .= $_;
                }
            }
        }
    } else {
         while(<$sheet>){
            if(m/^FCID,/i){
                $sampleSheetHeader = $_;
                last;
            }
        }
    }
    return($sampleSheetHeader);
}

=pod

=head2 getIndexUsingSampleNumber()

 Title   : tmpdir
 Usage   : $sis->getIndexUsingSampleNumber($lane,$project,$sample,$sampleNumber,$sampleSheet)
 Function: Returns index for the sample with the provided information.
 Example :
 Returns : index (String)
 Args    : lane, sample and sampleNumber

=cut

sub getIndexUsingSampleNumber{
    my $self = shift;
    my $lane = shift;
    my $project = shift;
    my $sample = shift;
    my $sampleNumber = shift;
    my $sampleSheet = shift;

    foreach my $index (keys %{$sampleSheet->{$project}->{$lane}}) {
        if($sampleSheet->{$project}->{$lane}->{$index}->{'SampleNumber'} eq $sampleNumber &&
            $sampleSheet->{$project}->{$lane}->{$index}->{'SampleName'} eq $sample) {
            return $index
        } 
    }
    die "Couldn't find index for the provided sample information!\n";
}

=pod

=head2 tmpdir()

 Title   : tmpdir
 Usage   : $sis->tmpdir($size)
 Function: Returns the absolute path of a temporary directory with $size free space
 Example :
 Returns : a path
 Args    : required space in bytes

=cut

sub tmpdir{
    my $self = shift;
    my $size = shift;

    if( defined($ENV{TMPDIR}) && -e $ENV{TMPDIR} ){
	my $df = $self->df($ENV{TMPDIR});
	if($df > $size){
	    $self->mkpath("$ENV{TMPDIR}/sisyphus/$$", 2770);
	    return("$ENV{TMPDIR}/sisyphus/$$");
	}
    }
    foreach my $scr ('/proj/a2009002/nobackup/private/scratch', '/data/local/scratch', '/data/scratch', '/scratch', '/tmp'){
	my $scratch = $scr;
	if(-e $scratch){
	    $scratch = abs_path($scratch);
	}
	if(-w "$scratch"){
	    my $df = $self->df("$scratch");
	    if($df > $size){
		$self->mkpath("$scratch/sisyphus/$$",2770);
		return("$scratch/sisyphus/$$");
	    }
	}
    }
    confess "Failed to find a temporary directory with $size bytes free\n";
}

=pod

=head2 df()

 Title   : df
 Usage   : $sis->df($path)
 Function: Returns the free space in $path
 Example :
 Returns : number of bytes free space
 Args    : path to check

=cut

sub df{
    my $self = shift;
    my $path = shift;
    if(-e $path){
	my @df = split /\n/, `df -k -P "$path"`;
	my @r = split /\s+/, $df[1];
	return $r[3]*1024;  # bytes
    }
    return 0;
}


=pod

=head2 complete()

 Title   : complete
 Usage   : $sis->complete()
 Function: Checks if the runfolder is completed (the run is finished)
 Example :
 Returns : true if completed
 Args    : none

=cut

sub complete{
    my $self = shift;
    my $rfPath = $self->PATH;
    my $runInfo = $self->getRunInfo();
    my $runParams = $self->runParameters();
    my ($expectedCycles,$expectedTiles) = ($runInfo->{cycles}, $runInfo->{tiles});
    my $numLanes = $self->laneCount();
    foreach my $lane (1..$numLanes){
        my $ldir = "$rfPath/Data/Intensities/BaseCalls/L00${lane}";
        if( opendir(LANE, $ldir) ){
            my @cycles = grep /^C\d+\.1/, readdir(LANE);
	    if(@cycles < $expectedCycles){
		print STDERR "Too few cycles for lane $lane. Found " , @cycles + 0, ", expected $expectedCycles\n" if($self->{DEBUG});
		return 0;
	    }
            foreach my $c (@cycles){
                if( opendir(CYCLE, "$ldir/$c") ){
                    my @tiles = grep /s.*\.(bcl|bcl\.gz)/, readdir(CYCLE);
                    my $nTiles = @tiles + 0;

		    if($nTiles < $expectedTiles){
			print STDERR "Too few tiles for lane $lane, cycle $c. Found $nTiles, expected $expectedTiles.\n" if($self->{DEBUG});
			return 0;
		    }
                    close(CYCLE);
                }else{
                    warn "Failed to open '$ldir/$c'\n";
                    return 0;
                }
            }
            close(LANE);
        }else{
            warn "Failed to open '$ldir'\n";
            return 0;
        }
    }
    if(-e "$rfPath/RTAComplete.txt"){
	print STDERR "Runfolder complete\n" if($self->{DEBUG});
	return 1;
    }
    print STDERR "Waiting for RTAComplete.txt\n" if($self->{DEBUG});
    return 0;
}

=pod

=head2 readConfig()

 Title   : readConfig
 Usage   : $sis->readConfig()
 Function: Reads and returns the contents of sisyphus.yml, blocks until the file is readable
 Example :
 Returns : Hash ref with config information
 Args    : none

=cut

sub readConfig{
    my $self = shift;
    until(-e $self->PATH . '/sisyphus.yml'){
	print STDERR "Waiting for config file " . $self->PATH . "/sisyphus.yml\n";
	if(-e $self->PATH . '/sisyphus.yml.gz'){
	    system('gunzip' , '-N',  $self->PATH . '/sisyphus.yml.gz');
	}
	sleep 5;
    }
    my $conf = YAML::Tiny->read($self->PATH . '/sisyphus.yml') || confess "Failed to read '" . $self->PATH . "/sisyphus.yml'\n";
    return $conf->[0];
}

=pod

=head2 runParameters()

 Title   : runParameters
 Usage   : $sis->runParameters()
 Function: returns the runParameters.xml as a XML::Simple object
 Example :
 Returns : XML::Simple object
 Args    : none

=cut

sub runParameters{
    my $self = shift;
    if(defined $self->{RUNPARAMS}){
	return $self->{RUNPARAMS};
    }
    my $rfPath = $self->{PATH};
    my $runParName = glob("$rfPath/[rR]unParameters.xml*");
    if($runParName =~ m/\.gz$/){
        `gunzip -N "$runParName"`;
	$runParName =~ s/\.gz$//;
    }

    my $runParams = XMLin($runParName) || confess "Failed to read runParameters.xml ($runParName)\n";
    unless(defined $runParams){
	confess "Failed to read runParameters.xml ($runParName)\n";
    }

    $self->{RUNPARAMS}=$runParams;
    return $runParams;
}

=pod

=head2 getRunMode()

 Title   : getRunMode
 Usage   : $sis->getRunMode()
 Function: returns the used RunMode
 Example :
 Returns : RunType string or undef
 Args    : none

=cut

sub getRunMode{
    my $self = shift;
    if(!defined $self->{RUNPARAMS}){
	confess "RunParameters haven't been loaded\n";
    }
    return $self->{RUNPARAMS}->{Setup}->{RunMode} eq "" ? return : $self->{RUNPARAMS}->{Setup}->{RunMode};
}

=pod

=head2 getApplicationName()

 Title   : getApplicationName
 Usage   : $sis->getApplicationName()
 Function: returns Application Name (MiSeq Control Software or HiSeq Control Software)
 Example :
 Returns : Application Name string or undef
 Args    : none

=cut

sub getApplicationName {
    my $self = shift;
    if(!defined $self->{RUNPARAMS}){
        confess "RunParameters haven't been loaded\n";
    }
    return $self->{RUNPARAMS}->{Setup}->{ApplicationName} eq "" ? return : $self->{RUNPARAMS}->{Setup}->{ApplicationName};
}

=pod

=head2 getRead1Length()

 Title   : getRead1Length
 Usage   : $sis->getRead1Length()
 Function: returns used read 1 length
 Example :
 Returns : Integer or undef
 Args    : none

=cut

sub getRead1Length {
    my $self = shift;
    if(!defined $self->{RUNPARAMS}){
        confess "RunParameters haven't been loaded\n";
    }
    if($self->machineType() eq "miseq") {
       foreach($self->{RUNPARAMS}->{Reads}->{RunInfoRead}->[0]) {
               return $_->{NumCycles} if($_->{IsIndexedRead} eq 'N');
       }
    }
    return $self->{RUNPARAMS}->{Setup}->{Read1} eq "" ? return : $self->{RUNPARAMS}->{Setup}->{Read1};
}

=pod

=head2 getRead2Length()

 Title   : getRead2Length
 Usage   : $sis->getRead2Length()
 Function: returns used read 2 length
 Example :
 Returns : Integer or undef
 Args    : none

=cut

sub getRead2Length{
    my $self = shift;
    if(!defined $self->{RUNPARAMS}){
        confess "RunParameters haven't been loaded\n";
    }
    if($self->machineType() eq "miseq") {
        my $second = 0;
        foreach(@{$self->{RUNPARAMS}->{Reads}->{RunInfoRead}}) {
            if($_->{IsIndexedRead} eq 'N') {
                if($second) {
                    return $_->{NumCycles};
                } else {
                    $second = 1;
                }
           }
        }
    }
    return $self->{RUNPARAMS}->{Setup}->{Read2} eq "" ? return : $self->{RUNPARAMS}->{Setup}->{Read2};
}

=pod

=head2 getBarcode()

 Title   : getBarcode
 Usage   : $sis->getBarcode()
 Function: returns the used barcode sequence
 Example :
 Returns : String or undef
 Args    : none

=cut

sub getBarcode{
    my $self = shift;
    if(!defined $self->{RUNPARAMS}){
        confess "RunParameters haven't been loaded\n";
    }
    return $self->{RUNPARAMS}->{Setup}->{Barcode} eq "" ? return : $self->{RUNPARAMS}->{Setup}->{Barcode};
}

=pod

=head2 getReagentKitVersion()

 Title   : getReagentKitVersion
 Usage   : $sis->getReagentKitVersion()
 Function: returns the used reagemt kit version
 Example :
 Returns : String or undef
 Args    : none

=cut

sub getReagentKitVersion{
    my $self = shift;
    if(!defined $self->{RUNPARAMS}){
        confess "RunParameters haven't been loaded\n";
    }
    if($self->machineType() eq "miseq") {
       return $self->{RUNPARAMS}->{ReagentKitVersion} eq ""  ? return : $self->{RUNPARAMS}->{ReagentKitVersion};
    } else {
       return $self->{RUNPARAMS}->{Setup}->{Flowcell} eq ""  ? return : $self->{RUNPARAMS}->{Setup}->{Flowcell};
    }
}


=pod

=head2 reads()

 Title   : reads()
 Usage   : $sis->reads()
 Function: Returns the reads from RunInfo.xml
 Example :
 Returns : Array of reads
 Args    : none

=cut

sub reads{
    my $self = shift;
    my $runInfo = $self->getRunInfo();
    return( @{$runInfo->{reads}} );
}

=pod

=head2 createReadMask()

 Title   : createReadMask()
 Usage   : $sis->createReadMask()
 Function: Creates a read mask for demultiplexing, skipping the last base in each read (except the index read on MiSeq)
 Example :
 Returns : String in the form Y*n,I*n,Y*n as described in the CASAVA documentation
 Args    : none

=cut

sub createReadMask{
    my $self = shift;
    my @readMask;
    my @reads = $self->reads();
    foreach my $read (@reads){
	if($read->{index} eq 'Y'){
	    push @readMask, 'I*';
	}else{
	    push @readMask, 'Y*n';
	}
    }
    return(join(',',@readMask));
}

=head2 qType

 Title   : qType
 Usage   : $sisyphus->qType($fastqFile)
 Function: Determine the quality value encoding of the fastq file
 Example :
 Returns : The offset value used.
 Args    : The path to a (gzipped or plain) fastq file

=cut

sub qType{
    # This version of sisyphus only works with CASAVA 1.8+ anyway,
    # so just return sanger format
    return(33);

    # Old code
    my $self = shift;
    my $fastqFile = shift;
    my $fq;
    if($fastqFile =~ m/\.gz/){
	open($fq, '-|', "zcat $fastqFile") or die "Failed to read $fastqFile with zcat: $!\n";
    }else{
	open($fq, $fastqFile) or die "Failed to read $fastqFile: $!\n";
    }
    while(<$fq>){
	my $name1 = $_;
	my $read = <$fq>;
	my $name2 = <$fq>;
	my $qual  = <$fq>;
	chomp($qual);
	# Illumina 1.0:  ASCII 59 = Q -5
	# Illumina 1.3+: ASCII 64 = Q  0
	# Illumina 1.0+: ASCII 94 = Q  30
	# Sanger:        ASCII 33 = Q  0
	# Sanger:        ASCII 80 = Q  47
	foreach(split //, $qual){
	    if(ord($_)<59){
		print STDERR "Found Q-value < 59. Assuming Phred/Sanger.\n" if($self->{DEBUG});
		close($fq);
		return(33);
	    }
	    if(ord($_)>80){
		print STDERR "Found Q-value > 80. Assuming Illumina 1.3+.\n" if($self->{DEBUG});
		close($fq);
		return(64);
	    }
	}
    }
    close($fq);
    die "Failed to determine Q-value type\n";
}


=pod

=head2 GenerateRgId

Generate a unique readgroup id.

=cut

sub GenerateRgId {
    my $self = shift;
    unless(exists $self->{RGSEED} && $self->{RGSEED}){
	my $t = time;
	$t=~s/^\d\d//;
	$self->{RGSEED} = $t - $$;
    }
    $self->{RGSEED}--;
    return($self->GenerateBase62($self->{RGSEED}));
}

=pod

=head2 GenerateBase

Change the base representation of a non-negative integer into base 62

Adopted from http://www.perlmonks.org/?node_id=27148

=cut

sub GenerateBase62 {
    my $self = shift;
    my $number = shift;
    my $base = 62;

    my @nums = (0..9,'a'..'z','A'..'Z')[0..$base-1];
    my $index = 0;
    my %nums = map {$_,$index++} @nums;

    return $nums[0] if $number == 0;
    my $rep = ""; # this will be the end value.
    while( $number > 0 )
      {
	  $rep = $nums[$number % $base] . $rep;
	  $number = int( $number / $base );
      }
    return $rep;
}

=pod

=head2 sampleSize()

 Title   : sampleSize($lane, $project, $sample, $tag)
 Usage   : $sis->sampleSize($lane, $project, $sample, $tag)
 Function: Returns the estimated number of sequences
           from a specific sample in a lane.
           Requires that demultiplexing has been done by CASAVA 1.8
 Example :
 Returns : Integer
 Args    : Lane number, project name, sample name, index tag

=cut

sub sampleSize{
    my $self = shift;
    my $lane = shift;
    my $proj = shift;
    my $sample = shift;
    my $tag = shift;

    if($proj eq 'Undetermined_indices'){
	$tag = 'Undetermined';
    }elsif($tag eq ''||!defined $tag){
	$tag = 'NoIndex';
    }
    my ($laneData,$sampleData) = $self->resultStats();
    # All reads should have the same number of clusters
    if(exists $sampleData->{$sample}->{$lane}->{1}->{$tag}->{PF}){
	return($sampleData->{$sample}->{$lane}->{1}->{$tag}->{PF});
    }
    confess "Failed to get number of clusters from SAMPLE $sample, LANE $lane, TAG $tag\n";
}

=pod

=head2 resultStats()

 Title   : resultStats
 Usage   : my $resultStats = $sis->resultStats()
 Function: Returns summary statistics for each sample and lane
           extracted from the InterOp folder and
           Unaligned/Basecall_Stats_X/Flowcell_demux_summary.xml
           Requires that demultiplexing has been done by CASAVA 1.8
 Returns : Two hashrefs with the following structure:
           LANE_ID => {
                       READ_ID => {
                                   QscoreSum  => Sum of all Q-scores,
                                   DensityRaw => Number of raw clusters/mm2,
                                   ErrRateSD  => Standard dev of ErrRate,
                                   YieldPF    => Yield Pass Filter,
                                   DensityPF  => Number of raw clusters/mm2,
                                   PF         => Number of PF clusters,
                                   ErrRate    => Error rate for phiX,
                                   Raw        => Number of raw clusters,
                                   AvgQ       => Average Q score,
                                   YieldQ30   => Yield with Q>=30,
                                   PctQ30     => Percent bases with Q>=30,
                                   PctPF      => Percent clusters PF,
                                  }
                       }

           SAMPLE_ID => {
                  LANE_ID => {
                       READ_ID => {
                            BARCODE => {
                                        QscoreSum  => Sum of all Q-scores,
                                        PctLane    => Percent of lane with this tag,
                                        YieldPF    => Yield Pass Filter,
                                        PF         => Number of PF clusters,
                                        mismatchCnt1 => Number of clusters with index mismatch,
                                        AvgQ       => Average Q score,
                                        YieldQ30   => Yield with Q>=30,
                                        PctQ30     => Percent bases with Q>=30
                                        TagErr     => Percent tags with an error,
                                       }
                                  }
                             }
                       }

 Args    : none

=cut

sub resultStats{
    my $self = shift;
    my $fc = $self->fcId();

    if(exists $self->{RESULTSTATS}->{LANEDATA} &&
       exists $self->{RESULTSTATS}->{SAMPLEDATA}){
	return($self->{RESULTSTATS}->{LANEDATA},$self->{RESULTSTATS}->{SAMPLEDATA});
    }

    my %laneData;
    my %sampleData;
    my $runInfo = $self->getRunInfo();
    my $numLanes = $self->laneCount();
    my $rId = 0;
    my %nCycles; # get number of cycles and subtract 1 since the last cycle is not included in input
    my $clusterMetrics = $self->readTileMetrics(); #These are the same for all reads
    my @reads = @{$runInfo->{reads}};
    foreach my $read (@reads){
	next if($read->{index} eq 'Y');
	$rId++; # Do not count index reads
	$nCycles{$rId} = $read->{last} - $read->{first}; # Do not add 1 here, as the last cycle is not used
	foreach my $lane (1..$numLanes){
	    if(exists $clusterMetrics->{$lane}){
		$laneData{$lane}->{$rId}->{Raw} = exists $clusterMetrics->{$lane}->{Raw} ? $clusterMetrics->{$lane}->{Raw}: 0;
		$laneData{$lane}->{$rId}->{PF} = exists $clusterMetrics->{$lane}->{PF} ? $clusterMetrics->{$lane}->{PF} : 0;
		$laneData{$lane}->{$rId}->{PctPF} = exists $clusterMetrics->{$lane}->{PF} && exists $clusterMetrics->{$lane}->{Raw} ?
		  sprintf('%.1f', $clusterMetrics->{$lane}->{PF} / $clusterMetrics->{$lane}->{Raw} * 100) : 0;
		$laneData{$lane}->{$rId}->{DensityRaw} = exists $clusterMetrics->{$lane}->{DensityRaw} ? $clusterMetrics->{$lane}->{DensityRaw} : 0;
		$laneData{$lane}->{$rId}->{DensityPF} = exists $clusterMetrics->{$lane}->{DensityPF} ? $clusterMetrics->{$lane}->{DensityPF} : 0;
		$laneData{$lane}->{$rId}->{ExcludedTiles} = $clusterMetrics->{$lane}->{ExcludedTiles};
	    }else{
		$laneData{$lane}->{$rId}->{Raw} = 0;
		$laneData{$lane}->{$rId}->{PF} = 0;
		$laneData{$lane}->{$rId}->{PctPF} = 0;
		$laneData{$lane}->{$rId}->{DensityRaw} = 0;
		$laneData{$lane}->{$rId}->{DensityPF} = 0;
		# All tiles excluded
		$laneData{$lane}->{$rId}->{ExcludedTiles} = $runInfo->{tiles};
	    }
	}
	# Get the error rate at the last (used) cycle, using 1-based cycle numbering
	my $errorMetrics = $self->readErrorMetrics($read->{first}+1, $read->{last}, 0);
	# Get the error rate of excluded tiles at the last (used) cycle, using 1-based cycle numbering
	my $errorMetricsExcl = $self->readErrorMetrics($read->{first}+1, $read->{last}, 1);
	foreach my $lane (keys %{$errorMetrics}){
	    $laneData{$lane}->{$rId}->{ErrRate} = sprintf('%.2f', $errorMetrics->{$lane}->{ErrRate});
	    $laneData{$lane}->{$rId}->{ErrRateSD} = sprintf('%.2f', $errorMetrics->{$lane}->{ErrRateSD});
	    if(exists($clusterMetrics->{$lane}) && exists($clusterMetrics->{$lane}->{ExcludedTiles})){
		$laneData{$lane}->{$rId}->{Excluded}->{ErrRate} = sprintf('%.2f', $errorMetricsExcl->{$lane}->{ErrRate});
		$laneData{$lane}->{$rId}->{Excluded}->{ErrRateSD} = sprintf('%.2f', $errorMetricsExcl->{$lane}->{ErrRateSD});
	    }
	}
    }

    my $sampleData;
    if($self->machineType eq 'hiseqx') {
	$sampleData = $self->readDemultiplexStatsHiSeqX($self->{PATH} . '/Unaligned/Stats/DemultiplexingStats.xml', $self->{PATH} . '/Unaligned/Stats/ConversionStats.xml', \%nCycles, \%laneData);
    } else {
	$sampleData = $self->readDemultiplexStats($self->{PATH} . '/Unaligned/Basecall_Stats_' . $fc .'/Flowcell_demux_summary.xml', \%nCycles, \%laneData);
    }

    $self->{RESULTSTATS}->{LANEDATA} = \%laneData;
    $self->{RESULTSTATS}->{SAMPLEDATA} = $sampleData;
#    {
#	no warnings;
#	Hash::Util::lock_hashref($self->{RESULTSTATS}->{LANEDATA});
#	Hash::Util::lock_hashref($self->{RESULTSTATS}->{SAMPLEDATA});
#    }
    return(\%laneData,$sampleData);
}



sub readDemultiplexStats{
    my $self = shift;
    my $xmlDemFile = shift;
    my $nCycles = shift;
    my $laneData = shift;

    my %sampleData;
    my $laneDataTmp;

    if(-e "$xmlDemFile.gz" && !-e $xmlDemFile){
	system("gunzip", "$xmlDemFile.gz")==0 or die "Failed to gunzip $xmlDemFile.gz:$!\n";
    }
    if(-e $xmlDemFile){
	my $summary = XMLin($xmlDemFile,ForceArray=>['Read','Lane','Sample','Tile','Barcode']) || confess "Failed to read $xmlDemFile\n";
	foreach my $lane (@{$summary->{Lane}}){
	    my $lid = $lane->{index};
	    foreach my $sample (@{$lane->{Sample}}){
		my $name = $sample->{index};
		foreach my $barcode (@{$sample->{Barcode}}){
		    my $tag = $barcode->{index};
		    $tag = '' if($tag eq 'NoIndex');
		    foreach my $tile (@{$barcode->{Tile}}){
			foreach my $read (@{$tile->{Read}}){
			    my $rId = $read->{index};
			    $sampleData{$name}->{$lid}->{$rId}->{$tag}->{YieldQ30} += $read->{Pf}->{YieldQ30};
			    $sampleData{$name}->{$lid}->{$rId}->{$tag}->{QscoreSum} += $read->{Pf}->{QualityScoreSum};
			    $sampleData{$name}->{$lid}->{$rId}->{$tag}->{PF} += $read->{Pf}->{ClusterCount};
			    $sampleData{$name}->{$lid}->{$rId}->{$tag}->{YieldPF} += $read->{Pf}->{Yield};
			    $sampleData{$name}->{$lid}->{$rId}->{$tag}->{mismatchCnt1} += $read->{Pf}->{ClusterCount1MismatchBarcode};
			    $laneDataTmp->{$lid}->{$rId}->{YieldQ30} += $read->{Pf}->{YieldQ30};
			    $laneDataTmp->{$lid}->{$rId}->{QscoreSum} += $read->{Pf}->{QualityScoreSum};
			}
		    }
		}
	    }
	}
    }else{
	confess "Failed to extract data from $xmlDemFile: file does not exist\n";
    }

    # Calculate per lane metrics
    foreach my $lid (keys %{$laneDataTmp}){
	foreach my $rId (keys %{$laneDataTmp->{$lid}}){
	    my $lane = $laneDataTmp->{$lid};
	    if(exists $laneData->{$lid}){
		$lane->{$rId}->{YieldPF} = exists($laneData->{$lid}->{$rId}->{PF}) ? $laneData->{$lid}->{$rId}->{PF} * $nCycles->{$rId} : 0;
		$lane->{$rId}->{PctQ30} = exists($lane->{$rId}->{YieldQ30}) && exists($lane->{$rId}->{YieldPF}) && $lane->{$rId}->{YieldPF} > 0 ?
		  $lane->{$rId}->{YieldQ30} / $lane->{$rId}->{YieldPF} : 0;
		$lane->{$rId}->{AvgQ} = exists($lane->{$rId}->{QscoreSum}) && exists($lane->{$rId}->{YieldPF}) && $lane->{$rId}->{YieldPF} > 0 ?
		  $lane->{$rId}->{QscoreSum} / $lane->{$rId}->{YieldPF} : 0;
	    }else{
		$lane->{$rId}->{YieldQ30} = 0;
		$lane->{$rId}->{QscoreSum} = 0;
		$lane->{$rId}->{YieldQPF} = 0;
		$lane->{$rId}->{PctQ30} = 0;
		$lane->{$rId}->{AvgQ} = 0;
	    }
	}
    }

    # And some more per sample metrics
    foreach my $name (keys %sampleData){
        foreach my $lid (keys %{$sampleData{$name}}){
            foreach my $rId (keys %{$sampleData{$name}->{$lid}}){
                foreach my $tag (keys %{$sampleData{$name}->{$lid}->{$rId}}){
		    if(exists $sampleData{$name}->{$lid}->{$rId}->{$tag}->{PF} &&
		       $sampleData{$name}->{$lid}->{$rId}->{$tag}->{PF} > 0){

			$sampleData{$name}->{$lid}->{$rId}->{$tag}->{TagErr} =
			  $sampleData{$name}->{$lid}->{$rId}->{$tag}->{mismatchCnt1} /
			    $sampleData{$name}->{$lid}->{$rId}->{$tag}->{PF}*100;

			$sampleData{$name}->{$lid}->{$rId}->{$tag}->{PctLane} =
			  $sampleData{$name}->{$lid}->{$rId}->{$tag}->{PF} /
			    $laneData->{$lid}->{$rId}->{PF} * 100;
		    }
		    if(exists $sampleData{$name}->{$lid}->{$rId}->{$tag}->{YieldPF} &&
		       $sampleData{$name}->{$lid}->{$rId}->{$tag}->{YieldPF} > 0){

			$sampleData{$name}->{$lid}->{$rId}->{$tag}->{AvgQ} =
			  $sampleData{$name}->{$lid}->{$rId}->{$tag}->{QscoreSum} /
			    $sampleData{$name}->{$lid}->{$rId}->{$tag}->{YieldPF};

			$sampleData{$name}->{$lid}->{$rId}->{$tag}->{PctQ30} =
			  $sampleData{$name}->{$lid}->{$rId}->{$tag}->{YieldQ30} /
			    $sampleData{$name}->{$lid}->{$rId}->{$tag}->{YieldPF} * 100;
		    }
		}
	    }
	}
    }


    # Set sample info for failed lanes
    my $sampleSheet = $self->readSampleSheet();
    foreach my $proj (keys %{$sampleSheet}){
	foreach my $lid (keys %{$sampleSheet->{$proj}}){
	    foreach my $tag (keys %{$sampleSheet->{$proj}->{$lid}}){
		my $name = $sampleSheet->{$proj}->{$lid}->{$tag}->{SampleID};
		unless(exists $sampleData{$name}->{$lid}){
		    foreach my $rId (keys %{$laneData->{$lid}}){
			$sampleData{$name}->{$lid}->{$rId}->{$tag}->{YieldQ30} = 0;
			$sampleData{$name}->{$lid}->{$rId}->{$tag}->{QscoreSum} = 0;
			$sampleData{$name}->{$lid}->{$rId}->{$tag}->{PF} = 0;
			$sampleData{$name}->{$lid}->{$rId}->{$tag}->{YieldPF} = 0;
			$sampleData{$name}->{$lid}->{$rId}->{$tag}->{mismatchCnt1} = 0;
			$sampleData{$name}->{$lid}->{$rId}->{$tag}->{TagErr} = 0;
			$sampleData{$name}->{$lid}->{$rId}->{$tag}->{PctLane} = 0;
			$sampleData{$name}->{$lid}->{$rId}->{$tag}->{AvgQ} = 0;
			$sampleData{$name}->{$lid}->{$rId}->{$tag}->{PctQ30} = 0;
		    }
		}
	    }
	}
    }







    # Copy data from $laneDataTmp to $laneData
    foreach my $lane (keys %{$laneDataTmp}){
	foreach my $rId (keys %{$laneDataTmp->{$lane}}){
	    foreach my $key (keys %{$laneDataTmp->{$lane}->{$rId}}){
		$laneData->{$lane}->{$rId}->{$key} = $laneDataTmp->{$lane}->{$rId}->{$key};
	    }
	}
   }

    return \%sampleData;
}

sub readDemultiplexStatsHiSeqX{
    my $self = shift;
    my $xmlDemFile = shift;
    my $conversionFile = shift;
    my $nCycles = shift;
    my $laneData = shift;

    my %sampleData;
    my $laneDataTmp;

    if(-e "$conversionFile.gz" && !-e $conversionFile){
       system("gunzip", "$conversionFile.gz")==0 or die "Failed to gunzip $conversionFile.gz:$!\n";
    }
    if(-e $conversionFile){
        my $stats = XMLin($conversionFile,ForceArray=>['Read','Tile','Lane','Project', 'Sample', 'Flowcell', 'Barcode'], KeyAttr => {item => 'name'}) || confess "Failed to read $conversionFile\n";        
        foreach my $flowcell (@{$stats->{Flowcell}}){
            my $flowcellId = $flowcell->{'flowcell-id'};
            foreach my $project (@{$flowcell->{'Project'}}){
                my $projectName = $project->{name};
                foreach my $sample (@{$project->{Sample}}){
                    my $sampleName = $sample->{name};
                    foreach my $barcode (@{$sample->{Barcode}}){
                        my $tag = $barcode->{name};
                        $tag = '' if($tag eq 'NoIndex');
                        foreach my $lane (@{$barcode->{Lane}}){
                            my $lid = $lane->{number};
                            foreach my $tile (@{$lane->{Tile}}){
                                my $pf = $tile->{Pf};
                                foreach my $read (@{$pf->{Read}}){
                                    my $rId = $read->{number};
                                    if(!($tag eq 'all')) {
                                        $sampleData{$sampleName}->{$lid}->{$rId}->{$tag}->{PF} += $pf->{ClusterCount};
                                        $sampleData{$sampleName}->{$lid}->{$rId}->{$tag}->{YieldQ30} += $read->{YieldQ30};
                                        $sampleData{$sampleName}->{$lid}->{$rId}->{$tag}->{QscoreSum} += $read->{QualityScoreSum};
                                        $sampleData{$sampleName}->{$lid}->{$rId}->{$tag}->{YieldPF} += $read->{Yield};
                                        $laneDataTmp->{$lid}->{$rId}->{YieldQ30} += $read->{YieldQ30};
                                        $laneDataTmp->{$lid}->{$rId}->{QscoreSum} += $read->{QualityScoreSum};
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }else{
        confess "Failed to extract data from $xmlDemFile: file does not exist\n";
    }
    if(-e "$xmlDemFile.gz" && !-e $xmlDemFile){
        system("gunzip", "$xmlDemFile.gz")==0 or die "Failed to gunzip $xmlDemFile.gz:$!\n";
    }
    if(-e $xmlDemFile){
        my $xmlDemStat = XMLin($xmlDemFile,ForceArray=>['Lane','Project', 'Sample', 'Flowcell', 'Barcode'], KeyAttr => {item => 'name'}) || confess "Failed to read $conversionFile\n";
        foreach my $flowcell (@{$xmlDemStat->{Flowcell}}){
            my $flowcellId = $flowcell->{'flowcell-id'};
            foreach my $project (@{$flowcell->{'Project'}}){
                my $projectName = $project->{name};
                foreach my $sample (@{$project->{Sample}}){
                    my $sampleName = $sample->{name};
                    foreach my $barcode (@{$sample->{Barcode}}){
                        my $tag = $barcode->{name};
                        $tag = '' if($tag eq 'NoIndex');
                        if(!($tag eq 'all')) {
                            foreach my $lane (@{$barcode->{Lane}}){
                                my $lid = $lane->{number};
                                foreach my $rId (keys %{$sampleData{$sampleName}->{$lid}}) {
                                    $sampleData{$sampleName}->{$lid}->{$rId}->{$tag}->{mismatchCnt1} += $lane->{OneMismatchBarcodeCount};
                                }
                            }
                        }
                    }
                }
            }
        }
    }else{
        confess "Failed to extract data from $xmlDemFile: file does not exist\n";
    }

    # Calculate per lane metrics
    foreach my $lid (keys %{$laneDataTmp}){
        foreach my $rId (keys %{$laneDataTmp->{$lid}}){
            my $lane = $laneDataTmp->{$lid};
            if(exists $laneData->{$lid}){
                $lane->{$rId}->{YieldPF} = exists($laneData->{$lid}->{$rId}->{PF}) ? $laneData->{$lid}->{$rId}->{PF} * $nCycles->{$rId} : 0;
                $lane->{$rId}->{PctQ30} = exists($lane->{$rId}->{YieldQ30}) && exists($lane->{$rId}->{YieldPF}) && $lane->{$rId}->{YieldPF} > 0 ?
                    $lane->{$rId}->{YieldQ30} / $lane->{$rId}->{YieldPF} : 0;
                $lane->{$rId}->{AvgQ} = exists($lane->{$rId}->{QscoreSum}) && exists($lane->{$rId}->{YieldPF}) && $lane->{$rId}->{YieldPF} > 0 ?
                    $lane->{$rId}->{QscoreSum} / $lane->{$rId}->{YieldPF} : 0;
            }else{
                $lane->{$rId}->{YieldQ30} = 0;
                $lane->{$rId}->{QscoreSum} = 0;
                $lane->{$rId}->{YieldQPF} = 0;
                $lane->{$rId}->{PctQ30} = 0;
                $lane->{$rId}->{AvgQ} = 0;
            }
        }
    }

    # And some more per sample metrics
    foreach my $name (keys %sampleData){
        foreach my $lid (keys %{$sampleData{$name}}){
            foreach my $rId (keys %{$sampleData{$name}->{$lid}}){
                foreach my $tag (keys %{$sampleData{$name}->{$lid}->{$rId}}){
                    $tag = '' if($tag eq 'NoIndex');
                    if(exists $sampleData{$name}->{$lid}->{$rId}->{$tag}->{PF} &&
                        $sampleData{$name}->{$lid}->{$rId}->{$tag}->{PF} > 0){
                        $sampleData{$name}->{$lid}->{$rId}->{$tag}->{TagErr} =
                            $sampleData{$name}->{$lid}->{$rId}->{$tag}->{mismatchCnt1} /
                            $sampleData{$name}->{$lid}->{$rId}->{$tag}->{PF}*100;

                        $sampleData{$name}->{$lid}->{$rId}->{$tag}->{PctLane} =
                            $sampleData{$name}->{$lid}->{$rId}->{$tag}->{PF} /
                            $laneData->{$lid}->{$rId}->{PF} * 100;
                    }
                    if(exists $sampleData{$name}->{$lid}->{$rId}->{$tag}->{YieldPF} &&
                        $sampleData{$name}->{$lid}->{$rId}->{$tag}->{YieldPF} > 0){

                        $sampleData{$name}->{$lid}->{$rId}->{$tag}->{AvgQ} =
                            $sampleData{$name}->{$lid}->{$rId}->{$tag}->{QscoreSum} /
                            $sampleData{$name}->{$lid}->{$rId}->{$tag}->{YieldPF};

                        $sampleData{$name}->{$lid}->{$rId}->{$tag}->{PctQ30} =
                            $sampleData{$name}->{$lid}->{$rId}->{$tag}->{YieldQ30} /
                            $sampleData{$name}->{$lid}->{$rId}->{$tag}->{YieldPF} * 100;
                    }
                }
            }
        }
    }

    # Set sample info for failed lanes
    my $sampleSheet = $self->readSampleSheet();
    foreach my $proj (keys %{$sampleSheet}){
        foreach my $lid (keys %{$sampleSheet->{$proj}}){
            foreach my $tag (keys %{$sampleSheet->{$proj}->{$lid}}){
                my $name = $sampleSheet->{$proj}->{$lid}->{$tag}->{SampleName};
                unless(exists $sampleData{$name}->{$lid}){
                    foreach my $rId (keys %{$laneData->{$lid}}){
                        $sampleData{$name}->{$lid}->{$rId}->{$tag}->{YieldQ30} = 0;
                        $sampleData{$name}->{$lid}->{$rId}->{$tag}->{QscoreSum} = 0;
                        $sampleData{$name}->{$lid}->{$rId}->{$tag}->{PF} = 0;
                        $sampleData{$name}->{$lid}->{$rId}->{$tag}->{YieldPF} = 0;
                        $sampleData{$name}->{$lid}->{$rId}->{$tag}->{mismatchCnt1} = 0;
                        $sampleData{$name}->{$lid}->{$rId}->{$tag}->{TagErr} = 0;
                        $sampleData{$name}->{$lid}->{$rId}->{$tag}->{PctLane} = 0;
                        $sampleData{$name}->{$lid}->{$rId}->{$tag}->{AvgQ} = 0;
                        $sampleData{$name}->{$lid}->{$rId}->{$tag}->{PctQ30} = 0;
                    }
                }
            }
        }
    }

    # Copy data from $laneDataTmp to $laneData
    foreach my $lane (keys %{$laneDataTmp}){
        foreach my $rId (keys %{$laneDataTmp->{$lane}}){
            foreach my $key (keys %{$laneDataTmp->{$lane}->{$rId}}){
                $laneData->{$lane}->{$rId}->{$key} = $laneDataTmp->{$lane}->{$rId}->{$key};
            }
        }
    }

    return \%sampleData;
}

=pod

=head2 readTileMetrics()

 Title   : readTileMetrics()
 Usage   : readTileMetrics(bool $excludedOnly)
 Function: Reads the tile metrics (clusters) from InterOp/TileMetricsOut.bin.
           If excludedOnly is set, then only include excluded tiles in the metrics.
 Example :
 Returns : A hash ref with the lane as key, and hashrefs with the following keys as value
   Raw - Number of raw
   PF  - Number of pass filter clusters
   DensityRaw - Mean raw tile density (clusters/mm2)
   DensityPF - Mean pass filter density (clusters/mm2)
   TileData - Hash ref with per tile values with keys Density, DensityPF, Raw, PF, Aligned
              Where the value of Aligned is a hash ref with the percent aligned reads of the
              tile as value and the read number as key
 Args    : none

 File formats according to RTA theory of operation (RTA 1.12) Pub. No. 770-2009-020, current as of 9 May 11

=cut

sub readTileMetrics{
    my $self = shift;
    my $excludedOnly = shift || 0;
    my $rfPath = $self->{PATH};
    my $interOp="$rfPath/InterOp";

    # Return cached version if it exists
    return $self->{TILEMETRICS}->{$excludedOnly} if(defined $self->{TILEMETRICS}->{$excludedOnly});

    my $excludedTiles = $self->excludedTiles();

    print STDERR "Reading data from $interOp/TileMetricsOut.bin\n" if($self->{DEBUG});
    my $tmfh;
    if(-e "$interOp/TileMetricsOut.bin" ){
	open($tmfh, "$interOp/TileMetricsOut.bin") or croak "Failed to open TileMetricsOut.bin";
    }elsif(-e "$interOp/TileMetricsOut.bin.gz"){
	open($tmfh, '-|', "zcat $interOp/TileMetricsOut.bin") or croak "Failed to open TileMetricsOut.bin.gz";
    }else{
	confess "Failed to find $interOp/TileMetricsOut.bin";
    }

    binmode($tmfh);
    my $buf;

    # Read and check file format version
    read($tmfh, $buf, 1);
    print STDERR "Format version: " . unpack('C',$buf) . "\n" if($self->{DEBUG});
    confess "Unexpected file version of TileMetricsOut.bin" unless( unpack('C',$buf)==2 );

    # Get the record length
    read($tmfh, $buf, 1);
    my $rlen = unpack('C', $buf);
    print STDERR "Record length: $rlen\n" if($self->{DEBUG});
    confess "Unexpected record length in TileMetricsOut.bin" unless( $rlen==10 );

    # Iterate over each record
    my %tileMetrics;
    my %laneMetrics;
    while(read($tmfh,$buf,$rlen)){
	my($lane,$tile,$code,$val) = unpack('SSSf',$buf);
	print STDERR "Lane: $lane\n" if($self->{DEBUG});
	print STDERR "Tile: $tile\n" if($self->{DEBUG});
	if(! $excludedOnly && exists $excludedTiles->{$lane}->{$tile}){
	    print STDERR "Tile $lane $tile excluded\n" if($self->{DEBUG});
	    next;
	}elsif($excludedOnly && ! exists $excludedTiles->{$lane}->{$tile}){
	    print STDERR "Tile $lane $tile included\n" if($self->{DEBUG});
	    next;
	}

	print STDERR "Code: $code\n" if($self->{DEBUG});
	print STDERR "Val: $val\n" if($self->{DEBUG});
	if($code==100){ # Tile denstiy raw
	    $tileMetrics{$lane}->{Density}->{$tile} = $val;
	}elsif($code==101){# Tile density PF
	    $tileMetrics{$lane}->{DensityPF}->{$tile} = $val;
	}elsif($code==102){ # Tile clusters raw
	    $laneMetrics{$lane}->{Raw} += $val;
	    $tileMetrics{$lane}->{Raw}->{$tile} = $val;
	}elsif($code==103){# Tile clusters PF
	    $laneMetrics{$lane}->{PF} += $val;
	    $tileMetrics{$lane}->{PF}->{$tile} = $val;
	}elsif($code>=300 && $code<400){ # Tile % aligned for read N
	    $tileMetrics{$lane}->{Aligned}->{$tile}->{$code-299} = $val;
	}
    }
    close($tmfh);
    foreach my $lane (keys %laneMetrics){
	$laneMetrics{$lane}->{DensityRaw} = $self->mean(values %{$tileMetrics{$lane}->{Density}});
	$laneMetrics{$lane}->{DensityPF} = $self->mean(values %{$tileMetrics{$lane}->{DensityPF}});
	$laneMetrics{$lane}->{TileData} = $tileMetrics{$lane};
	unless($excludedOnly){
	    $laneMetrics{$lane}->{ExcludedTiles} = (defined $excludedTiles->{$lane} && keys %{$excludedTiles->{$lane}} > 0 ) ?
	      scalar( keys %{$excludedTiles->{$lane}} ) - 2 : 0; # Two keys are for metadata
	}
    }

    $self->{TILEMETRICS}->{$excludedOnly} = \%laneMetrics;
#    {
#	no warnings;
#	Hash::Util::lock_hashref($self->{TILEMETRICS}->{$excludedOnly});
#    }
    return $self->{TILEMETRICS}->{$excludedOnly};
}


=pod

=head2 readErrorMetrics()

 Title   : readErrorMetrics()
 Usage   : readErrorMetrics($first,$last)
 Function: Reads the error metrics from InterOp/ErrorMetricsOut.bin and calculates the lane mean and average
 Example :
 Returns : A hash ref with the lane as key, and hashrefs with the following keys as value
   ErrorRate - Mean Error rate over all tiles from the first to the last cycle
   ErrorRateSD - Standard Dev of error rate over all tiles from the first to the last cycle
 Args    : none

=cut

sub readErrorMetrics{
    my $self = shift;
    my $first = shift;
    my $last = shift;
    my $excludedOnly = shift || 0;

    my $errMetrics = $self->readRawErrorMetrics($first,$last);
    my $excludedTiles = $self->excludedTiles();
    my %filteredMetrics;
    my %metrics;

    foreach my $lane (keys %{$errMetrics}){
	# Now calculate errors over aligned for each tile
	foreach my $tile (keys %{$errMetrics->{$lane}}){
	    if(! $excludedOnly && exists $excludedTiles->{$lane}->{$tile}){
		next;
	    }elsif($excludedOnly && ! exists $excludedTiles->{$lane}->{$tile}){
		next;
	    }
	    $filteredMetrics{$lane}->{$tile} = $errMetrics->{$lane}->{$tile};
	}

	# And finally calculate tile mean and stddev
	$metrics{$lane}->{ErrRate} = $self->mean(grep {$_<100} values %{$filteredMetrics{$lane}});
	$metrics{$lane}->{ErrRateSD} = $self->stddev(grep {$_<100} values %{$filteredMetrics{$lane}});
    }
    return \%metrics;
}


=pod

=head2 readRawErrorMetrics()

 Title   : readRawErrorMetrics()
 Usage   : readRawErrorMetrics($first,$last)
 Function: Reads the error metrics from InterOp/ErrorMetricsOut.bin
 Example :
 Returns : A hash ref with the following structure
           $errMetrics->{$lane}->{$tile} = number of errors / number aligned
 Args    : first and last cycle in the read to calculate the error for

 File formats according to RTA theory of operation (RTA 1.12) Pub. No. 770-2009-020, current as of 9 May 11

=cut

sub readRawErrorMetrics{
    my $self = shift;
    my $first = shift;
    my $last = shift;
    my $rfPath = $self->{PATH};
    my $interOp="$rfPath/InterOp";
    my $read = $self->cycleToRead($first);
    unless($read == $self->cycleToRead($last)){
	confess "Cycles $first and $last belong to different reads!";
    }

    if(exists $self->{RAW_ERROR_METRICS}->{$first}->{$last}){
	return $self->{RAW_ERROR_METRICS}->{$first}->{$last};
    }

    my $tileMetrics = $self->readTileMetrics();
    my $tileMetricsEx = $self->readTileMetrics(1);
    my %metrics;

    print STDERR "Reading data from $interOp/ErrorMetricsOut.bin\n" if($self->{DEBUG});
    my $fh;
    if(-e "$interOp/ErrorMetricsOut.bin" ){
	open($fh, "$interOp/ErrorMetricsOut.bin") or croak "Failed to open ErrorMetricsOut.bin";
    }elsif(-e "$interOp/ErrorMetricsOut.bin.gz"){
	open($fh, '-|', "zcat $interOp/ErrorMetricsOut.bin") or croak "Failed to open ErrorMetricsOut.bin.gz";
    }else{
	# A run can be done without phiX
	carp "Failed to find $interOp/ErrorMetricsOut.bin";
	return \%metrics;
    }

    binmode($fh);
    my $buf;

    # Read and check file format version
    read($fh, $buf, 1);
    print STDERR "Format version: " . unpack('C',$buf) . "\n" if($self->{DEBUG});
    confess "Unexpected file version of ErrorMetricsOut.bin" unless( unpack('C',$buf)==3 );

    # Get the record length
    read($fh, $buf, 1);
    my $rlen = unpack('C', $buf);
    print STDERR "Record length: $rlen\n" if($self->{DEBUG});
    confess "Unexpected record length in TileMetricsOut.bin" unless( $rlen==30 );

    # Iterate over each record
    my %errMetrics;
    while(read($fh,$buf,$rlen)){
	# We only use the error rate now, but parse the rest if we need it in the future
	my($lane,$tile,$cycle,$err,$nPerf,$n1err,$n2err,$n3err,$n4err) = unpack('SSSfLLLLL',$buf);

	print STDERR "Lane: $lane\n" if($self->{DEBUG});
	print STDERR "Tile: $tile\n" if($self->{DEBUG});
	print STDERR "Cycle: $cycle\n" if($self->{DEBUG});
	print STDERR "Err: $err\n" if($self->{DEBUG});
#	print STDERR "nPerf: $nPerf\n" if($self->{DEBUG});
#	print STDERR "n1err: $n1err\n" if($self->{DEBUG});
#	print STDERR "n2err: $n2err\n" if($self->{DEBUG});
#	print STDERR "n3err: $n3err\n" if($self->{DEBUG});
#	print STDERR "n4err: $n4err\n" if($self->{DEBUG});

	# The error rate is defined as the number of errors/number of aligned bases
	# So we have to sum up all errors from first to last cycle,
	# and the total number of aligned bases in the same cycles

	# Only look at data for the requested cycles
	if($cycle >= $first && $cycle <= $last){
	    # Get number of aligned clusters
	    my $n;
	    if(exists($tileMetrics->{$lane}) && exists($tileMetrics->{$lane}->{TileData}->{PF}->{$tile})){
		$n = $tileMetrics->{$lane}->{TileData}->{PF}->{$tile} *
		  $tileMetrics->{$lane}->{TileData}->{Aligned}->{$tile}->{$read}/100;
	    }elsif(exists($tileMetricsEx->{$lane}) && exists($tileMetricsEx->{$lane}->{TileData}->{PF}->{$tile})){
		$n = $tileMetricsEx->{$lane}->{TileData}->{PF}->{$tile} *
		  $tileMetricsEx->{$lane}->{TileData}->{Aligned}->{$tile}->{$read}/100;
	    }
	    # Sum errors over all cycles for each tile
	    $errMetrics{$lane}->{ERRORS}->{$tile} += $err*$n;
	    # Sum total number of aligned bases
	    $errMetrics{$lane}->{ALIGNED}->{$tile} += $n;
	}
    }
    close($fh);

    # Now we can divide the number of errors with the number of aligned bases
    my %errors;
    my $runInfo = $self->getRunInfo() || croak "Failed to read RunInfo.xml\n";

    # As only tiles with aligned phiX is represented, some tiles will be missing if the
    # error is too high.
    # We cannot discriminate lanes without phiX from lanes with too high error, but a
    # lane without any aligned read is unlikely
    # Lanes without phiX should not be a key in the errMetrics, so there should be
    # no risk with setting a very high error on tiles without phiX
    foreach my $lane (keys %errMetrics){
	foreach my $tile (keys %{$errMetrics{$lane}->{ERRORS}}){
	    my $flowcellLayot = $runInfo->{xml}->{Run}->{FlowcellLayout};
	    for(my $surf=1; $surf<=$flowcellLayot->{SurfaceCount}; $surf++){
		for(my $swath=1; $swath<=$flowcellLayot->{SwathCount}; $swath++){
		    for(my $t=1; $t<=$flowcellLayot->{TileCount}; $t++){
			my $tile = sprintf("$surf$swath%02d", $t);
			if(exists $errMetrics{$lane}->{ERRORS}->{$tile} && exists $errMetrics{$lane}->{ALIGNED}->{$tile}){
			    $errors{$lane}->{$tile} = $errMetrics{$lane}->{ERRORS}->{$tile} / $errMetrics{$lane}->{ALIGNED}->{$tile};
			}else{
			    $errors{$lane}->{$tile} = 100;
			}
		    }
		}
	    }
	}
    }
    $self->{RAW_ERROR_METRICS}->{$first}->{$last} = \%errors;
    return \%errors;
}

=pod

=head2 mkpath()

 Title   : mkpath()
 Usage   : mkpath($path,$mode)
 Function: Creates a directory, with parents
 Example :
 Returns : True on success
 Args    : A path to create and optionally permissions (as used in the system call mkdir), permissions defaults to the system default.

=cut

sub mkpath{
    my($self,$mode,$path);
    if(ref($_[0]) =~ m/Sisyphus::Common/){
	$self = shift;
    }
    $path = shift;
    $mode = shift if(@_);
    unless($path=~m:^/:){
	$path = cwd() . "/$path";
    }
#    print STDERR "Creating path $path\n";
    my $retval = 1;
    if($mode){
	my $parent = '/';
	foreach my $dir (split '/', $path){
	    next if(length($dir)<1);
	    unless(-e "$parent$dir"){
#		print STDERR "mkdir $parent$dir\n";
		$retval = system('mkdir', '-m', $mode, "$parent$dir");
		if($retval != 0){
		    carp "Failed to create dir '$parent$dir' with mode mode $mode: $!\n";
		}
	    }
	    $parent .= "$dir/";
	}
    }else{
	$retval = system('mkdir', '-p', $path);
	if($retval != 0){
	    croak "Failed to create dir '$path': $!\n";
	}
    }
    if($retval==0){
	return 1;
    }
    return 0;
}


=pod

=head2 fixSampleSheet()

 Title   : fixSampleSheet()
 Usage   : $sisyphus->fixSampleSheet($path)
 Function: Fixes common problems in the sample sheet and warns about errors. Also converts MiSeq samplesheet to the format expected by CASAVA.
 Example :
 Returns : True if sample sheet is OK.
 Args    : Sample sheet path

=cut

sub fixSampleSheet{
    my $self = shift;
    my $sampleSheet = shift || $self->PATH . '/SampleSheet.csv';

    unless(-e $sampleSheet){
	print STDERR "SampleSheet '$sampleSheet' does not exist\n";
	return 0;
    }

    # Make sure sample sheet has Unix format
    print STDERR "Convering '$sampleSheet' to unix format.\n";
    system('dos2unix', $sampleSheet)==0 or croak "Failed to convert sample sheet to unix format.\n";

    # What type of run is this
    my $type = $self->machineType;

    my $output;

    # Check that the SampleSheet contains info about the correct flowcell
    # and that no tag is present more than once in each lane
    my $rfPath = $self->PATH;
    my $fcId = $self->fcId();
    my $ok = 1;
    my $l=0;
    my %lanes;
    open(my $ssfh, $sampleSheet);
    my $test = <$ssfh>;
    seek($ssfh,0,0); # Rewind filehandle again

    if($test =~ m/^FCID/){
	# Sample sheet already in hiseq format
	$type = 'hiseq';
    }

    if($type eq 'hiseq'){
	while(<$ssfh>){
	    chomp;
	    s/\xA0//g; # Clean up some Windows/Excel copy paste remnant
	    $l++;
	    # Clean up empty rows and carrige return
	    next unless(m/\w/);
	    s/[\s\r\n]//g; # Remove any whitespaces (incl newline)
	    $_ .= "\n"; # Add proper newline
	    if(m/^FCID/ && $l==1){ # Skip header
		$output .= $_;
	    }elsif(m/^#/){ # Skip comments
		$output .= $_; # or should we rather delete them?
	    }else{
		my @r = split /,/, $_;
		# remove unallowed characters from sample name
		$r[2] =~ s/[\?\(\)\[\]\/\\\=\+\<\>\:\;\"\'\,\*\^\|\&\.]/_/g;
		if($r[0] !~ m/^$fcId$/){
		    print STDERR "Flowcell mismatch at line $l (expected '$fcId', got '$r[0]')\n";
		    $ok=0;
		}
		$output .= join ',', @r;
		$lanes{$r[1]}->{$r[4]}++;
	    }
	}
	close($ssfh);
    }elsif($type eq 'hiseqx'){
        my $dataFound = 0;
        open ADAPTORS, "> $rfPath/Adaptors.txt" or die "Couldn't open output file: $rfPath/Adaptors.txt\n";
        while(<$ssfh>){
            chomp;
            s/\xA0//g; # Clean up some Windows/Excel copy paste remnant
            $l++;
            # Clean up empty rows and carrige return
            next unless(m/\w/);
            s/[\s\r\n]//g; # Remove any whitespaces (incl newline)
            $_ .= "\n"; # Add proper newline
            if(m/^\[Data\]/){ # Skip header
                $dataFound = 1;
                $output .= $_;
            }elsif($dataFound != 1){ # Skip comments
                if(/^Adapter/) {
                    my @r = split /,/, $_;
                    if($r[1] =~ /^[ACGT]+$/) {
                        print ADAPTORS $r[0] . "," . $r[1] ."\n";
                        $r[1] = "";
                        $output .= join ',', @r;
                    } else {
                        $output .= $_;
                    }
                } else {
                    $output .= $_; # or should we rather delete them?
                }
            }else{
                my @r = split /,/, $_;
                # remove unallowed characters from sample name
                $r[1] =~ s/[\?\(\)\[\]\/\\\=\+\<\>\:\;\"\'\,\*\^\|\&\._]/-/g if(!($r[0] eq "Lane"));
                $r[2] =~ s/[\?\(\)\[\]\/\\\=\+\<\>\:\;\"\'\,\*\^\|\&\._]/-/g if(!($r[0] eq "Lane"));
		$r[1] = "Sample_" . $r[1] if($r[1] eq $r[2]);
		$r[1] =~ s/Sample-/Sample_/;
                $output .= join ',', @r;
                $lanes{$r[0]}->{$r[6]}++;
            }
        }
        close(ADAPTORS);
        close($ssfh);
    }elsif($type eq 'miseq'){
	my $dataStart=0;
	my $projName='MiSeq';
	my @header;
	while(<$ssfh>){
	    chomp;
	    if(m/^Project Name,([^,]*),?/){
		$projName=$1;
	    }
	    if(m/^\[Data\]/){
		$dataStart = 1;
		my $r = <$ssfh>;
		chomp($r);
		@header = split /,/, $r, -1;
		# expected MiSeq header
		#Sample_ID,Sample_Name,Sample_Plate,Sample_Well,Sample_Project,index,I7_Index_ID,Description,GenomeFolder



                #Sample_ID,Sample_Name,Sample_Plate,Sample_Well,I7_Index_ID,index,I5_Index_ID,index2,Sample_Project,Description,Manifest,GenomeFolder
		# Check that the columns we want to use are the ones we expect

		foreach my $head (qw(Sample_ID Sample_Project index Description)){
		    unless(grep /^$head$/, @header){
			croak "Missing column header '$head' in SampleSheet\n";
		    }
		}
		# Add the Casava compatible header to output
		$output = "FCID,Lane,SampleID,SampleRef,Index,Description,Control,Recipe,Operator,SampleProject\n";
		next;
	    }
	    next unless($dataStart);
	    my %vals;
	    @vals{@header} = split /,/, $_, -1;
	    $vals{Sample_Project} = $projName unless(defined $vals{Sample_Project} && length($vals{Sample_Project})>0);
	    # remove unallowed characters from sample name
	    $vals{Sample_ID} =~ s/[\?\(\)\[\]\/\\\=\+\<\>\:\;\"\'\,\*\^\|\&\.]/_/g;

	    if(exists $vals{index2} && defined $vals{index2}){
		$output .= join(',', ($fcId,1,$vals{Sample_ID},'',"$vals{index}-$vals{index2}",$vals{Description},'','','',$vals{Sample_Project})) . "\n";
		$lanes{1}->{"$vals{index}-$vals{index2}"}++;
	    }else{
		$output .= join(',', ($fcId,1,$vals{Sample_ID},'',$vals{index},$vals{Description},'','','',$vals{Sample_Project})) . "\n";
		$lanes{1}->{$vals{index}}++;
	    }
	}
    }else{
	croak "Unknown instrument type";
    }

    foreach my $lane (keys %lanes){
	foreach my $tag (keys %{$lanes{$lane}}){
	    if($lanes{$lane}->{$tag} > 1){
		print STDERR "Tag $tag has multiple entries for lane $lane\n";
		$ok = 0;
	    }
	}
    }
    # Replace the old sample sheet with a fixed up version if all tests passed
    if($ok){
        # Pick the next available name for keeping a copy of the old samplesheet
        my $i = 1;
        while(-e "$sampleSheet.org.$i"){
	        $i++;
        }
        my $sampleSheetBak = "$sampleSheet.org.$i";
        # ..but if we have converted a miseq samplesheet, save the original under a stable name that can be used when uploading entire folder
        if ($type eq 'miseq') {
            ($sampleSheetBak = $sampleSheet) =~ s/\.csv/.miseq.csv/;
        }
	    rename($sampleSheet, $sampleSheetBak) or die "Failed to move $sampleSheet to $sampleSheetBak\n";
        open(my $fhOut, '>', $sampleSheet) or die "Failed to create new samplesheet in $sampleSheet\n";
        print $fhOut $output;
        close($fhOut);
    }
    return($ok);
}


=pod

=head2 fcId()

 Title   : fcId()
 Usage   : $sisyphus->fcId
 Function: Returns the flowcell ID of the run
 Example :
 Returns : Flowcell ID
 Args    : none

=cut

sub fcId{
    my $self = shift;
    my $runInfo = $self->getRunInfo();
    return $runInfo->{xml}->{Run}->{Flowcell};
}

=pod

=head2 laneCount()

 Title   : laneCount()
 Usage   : $sisyphus->laneCount
 Function: Returns the number of lanes in the run
 Example :
 Returns : number of lanes
 Args    : none

=cut

sub laneCount{
    my $self = shift;
    my $runInfo = $self->getRunInfo();
    my $runParams = $self->runParameters();
    my $numLanes = 8; # Default to 8
    if(exists $runParams->{Setup}->{NumLanes}){
	# This works on MiSeq
	$numLanes = $runParams->{Setup}->{NumLanes};
    }elsif(exists $runInfo->{xml}->{Run}->{FlowcellLayout}->{LaneCount}){
	# And this on HiSeq2000
	$numLanes = $runInfo->{xml}->{Run}->{FlowcellLayout}->{LaneCount};
    }
    return $numLanes
}

=pod

=head2 machineType()

 Title   : machineType()
 Usage   : $sisyphus->machineType
 Function: Returns the machine type used for the run
 Example :
 Returns : miseq or hiseq
 Args    : none

=cut

sub machineType{
    my $self = shift;
    my $type = "hiseq"; # Default to hiseq
    my $runParams = $self->runParameters();
    if($runParams->{Setup}->{ApplicationName} =~ m/miseq/i){
	$type = "miseq";
    } elsif($runParams->{Setup}->{ApplicationName} =~ m/HiSeq X/i) {
        $type = "hiseqx";
    }
    return $type;
}

=pod

=head2 cycleToRead()

 Title   : cycleToRead()
 Usage   : $sisyphus->cycleToRead($cycle)
 Function: Returns the read number of $cycle
 Example :
 Returns : 1 based read number
 Args    : a cycle number

=cut

sub cycleToRead{
    my $self = shift;
    my $cycle = shift;
    $cycle--; # Adjust to zero based
    my $runInfo = $self->getRunInfo();
    foreach my $read (@{$runInfo->{reads}}){
	return( $read->{id} ) if($cycle >= $read->{first} && $cycle<=$read->{last});
    }
    confess "Failed to determine read number for cycle $cycle";
}

=pod

=head2 positionsFormat()

 Title   : positionsFormat
 Usage   : $sisyphus->positionsFormat()
 Function: Returns the positions format used in the runfolder
 Example :
 Returns : .locs, .clocs or .pos.txt
 Args    : none

=cut

sub positionsFormat{
    my $self = shift;
    my $rfPath = $self->{PATH};
    # Force glob into list context using a funny reference/dereference structure
    if( @{[glob "$rfPath/Data/Intensities/*/*.clocs"]} > 0){
	return '.clocs';
    }
    if( @{[glob "$rfPath/Data/Intensities/*/*.locs"]} > 0 || @{[glob "$rfPath/Data/Intensities/*.locs"]} > 0){
	return '.locs';
    }
    if( @{[glob "$rfPath/Data/Intensities/*/*.pos.txt"]} > 0){
	return '.pos.txt';
    }
    croak "Failed to determine positions format\n";
}


=head2 excludeTiles()

 Title   : excludeTiles()
 Usage   : $sisyphus->excludeTiles()
 Function: Identify tiles with too high error
 Example :
 Returns : A two dimensional hashref with excluded tiles, lane as fist key and tile as second key
 Args    : none

=cut

sub excludeTiles{
    my $self = shift;
    my $rfPath = $self->{PATH};

    my $exFile = "$rfPath/excludedTiles.yml";
    if(-e $exFile){
	my $i = 1;
	while(-e "$exFile.$i"){
	    $i++;
	}
	system('mv', $exFile, "$exFile.$i")==0 or croak "Failed to rename existing $exFile to $exFile.$i\n";
    }

    my %excluded;
    my $runInfo = $self->getRunInfo();
    my $rId = 0;

    my $config = $self->readConfig;
    my $laneLimit = defined($config->{MAX_LANE_ERROR}) ? $config->{MAX_LANE_ERROR} : 2;
    my $tileLimit = defined($config->{MAX_TILE_ERROR}) ? $config->{MAX_TILE_ERROR} : 2.5;

    my $rawErrMetrics;
    # First identify any lanes where any of the reads has an error > 2%
    my %failedLanes;
    my @reads = @{$runInfo->{reads}};
    foreach my $read (@reads){
	next if($read->{index} eq 'Y');
	$rId++; # Do not count index reads
	# Get the error rate at the last (used) cycle, using 1-based cycle numbering
	my $errMetrics = $self->readErrorMetrics($read->{first}+1, $read->{last}, 0);
	$rawErrMetrics->{$rId} = $self->readRawErrorMetrics($read->{first}+1, $read->{last});
	foreach my $lane (keys %{$errMetrics}){
	    if($errMetrics->{$lane}->{ErrRate} > $laneLimit){
		push @{$failedLanes{$lane}}, $rId;
	    }
	}
    }

    # First exclude tiles with an error > 2.5%
    foreach my $lane (keys %failedLanes){
	foreach my $rId (@{$failedLanes{$lane}}){
	    foreach my $tile (keys %{$rawErrMetrics->{$rId}->{$lane}}){
		if($rawErrMetrics->{$rId}->{$lane}->{$tile} > $tileLimit){
		    $excluded{$lane}->{$tile}->{$rId} = $rawErrMetrics->{$rId}->{$lane}->{$tile};
		}
	    }
	}
    }

    # Then exclude the tile with most error until the mean tile error is < 2%
    foreach my $lane (keys %failedLanes){
	foreach my $rId (@{$failedLanes{$lane}}){
	    my @included = grep { ! exists($excluded{$lane}->{$_}) } keys %{$rawErrMetrics->{$rId}->{$lane}};
	    while(@included > 0 && $self->mean(@{$rawErrMetrics->{$rId}->{$lane}}{@included}) > $laneLimit){
		my @tiles = sort( {$rawErrMetrics->{$rId}->{$lane}->{$b} <=> $rawErrMetrics->{$rId}->{$lane}->{$a} } @included );
		$excluded{$lane}->{$tiles[0]}->{$rId} = $rawErrMetrics->{$rId}->{$lane}->{$tiles[0]};
		@included = grep { ! exists($excluded{$lane}->{$_}) } keys %{$rawErrMetrics->{$rId}->{$lane}};
	    }
	    $excluded{$lane}->{BEFORE}->{$rId} = $self->mean(grep {$_<100} values %{$rawErrMetrics->{$rId}->{$lane}});
	    $excluded{$lane}->{AFTER}->{$rId} = $self->mean(grep {$_<100} @{$rawErrMetrics->{$rId}->{$lane}}{@included});
	}
    }

    YAML::Tiny::DumpFile("$rfPath/excludedTiles.yml", \%excluded) || confess "Failed to write '$rfPath/excludedTiles.yml'\n";
    return \%excluded;
}

=head2 excludedTiles()

 Title   : excludedTiles()
 Usage   : $sisyphus->excludedTiles()
 Function: List tiles with too high error. Reads the info from excludedTiles.yml in the runfolder.
           If the file does not exist, returns an empty hashref.
           The file excludedTiles.yml is created by excludeTiles()
 Example :
 Returns : A two dimensional hashref with excluded tiles, lane as fist key and tile as second key
 Args    : none

=cut

sub excludedTiles{
    my $self = shift;
    my $rfPath = $self->{PATH};
    my $excluded = {};
    if(-e "$rfPath/excludedTiles.yml.gz"){
	system('gunzip' , '-N',  "$rfPath/excludedTiles.yml.gz");
    }
    if(-e "$rfPath/excludedTiles.yml"){
	$excluded = YAML::Tiny::LoadFile("$rfPath/excludedTiles.yml") || confess "Failed to read '$rfPath/excludedTiles.yml'\n";
    }
    return $excluded;
}

=pod

=head2 mean()

 Title   : mean()
 Usage   : $sisyphus->mean(@values)
 Function: Returns the mean value of @values, or zero if list is empty
 Example :
 Returns : mean value
 Args    : Values to take mean of

=cut

sub mean{
    my $self = shift;
    return 0 if(@_ == 0);
    my $sum=0;
    my $n=0;
    foreach my $v (@_){
	$sum += $v;
	$n++;
    }
    return($sum/$n);
}

=pod

=head2 stddev()

 Title   : stddev()
 Usage   : $sisyphus->stddev(@values)
 Function: Returns the standard deviation of @values or zero if list is empty
 Example :
 Returns : standard deviation
 Args    : Array of values

=cut

sub stddev{
    my $self = shift;
    return 0 if(@_ == 0);
    my $mean = $self->mean(@_);
    my $sum=0;
    my $n=-1;
    foreach my $v (@_){
	$sum += ($v-$mean)**2;
	$n++;
    }
    if($n>0){
	return( sqrt($sum/$n) );
    }
    return 0;
}

=pod

=head2 excludeLane()

 Title   : excludeLane()
 Usage   : $sisyphus->excludeLane($lane)
 Function: Excludes a lane from delivery by adding it to the excluded lanes in the configuration
 Example :
 Returns : nothing
 Args    : a lane number

=cut

sub excludeLane{
    my $self = shift;
    my $lane = shift;

    my $config = $self->readConfig();
    if( defined $config->{SKIP_LANES} ){
	unless(grep {$_==$lane} @{$config->{SKIP_LANES}} ){
	    open(my $confh, '+<', $self->PATH . '/sisyphus.yml') or die "Failed to open " . $self->PATH . "/sisyphus.yml\n";
#	    local $/=undef;
#	    my $confTxt = <$confh>;
#	    $confTxt =~ s/^SKIP_LANES:$/SKIP_LANES:\n - $lane/m;
	    my $confTxt;
	    my $skipLanes = '';
	    my $flag = 0;
	    while(<$confh>){
		if($flag && (m/^#/||m/^\s*$/)){
		    $flag = 0;
		}elsif(m/^SKIP_LANES:/ || $flag){
		    if($flag){
			s/^\s+/ /;
		    }else{
			$confTxt .= "SKIP_LANES_HERE\n";
			$flag = 1;
		    }
		    $skipLanes .= $_;
		}
		$confTxt .= $_ unless($flag);
	    }
	    $skipLanes .= " - $lane\n";
	    $confTxt =~ s/^SKIP_LANES_HERE$/$skipLanes/m;
	    seek($confh,0,0);
	    print $confh $confTxt;
	    close($confh);
	}
    }else{
	open(my $confh, '>>', $self->PATH . '/sisyphus.yml') or die "Failed to open " . $self->PATH . "/sisyphus.yml\n";
	print $confh "SKIP_LANES:\n - $lane\n";
	close($confh);
    }
}



1;
