package Molmed::Sisyphus::IndexCheck;

use strict;
use warnings;
use Data::Dumper;
use Molmed::Sisyphus::Common;


use base 'Exporter';
our @EXPORT = qw(checkIndices);

sub checkIndices{

	my $sisyphus = $_[0];	
	my $DemuxSumPath = $_[1];
	my $noOfSamples = $_[2];
	my $numLanes = $_[3];
	my $debug = $_[4];

	my $failedIndexCheck = 0;
	my $passedIndexCheck;

	# Read demuxSummary files for each lane, store info in hash
	my %indexCount;
	my $LanePrefix = "DemuxSummaryF1L";
	my $indexSection;
	my @refIndices;

	foreach my $lane (1..$numLanes){

		$indexSection = 0;
		
		my (@counts, @indices1, @indices2);

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

	if ($debug){

		print "INDEXCOUNT HASH:\n";
		print Dumper(\%indexCount);
		print "SAMPLES PER LANE HASH:\n";
		print Dumper($noOfSamples);

	}	

	print "\nChecking indices...\n";

	foreach my $lane (1..$numLanes){

		foreach my $indexRead (keys %{$indexCount{$lane}{'Indices'}}){

			if (@{$indexCount{$lane}{'Indices'}{$indexRead}}){
			
				my %sigCounts = significanceTest($indexCount{$lane}{'Counts'}, $indexCount{$lane}{'Indices'}{$indexRead}, $lane, $sisyphus, $DemuxSumPath);

				# Number of indices with significant counts
				my $sigCount = keys %sigCounts;

				if ($sigCount > 1){
				
					print "\nThere are $sigCount significant undetermined index counts for Lane $lane $indexRead: \n";
				
				}
				if ($sigCount == 1){
				
					print "\nThere is $sigCount significant undetermined index count for Lane $lane $indexRead: \n";

				}

				foreach my $unidentifiedIndex (keys %sigCounts){
	
					$passedIndexCheck = 0;
	
					foreach my $idxRead (keys %{$indexCount{$lane}{'Indices'}}){

						if (@{$noOfSamples->{$lane}->{'Indices'}->{$idxRead}}){

							@refIndices = @{$noOfSamples->{$lane}->{'Indices'}->{$idxRead}};
					
							if ( grep {$_ eq $unidentifiedIndex} @refIndices){
							
								if ($idxRead eq $indexRead){
						
									print "Index $unidentifiedIndex is present in Samplesheet among $indexRead. OK!\n";
				
									$passedIndexCheck = 1;					 
						
								}
								else{
						
									print "It appears that $unidentifiedIndex is present in Samplesheet among $idxRead.\n";
							
								}

							}
							elsif ( mismatch($unidentifiedIndex, \@refIndices) ){

								if ($idxRead eq $indexRead){
						
									print "Index $unidentifiedIndex is one mismatch from being a correct index among $indexRead. OK!\n";
									
									$passedIndexCheck = 1;
			  
								}
								else{
						  
									print "Index $unidentifiedIndex is one mismatch from being a correct index among $idxRead.\n";
								
								}

							}
							elsif ($unidentifiedIndex =~ /N.*N/ ){

								print "Index $unidentifiedIndex contains read errors. OK!\n";

								$passedIndexCheck = 1; 

							}
							elsif (grep {$_ eq reverse($unidentifiedIndex)} @refIndices){

								if ($idxRead eq $indexRead){

									print "The reverse of index $unidentifiedIndex is present in SampleSheet among $indexRead.\n";
								
								}
								else{
								
									print "The reverse of index $unidentifiedIndex is present in SampleSheet among $idxRead.\n";

								}

							}
							elsif (grep {$_ eq reverseComplement($unidentifiedIndex, 1)} @refIndices){

								if ($idxRead eq $indexRead){
						
									print "The complement of index $unidentifiedIndex is present in SampleSheet among $indexRead.\n";

								}
								else{

									print "The complement of index $unidentifiedIndex is present in SampleSheet among $idxRead.\n";

								}

							}
							elsif (grep {$_ eq reverseComplement($unidentifiedIndex, 0)} @refIndices){

								if ($idxRead eq $indexRead){

									print "The reverse complement of index $unidentifiedIndex is present in SampleSheet among $indexRead.\n";

								}
								else{

									print "The reverse complement of index $unidentifiedIndex is present in SampleSheet among $idxRead.\n";
							
								}
							}
					
						}
					
					}
					unless ($passedIndexCheck){

						my $rounded = sprintf("%.3f", $sigCounts{$unidentifiedIndex});
						print "Please investigate index $unidentifiedIndex. ($rounded% of all reads in lane $lane)\n";

						$failedIndexCheck = 1; 

					}
			 
				}

			}
		}
	}

	return $failedIndexCheck;
}

sub significanceTest{

	my @countArray = @{$_[0]};
	my @indexArray = @{$_[1]};
	my $lane = $_[2];
	my $sisyphus = $_[3];
	my $DemuxSumPath = $_[4];
	
	my $total = $sisyphus->getBarcodeCount($lane, $DemuxSumPath);

	my %sigIndices;

	my $counter = 0;

	# Start with the first (and greatest) element
	my $count = $countArray[$counter];

	while ($count >= 0.01*$total){

		$sigIndices{$indexArray[$counter]} = $count/$total*100;

		$counter++;

		$count = $countArray[$counter];
		
	}

	return %sigIndices;

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

1
