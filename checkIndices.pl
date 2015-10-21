#!/usr/bin/perl -w

use FindBin;                # Find the script location
use lib "$FindBin::Bin/lib";# Add the script libdir to libs
use Molmed::Sisyphus::Libpath;

use strict;
use Getopt::Long;
use Pod::Usage;
use File::Basename;

use Molmed::Sisyphus::Common qw(mkpath);
use Molmed::Sisyphus::QStat;
=pod

=head1 NAME

checkIndices.pl - Check if there seems to be something something wrong with the indices

=head1 SYNOPSIS

 checkIndices.pl -help|-man
 checkIndices.pl -runfolder <path to runfolder> -demuxSummary <path to folder containing DemuxSummary files> 

=head1 OPTIONS

=over 4

=item -h|-help

prints out a brief help text.

=item -m|-man

Opens the manpage.

=item -runfolder 

Full path to runfolder of interest

=item -demuxSummary

Path to folder containing DemuxSummary files, e.g. '<path to runfolder>/Unaligned/Stats'

=item -debug

Print debugging information

=back

=head1 DESCRIPTION

Checks if there is anything supicious about the index sequences before performing demultiplexing on all data

=cut

# Parse options
my($help,$man) = (0,0);
my $DemuxSumPath = "";
my $rfPath = "";
our $debug = 0;

GetOptions('help|?'=>\$help,
            'man'=>\$man,
            'runfolder=s' => \$rfPath,
	        'demuxSummary=s' => \$DemuxSumPath,
	        'debug'=> \$debug,
	  ) or pod2usage(-verbose => 0);
pod2usage(-verbose => 1)  if ($help);
pod2usage(-verbose => 2)  if ($man);

unless(defined $rfPath && -e $rfPath){
    print STDERR "Runfolder not specified or does not exist\n";
    pod2usage(-verbose => 1);
    exit;
}

# Create a new sisyphus object for common functions
my $sisyphus = Molmed::Sisyphus::Common->new(PATH=>$rfPath, DEBUG=>$debug);
$rfPath = $sisyphus->PATH;

# Setting default DemuxSummaryPath
if (length($DemuxSumPath)==0){
    $DemuxSumPath = $rfPath . "/Unaligned/Stats";
}

my $sampleSheet = $sisyphus->readSampleSheet();
#my $machineType = $sisyphus->machineType();

my $flowCellID = $sisyphus->fcId();
my $noOfSamples = $sisyphus->samplesPerLane(); 
my $numLanes = $sisyphus->laneCount();
my $failedIndexCheck = 0;
my $passedIndexCheck;

# Read demuxSummary files for each lane, store info in hash
my %indexCount;
my @numberOfIndices = 1; 
my $LanePrefix = "DemuxSummaryF1L";
my $indexSection;
my @refIndices;

foreach my $lane (1..$numLanes){

    $indexSection = 0;
    my (@counts, @indices1, @indices2);

    #Check if current read is applicable for lane
    open (my $fh, "<", "$DemuxSumPath/$LanePrefix$lane.txt") or die "Can't open the file $DemuxSumPath/$LanePrefix$lane.txt: ";

    while (my $line =<$fh>){
                    
	    chomp ($line);		

		    if ($line =~ /Index_Sequence/ || $indexSection ){           
     				
			    $indexSection = 1;
			
			    # skip header	
                if ($line !~ /Index_Sequence/){
                
                    my($index, $count) = split("\t", $line);
                
			        my($index1, $index2) = split(/\Q+\E/, $index);

                    push (@counts, $count);
                    push (@indices1, $index1);
			    
                    if ($index2){
			            push (@indices2, $index2);
                    }
                }
            }
    }

    # Data is saved to hash
    $indexCount{$lane} = {'Indices' => { 'Index1' => \@indices1, 'Index2' => \@indices2 }, 'Counts' => \@counts};
    
}

print "\nChecking indices...\n";

foreach my $lane (1..$numLanes){

    foreach my $indexRead (keys %{$indexCount{$lane}{'Indices'}}){

        if (@{$indexCount{$lane}{'Indices'}{$indexRead}}){
    
            my @sigCounts = significanceTest($indexCount{$lane}{'Counts'}, $indexCount{$lane}{'Indices'}{$indexRead}, $lane);

            # Number of index with significant counts
            my $sigCount = @sigCounts;

            if ($sigCount > 1){
            
                print "\nThere are $sigCount significant undetermined index counts for Lane $lane $indexRead: \n";
            
            }
            if ($sigCount == 1){
            
                print "\nThere is $sigCount significant undetermined index count for Lane $lane $indexRead: \n";

            }

            $passedIndexCheck = 0;        

            foreach my $unidentifiedIndex (@sigCounts){
        
                foreach my $idxRead (keys %{$indexCount{$lane}{'Indices'}}){

                    if (@{$noOfSamples->{$lane}->{'Indices'}->{$idxRead}}){

                        @refIndices = @{$noOfSamples->{$lane}->{'Indices'}->{$idxRead}};
                
                        if ( grep {$_ eq $unidentifiedIndex} @refIndices){
                        
                            if ($idxRead eq $indexRead){
                    
                                print "Index $unidentifiedIndex is present in Samplesheet among $indexRead. OK!\n";
            
                                $passedIndexCheck = 1;                     
                    
                            }
                            else{
                    
                                print "It appears that $unidentifiedIndex is present in Samplesheet among $idxRead. ";
                        
                            }

                        }
                        elsif ( mismatch($unidentifiedIndex, \@refIndices) ){

                            if ($idxRead eq $indexRead){
                    
                                print "Index $unidentifiedIndex is one mismatch from being a correct index among $indexRead. OK!\n";
                                
                                $passedIndexCheck = 1;
          
                            }
                            else{
                      
                                print "Index $unidentifiedIndex is one mismatch from being a correct index among $idxRead. ";
                            
                            }

                        }
                        elsif ($unidentifiedIndex =~ /N\.*N/ ){

                            print "Index $unidentifiedIndex contains read errors. OK!\n";

                            $passedIndexCheck = 1; 

                        }
                        elsif (grep {$_ eq reverse($unidentifiedIndex)} @refIndices){

                            if ($idxRead eq $indexRead){

                                print "The reverse of index $unidentifiedIndex is present in SampleSheet among $indexRead. ";
                            
                            }
                            else{
                            
                                print "The reverse of index $unidentifiedIndex is present in SampleSheet among $idxRead. ";

                            }

                        }
                        elsif (grep {$_ eq reverseComplement($unidentifiedIndex, 1)} @refIndices){

                            if ($idxRead eq $indexRead){
                    
                                print "The complement of index $unidentifiedIndex is present in SampleSheet among $indexRead. ";

                            }
                            else{

                                print "The complement of index $unidentifiedIndex is present in SampleSheet among $idxRead. ";

                            }

                        }
                        elsif (grep {$_ eq reverseComplement($unidentifiedIndex, 0)} @refIndices){

                            if ($idxRead eq $indexRead){

                                print "The reverse complement of index $unidentifiedIndex is present in SampleSheet among $indexRead. ";

                            }
                            else{

                                print "The reverse complement of index $unidentifiedIndex is present in SampleSheet among $idxRead. ";
                        
                            }
                        }
                
                    }
                
                }
                unless ($passedIndexCheck){

                print "Please investigate index $unidentifiedIndex.\n";

                $failedIndexCheck = 1; 

                }
     
            }

        }
    }
}

if($failedIndexCheck){

    print "\n";
    exit 1;

}
else{

    print "Undetermined indices OK!\n\n"

}

sub significanceTest{

    my @countArray = @{$_[0]};
    my @indexArray = @{$_[1]};
    my $lane = $_[2];
    
    my $total = $sisyphus->getBarcodeCount($lane, $DemuxSumPath);

    my @sigIndices;

    my $counter = 0;

    # Start with the first (and greatest) element
    my $count = $countArray[$counter];

    while ($count >= 0.01*$total){

        push ( @sigIndices, $indexArray[$counter] );

        $counter++;

        $count = $countArray[$counter];
        
    }

    
    return @sigIndices;

}

sub mismatch{

    my $index = $_[0];
    my @shIndices = @{$_[1]};

    my @mismatchArray;

    # Compare index with SampleSheet indices and count number of mismatches
    for my $shIndex (@shIndices){
        
        my $noMismatches = 0;
        
        for(0 .. length($index)) {
        
            my $char = substr($shIndex, $_, 1);
             
                   if ($char ne substr($index, $_, 1)) {
                
                        $noMismatches++;
                    } 
        }
        
        push (@mismatchArray, $noMismatches);
    }

    #Check if index is one mismatch from a real index
    if (grep {$_ == 1} @mismatchArray){

        return 1;
    }

    else {

        return 0;
    
    }

}

sub reverseComplement{

    my $tag = $_[0];
    my $justComp = $_[1];
    
    my $revComp = $tag;
 
    unless($justComp){
        # Reverse index/tag 
        $revComp = reverse $tag;
    }

    # Complement index/tag
    $revComp =~ tr/ACGTacgt/TGCAtgca/;
 
    return $revComp;

}

