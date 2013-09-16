package Molmed::Sisyphus::QStat;

use strict;
use Carp;
use PDL;
use Data::Dumper;
use Archive::Zip qw( :ERROR_CODES :CONSTANTS );
use File::Basename;
use Molmed::Sisyphus::Common qw(mkpath);

our $AUTOLOAD;

=pod

=head1 NAME

Molmed::Sisyphus::QStat - Collect and write score & sequence statistics from strings

=head1 SYNOPSIS

use Molmed::Sisyphus::Qstat;

my $qstat =  Molmed::Sisyphus::Qstat->new(
  OFFSET=>$offset,
  LANE=>$lane,
  READ=>$read,
  PROJECT=>$project,
  SAMPLE=>$sample,
  TAG=>$tag,
  MAXSAMPLES=>1e5,
  SAMPLING_DENSITY=>1e5/$total,
  DEBUG=>$debug
 );

=head1 DESCRIPTION

This module is used for collecting and summarizing statistics on Q-values.

=head1 CONSTRUCTORS

=head2 new()

=over 4

=item OFFSET

The offset used for ASCII encoding of the input Q-values.
Required.

=item READ

Read number (1-based). Required.

=item PROJECT

The lane from which the data was collected.

=item PROJECT

The project to which the sample belongs.

=item SAMPLE

The name of the sample.

=item LANE

Source lane of the data.

=item TAG

Expected index tag in the data. Use empty string if for samples without index tag.

=item MAXSAMPLES

Maximum number of unique sequences kept in memory for counting copy-number. Defaults to 100.000

=item SAMPLING_DENSITY

Fraction of sequences to samples, defaults to 1%.

=item DEBUG

Print debug information.

=back

=cut

sub new{
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = {@_};

    $self->{ADAPTERS}->{TRUSEQ} = ["AGATCGGAAGAGCACACGTC",
                                   "AGATCGGAAGAGCGTCGTGT"];

    # Set default max number of samplings
    unless(exists $self->{MAXSAMPLES}){
	$self->{MAXSAMPLES} = 1e5;
    }
    # Set default sampling density to 1%
    unless(exists $self->{SAMPLING_DENSITY}){
	$self->{SAMPLING_DENSITY} = 0.01;
    }
    # Init GC array
    unless(exists $self->{SEQGC}){
	# Percentage bins
	$self->{SEQGC} = [split //, "0" x 101];
    }
    # Init sequence counter
    unless(defined $self->{SEQUENCES}){
	$self->{SEQUENCES} = {};
    }

    bless ($self, $class);
    return $self;
}

=pod

=head1 SELECTORS

Any key set on object creation is available as a selector method.

The currently recommended keys are listed below, but there is no
restriction implemented.

=over

=item RUNFOLDER - Sisyphus::Common Object

=item OFFSET - Offset used for Q-values

=item PROJECT - Project of the sample

=item SAMPLE - Sample for which statistics were collected

=item TAG - Expected index tag in the data. Use empty string if for samples without index tag.

=item LANE - The lane from which the data was collected

=item READ - Read 1 or 2

=item OUTDIR - Base name of output directory

=item OUTFILE - Name of output file

=item INFILE - Name of input file

=back

=cut

sub AUTOLOAD {
    my $self = shift;
    my $type = ref($self)
      or confess "$self is not an object";

    return if $AUTOLOAD =~ /::DESTROY$/;

    my $name = $AUTOLOAD;
    $name =~ s/.*://;   # strip fully-qualified portion
    $name =~ tr/a-z/A-Z/; # Use uppercase

    if(@_>0){
	$self->{$name} = shift;
    }

    unless ( exists $self->{$name} ) {
        confess "Can't access `$name' field in class $type";
    }
    return $self->{$name};
}

=pod

=head1 FUNCTIONS

=head2 addDataPoint()

 Title   : addDataPoint
 Usage   : $qstat->addDataPoint($seq,$qstring)
 Function: Parses a sequence and quality string and adds them to the statistics
 Example : $qstat->addDataPoint($seq,$qstring)
 Returns : nothing
 Args    : a sequence and quality string

=cut

sub addDataPoint{
    my $self = shift;
    my $seq = shift;
    my $qstring = shift;

    chomp($seq);
    chomp($qstring);
    $seq =~ tr/a-z/A-Z/;

    $self->countCopies($seq);

    if(rand() < $self->{SAMPLING_DENSITY}){
	$self->addQstring($qstring);
	$self->addBaseDist($seq);
	$self->countGC($seq);
	$self->checkAdaptor($seq);
    }
    return 1;
}

=pod

=head2 addQstring()

 Title   : addQstring
 Usage   : $qstat->addQstring($qstring)
 Function: Parses a FASTQ quality string and adds it to the statistics
 Example : $qstat->addQstring($qstring)
 Returns : nothing
 Args    : a FASTQ quality string

=cut

sub addQstring{
    my $self = shift;
    my $qstring = shift;

    confess "Missing OFFSET for parsing of Q-value strings\n" unless(exists $self->{OFFSET});

    # Init a new zero piddle of type byte and length equal to string length
    my $len = length($qstring);
    unless(exists $self->{zeroPDL}->{$len}){
	$self->{zeroPDL}->{$len} = PDL->zeroes (byte, $len);;
    }
    my $pdl = $self->{zeroPDL}->{$len};
    # Replace the piddle content with the string
    ${$pdl->get_dataref} = $qstring;
    # Update piddle internal references
    $pdl->upd_data;

    # The piddle now holds the ascii values in the string
    # The offset is applied in the histogram function which will create 41
    # bins with the offset as bin 0.

    # Calculate histogram with Q value count as columns and cycle number as rows
    # Use $pdl->slice('*1') instead of transpose as it is the same thing for 1D arrays
    my $hist = histogram($pdl->slice('*1'), 1, $self->{OFFSET}, 41);
    if(exists $self->{QHIST}){
	$self->{QHIST} += $hist;
    }else{
	$self->{QHIST} = $hist;
    }

    # Find the fist occurence of Q<30 in string
#    my $ind = PDL->initialize();
#    PDL::_which_int($pdl < ($self->{OFFSET} + 30),$ind);

    # Find the length of the longest continuous stretch of Q>=30 in seq
    # WARNING!!!
    # This will alter the pdl-vector, so it best be last!
    # WARNING!!!
    my $ind = PDL->initialize();
    PDL::_which_int($pdl >= ($self->{OFFSET} + 30),$ind);

    if($ind->nelem == 0){
	$self->{Q30LENGTH}->{0}++;
    }else{
	# The index is 0-based, while first cycle is 1.
	# Hence, no need to subtract 1 from the index
	# position to get the last cycle with Q>30
	# my $min = $ind->at(0);
#	my $min = PDL::Core::at_bad_c($ind,[0]);
#	$self->{Q30LENGTH}->{$min}++;

	# Set all Q>= 30 to 200;
#	$pdl->index($ind) .= 200;
	PDL::Ops::assgn(200, $pdl->index($ind));
	# Run length encode
	my ($len,$val) = (PDL->initialize(), PDL->initialize());
	rle($pdl,$len,$val);
	my $ind2 = PDL->initialize();
	PDL::_which_int($val==200, $ind2);
	$self->{Q30LENGTH}->{at(maximum($len->index($ind2)),0)}++;
    }
}


=head2 addBaseDist()

 Title   : addBaseDist
 Usage   : $qstat->addBaseDist($seq)
 Function: Counts histogram of bases per position
 Example : $qstat->addBaseDist($seq)
 Returns : nothing
 Args    : a sequence string

=cut

sub addBaseDist{
    my $self = shift;
    my $seq = shift;

    # Init a new zero piddle of type byte and length equal to string length
    my $len = length($seq);
    unless(exists $self->{zeroPDL}->{$len}){
	$self->{zeroPDL}->{$len} = PDL->zeroes (byte, $len);;
    }
    my $pdl = $self->{zeroPDL}->{$len};
    # Replace the piddle content with the string
    ${$pdl->get_dataref} = $seq;
    # Update piddle internal references
    $pdl->upd_data;

    # The piddle now holds the ascii values in the string
    # Calculate histogram with ascii value count as columns and cycle number as rows
    # Use $pdl->slice('*1') instead of transpose as it is the same thing for 1D arrays
    # Offset the histogram with A (ASCII 65), and include up to T (ASCII 84)
    # Probably fastest to keep the zero columns til the end.
    # A=65, C=67, G=71, T=84, N=78
    # A=0,  C=2,  G=6,  T=19, N=13
    my $hist = histogram($pdl->slice('*1'), 1, 65, 20);

    if(exists $self->{BASEHIST}){
	$self->{BASEHIST} += $hist;
    }else{
	$self->{BASEHIST} = $hist;
    }
}

=head2 countGC()

 Title   : countGC
 Usage   : $qstat->countGC($seq)
 Function: Count the fraction GC in the sequence
 Example : $qstat->countGC($seq)
 Returns : nothing
 Args    : a sequence string

=cut

sub countGC{
    my $self = shift;
    my $seq = shift;

    # Calculate GC content in seq
    my $called = ($seq =~ tr/ACGT//);
    if($called){ # Bin the values to the int value
	$self->{SEQGC}->[ int(($seq =~ tr/GC//) * 100 / $called) ]++;
    }
}

=head2 countCopies()

 Title   : countCopies
 Usage   : $qstat->countCopies($seq)
 Function: counts the number of copies of each unique sequence
           The number of sequences is limited to MAXSAMPLES
 Example : $qstat->countCopies($seq)
 Returns : nothing
 Args    : a sequence string

=cut

sub countCopies{
    my $self = shift;
    my $seq = shift;

    # Count at most MAXSAMPLES unique sequences
    # only use first 50bp
    # Count all copies of the seqs included
    my $subSeq = substr($seq,0,50);
    if(exists $self->{SEQUENCES}->{$subSeq} ||
       scalar(keys %{$self->{SEQUENCES}}) < $self->{MAXSAMPLES}){
	$self->{SEQUENCES}->{$subSeq}++;
	$self->{SAMPLED_SEQS}++;
    }
}




=head2 checkAdaptor()

 Title   : checkAdaptor
 Usage   : $qstat->checkAdaptor($seq)
 Function: Checks (and records) if the ssequence contains adaptor sequence
 Example : $qstat->checkAdaptor($seq)
 Returns : nothing
 Args    : a sequence string

=cut

sub checkAdaptor{
    my $self = shift;
    my $seq = shift;
    my $len = length($seq);

    # Find the leftmost position that matches the expected adapter

    # Init an array for storing results
    if(! exists $self->{ADAPTER}){
	$self->{ADAPTER} = [(0)x(length($seq))];
    }

    my $adapter = $self->{ADAPTERS}->{TRUSEQ}->[$self->{READ} - 1];
    my $adapter2 = substr($adapter,1); # The A-base is lacking from dimers

    # PDL has overloaded the index function!

    # First check for adapter dimers
    if(substr($seq,0,length($adapter2)) eq $adapter2){
	$self->{ADAPTER}->[0]++;
    # Then check for exact match with A-base repair
    }elsif( (my $m = CORE::index($seq, $adapter))>=0){
	$self->{ADAPTER}->[$m]++;
    # Then do some fuzzy matching
    }else{
	# Find the most 3' match of the first 6bp of the adapter (without the A-base)
	# This will loose some sensitivity, but is 10x faster for
	$m = CORE::index(reverse($seq), reverse(substr($adapter,1,6)));
	if($m>=0){
	    # Find the most 5' match of the adaptor
	    # allowing the adaptor to hang off the 3'end
	    # of the read with a minimum match of 6 bases
	    # And a hamming distance of <= 10%
	    my $matchPos;
	    my $aLen = length($adapter);
	    for(my $i=($len - $m - 6); $i>-1 && $i<$len; $i--){ # Start at the pos found by index
		my $cmpLen = $aLen<$len-$i ? $aLen : $len-$i;
		if(((substr(substr($seq,$i),0,$cmpLen) ^ substr($adapter,0,$cmpLen)) =~ tr/\001-\255//)/($cmpLen) <= 0.1){
		    $matchPos = $i;
		}
		if($i==0){ #Adapter dimer without A-base
		    if(((substr(substr($seq,$i),0,$cmpLen) ^ substr($adapter,1,$cmpLen)) =~ tr/\001-\255//)/($cmpLen) <= 0.1){
			$matchPos = 0;
		    }
		}
	    }
	    if(defined $matchPos){
		$self->{ADAPTER}->[$matchPos]++;
	    }
	}
    }
}

=head2 add

 Title   : add
 Usage   : $stat3 = $stat1->add($stat2, ...)
 Function: Creates a new Qstat object with the summed statistics from stat1 and the
           supplied Qstat objects.
           NOTE: Arbitrary data set at object creation will be lost except for
           PROJECT SAMPLE LANE READ TAG (but only if identical between the added
           objects)
 Returns : New Qstat object
 Args    : one or more Qstat objects

=cut

sub add{
    my $self = shift;
    my $new = $self->new();

    # OFFSET is only used when adding qstrings
    foreach my $key (qw(PROJECT SAMPLE LANE READ TAG)){
	my $val = $self->{$key};
	foreach my $qstat (@_){
	    if(defined $val && "$qstat->{$key}" ne "$val"){
		$val = undef;
	    }
	}
	$new->{$key} = $val;
    }

    foreach my $stat ($self, @_){
	if(exists $stat->{QHIST}){
	    if(exists $new->{QHIST} ){
		$new->{QHIST} += $stat->{QHIST};
	    }else{
		$new->{QHIST} = $stat->{QHIST}->copy();
	    }
	}

	if( exists $stat->{Q30LENGTH} ){
	    my @lengths = keys %{$stat->{Q30LENGTH}};
	    if( exists $new->{Q30LENGTH} ){
		my @keys = keys %{$new->{Q30LENGTH}};
		my %tmp;
		@tmp{@keys,@lengths} = ();
		@lengths = keys %tmp;
	    }else{
		$new->{Q30LENGTH} = {};
	    }
	    foreach my $len (@lengths){
		$new->{Q30LENGTH}->{$len} +=
		  $stat->{Q30LENGTH}->{$len} if(exists $stat->{Q30LENGTH}->{$len});
	    }
	}

	# Base counts
	if(exists $new->{BASEHIST} ){
	    $new->{BASEHIST} += $stat->{BASEHIST};
	}elsif(exists $stat->{BASEHIST}){
	    $new->{BASEHIST} = $stat->{BASEHIST}->copy();
	}

	# GC Content
	if(exists $stat->{SEQGC}){
	    for(my $gc=0; $gc<=100; $gc++){
		if(defined $stat->{SEQGC}->[$gc]){
		    $new->{SEQGC}->[$gc] += $stat->{SEQGC}->[$gc];
		}
	    }
	}

	# Unique sequences
	# It makes no sense adding the sequences as these have been sampled
	# Convert to histogram over number of observations and add these
	my $copyHist = $stat->getCopyHist();
	if(defined $copyHist){
	    if(exists $new->{COPYHIST}){
		$new->{COPYHIST} += $copyHist;
	    }else{
		$new->{COPYHIST} = $copyHist->copy();
	    }
	}

	# Adapters
	if(exists $new->{ADAPTER} && exists $stat->{ADAPTER}){
	    for(my $i=0; $i<@{$stat->{ADAPTER}}; $i++){
		$new->{ADAPTER}->[$i] += $stat->{ADAPTER}->[$i];
	    }
	}elsif(exists $stat->{ADAPTER}){
	    $new->{ADAPTER} = [ @{$stat->{ADAPTER}} ];
	}
    }
    return $new;
}


=head2 metrics

 Title   : metrics
 Usage   : my %metrics = $stat->metrics()
 Function: Returns hash with performance metrics
 Returns : Hash with metric name as key
 Args    : None

=cut

sub metrics{
    my $self = shift;

    my %metrics = (Lane       => $self->{LANE},
		   Read       => $self->{READ},
		   Tag        => defined($self->{TAG}) ? $self->{TAG} : ''
		  );

    if($self->hasData){
	my $hist = $self->{QHIST};
	my $q = pdl(0..40); # The possible Q-values
	my $q30lengths = $self->{Q30LENGTH};

	my $cycles = $hist->getdim(1) || confess("Could not get number of cycles from q-histogram\n");
	my $clusters = $hist->slice("0:40,1")->sum || confess("Could not get number of clusters from q-histogram\n");

	my ($qMean, $qStddev, $q30, $lMean, $lStddev) = (0,0,0,0,0);
	if($clusters > 0){
	    $qMean = sum($hist * $q) / ($clusters * $cycles); # Adjust denominator for number of cycles
	    $qStddev = sqrt( sum($hist * ($q - $qMean)**2) / ($clusters * $cycles));
	    $q30 = sum($hist->slice("30:40,:"))/sum($hist);

	    # Mean Q30-length
	    my $lSum=0;
	    foreach my $len (keys %{$q30lengths}){
		$lSum += $q30lengths->{$len} * $len;
	    }
	    $lMean = $lSum/$clusters;

	    # Stddev of Q30-length
	    $lSum = 0;
	    foreach my $len (keys %{$q30lengths}){
		$lSum += ( $q30lengths->{$len} * ($len-$lMean)**2 );
	    }
	    $lStddev = sqrt($lSum/$clusters);
	}

	%metrics = (%metrics,
		    "QMean"   => sprintf('%.1f', $qMean),
		    "QStdDev" => sprintf('%.1f', $qStddev),
		    "Q30LengthMean"   => sprintf('%.1f', $lMean),
		    "Q30LengthStdDev" => sprintf('%.1f', $lStddev),
		    "Q30Fraction" => sprintf('%.1f', $q30*100),
		    "Cycles" => $cycles,
		   );
    }else{
	# No data in stats set zeroes
	%metrics = (%metrics,
		    "QMean"   => 0,
		    "QStdDev" => 0,
		    "Q30LengthMean"   => 0,
		    "Q30LengthStdDev" => 0,
		    "Q30Fraction" => 0,
		    "Cycles" => 0
		   );
    }

    if(exists $self->{SamplesOnLane}){
	$metrics{"SamplesOnLane"} = $self->{SamplesOnLane};
    }

    return(%metrics);

}

=head2 nCycles

 Title   : nCycles
 Usage   : $stat->nCycles()
 Function: Returns the number of cycles
 Example : $stat->nCycles();
 Returns : Number
 Args    : None

=cut

sub nCycles{
    my $self = shift;
    if(defined $self->{QHIST}){
	return($self->{QHIST}->getdim(1));
    }
    return 0;
}

=head2 hasData

 Title   : hasData
 Usage   : $stat->hasData()
 Function: Returns true if the stat is not empty
 Example : $stat->hasData();
 Returns : Bool
 Args    : None

=cut

sub hasData{
    my $self = shift;
    if(defined $self->{QHIST}){
	return 1;
    }
    return 0;
}

=head2 getHistogram

 Title   : getHhistogram
 Usage   : $stat->getHistogram($tag)
 Function: Returns the PDL histogram of Q-values
 Example : $stat->getHistogram();
 Returns : a PDL matrix, one row per cycle with one column per Q-value
 Args    : None

=cut

sub getHistogram{
    my $self = shift;
    return($self->{QHIST});
}

=head2 getAdapterCounts

 Title   : getAdapterCounts
 Usage   : $stat->getAdapterCounts()
 Function: Returns an array ref with the adapter count per cycle
 Example : $stat->getAdapterCounts();
 Returns : array ref with cycle number as index (0-based)
 Args    : None

=cut

sub getAdapterCounts{
    my $self = shift;
    return $self->{ADAPTER};
}

=head2 getSequenceCount

 Title   : getSequenceCount
 Usage   : $stat->getSequenceCount()
 Function: Returns the total number of sequences
 Example : $stat->getSequenceCount;
 Returns : number
 Args    : None

=cut

sub getSequenceCount{
    my $self = shift;
    return $self->{QHIST}->slice(':,0')->sum();
}

=head2 getOverrepresentedSeqs

 Title   : getOverrepresentedSeqs
 Usage   : $stat->getOverrepresentedSeqs()
 Function: Returns array of overrepresented sequences
 Example : $stat->getOverrepresentedSeqs();
 Returns : Hash with the keys Mean, StdDev and Sequences
           The Sequences are returned as an arrayref of hasherefs
           sorted descending on sequence frequency
           Each hashref has keys Seq and Freq
 Args    : None

=cut

sub getOverrepresentedSeqs{
    my $self = shift;
    confess("getOverrepresentedSeqs is outdatated!\n");
    my @tags = @_;

    my $pdlCount = pdl(values %{$self->{SEQUENCES}});
    my ($mean,$prms,$median,$min,$max,$adev,$rms) = stats($pdlCount);

    my $cut = $mean + (2 * $prms);

    my @overrepresented;
    if($max > $cut){
	foreach my $seq (keys %{$self->{SEQUENCES}}){
	    if($self->{SEQUENCES}->{$seq} > $cut){
		push @overrepresented, {Seq=>$seq,Freq=>$self->{SEQUENCES}->{$seq}/$self->{SAMPLED_SEQS}};
	    }
	}
    }
    return(Mean=>$mean->sclr, StdDev=>$prms->sclr, Sequences=>[sort {$b->{Freq}<=>$a->{Freq}} @overrepresented]);
}

=head2 getSequenceDistribution

 Title   : getSequenceDistribution
 Usage   : $self->getSequenceDistribution()
 Function: Returns the mean and stddev for number of copies per sequence
 Example : $self->getSequenceDistribution();
 Returns : Hash with keys MEAN and STDDEV
 Args    : None

=cut

sub getSequenceDistribution{
    my $self = shift;

    my @dupDist = $self->getDuplicateDistribution();

    my $sum = 0;
    my $n = 0;
    for(my $i=0; $i<@dupDist; $i++){
	$sum += $dupDist[$i]*$i;
	$n += $dupDist[$i];
    }
    my $mean = $sum/$n;
    my $sum2 = 0;
    for(my $i=0; $i<@dupDist; $i++){
	$sum2 += (($i-$mean)**2)*$dupDist[$i];
    }
    my $stdDev = sqrt($sum2/$n-1);
    return(MEAN=>$mean, STDDEV=>$stdDev);
}

=head2 getGCdistribution

 Title   : getGCdistribution
 Usage   : $stat->getGCdistribution()
 Function: Returns the GC distribution of the sequences
 Example : $stat->getGCdistribution();
 Returns : Array with the %GC-bin as index, where each bin represents
           steps from 1-100%. Frequency as values.
 Args    : None

=cut

sub getGCdistribution{
    my $self = shift;

    my $gcHist = pdl(@{$self->{SEQGC}});

    # Recalc counts to frequencies
    if($gcHist->sum() != 0){
	$gcHist = ($gcHist/$gcHist->sum());
    }
    return $gcHist->list();
}



=head2 getCopyHist

 Title   : getCopyHist
 Usage   : $stat->getCopyHist()
 Function: Returns a histogram of copies of unique sequences
 Example : $stat->getCopyHist();
 Returns : PDL histogram with counts as values
 Args    : None

=cut

sub getCopyHist{
    my $self = shift;

    if(! exists $self->{COPYHIST} && exists $self->{SEQUENCES}){
	$self->{COPYHIST} = histogram(pdl(values %{$self->{SEQUENCES}}), 1,0,101);
    }

    if(exists $self->{COPYHIST}){
	return($self->{COPYHIST});
    }

    return undef;

    # Recalc counts to frequencies
#    $dupHist = ($dupHist/$self->{SAMPLED_SEQS});
#    return $dupHist->list();
}

=head2 getQ30LengthHist

 Title   : getQ30LengthHist
 Usage   : $stat->getQ30LengthHist()
 Function: Returns a histogram of longest contiguous stretch with Q>=30
 Example : $stat->getQ30LengthHist();
 Returns : Arrayref with length as index and count as value
 Args    : None

=cut

sub getQ30LengthHist{
    my $self = shift;

    if(exists $self->{Q30LENGTH}){
	my $pdl = pdl(values %{$self->{Q30LENGTH}});
	my $n = $pdl->sum();
	my @ary;
	foreach my $len (keys %{$self->{Q30LENGTH}}){
	    $ary[$len] = $self->{Q30LENGTH}->{$len}/$n;
	}
	return \@ary;
    }
    return undef;
}


=head2 getBaseComposition

 Title   : getBaseComposition
 Usage   : $stat->getBaseComposition()
 Function: Returns a hash with base as key and arrayrefs with
           base counts for each cycle as value. The arrays are
           0-based.
 Example : $stat->getBaseComposition();
 Returns : number
 Args    : None

=cut

sub getBaseComposition{
    my $self = shift;

    my $hist = $self->{BASEHIST};
    my %bases;
    foreach my $base (qw(A C G T N)){
	my $n = ord($base) - 65;
	$bases{$base} = [ $hist->slice("$n,:")->transpose->list() ];
    }
    return(%bases);
}

=head2 suffix

 Title   : suffix
 Usage   : $self->suffix($value);
 Function: Returns the value as a string with one decimal and a suitable suffix
 Example :
 Returns : string
 Args    : numeric value

=cut

sub suffix{
    my $self = shift;
    my $val = shift;
    if($val>1e9){
	return( sprintf('%.1fG', $val/1e9) );
    }elsif($val>1e6){
	return( sprintf('%.1fM', $val/1e6) );
    }elsif($val>1e3){
	return( sprintf('%.1fk', $val/1e3) );
    }elsif($val>1){
	return( sprintf('%.1f', $val) );
    }
    return($val);
}

=head2 copy

 Title   : copy
 Usage   : my $q2 = $qstat->copy
 Function: Makes a deep copy of the qstat object
 Example :
 Returns : Qstat object
 Args    : none

=cut

sub copy{
    my $self = shift;
    my $new = $self->new();

    # Copy all scalars
    foreach my $key (keys %{$self}){
	unless(ref $self->{$key}){
	    $new->{$key} = $self->{$key};
	}
    }

    if(exists $self->{QHIST}){
	$new->{QHIST} = $self->{QHIST}->copy;
    }
    if(exists $self->{Q30LENGTH}){
	$new->{Q30LENGTH} = { %{$self->{Q30LENGTH}} };
    }
    if(exists $self->{BASEHIST}){
	$new->{BASEHIST} = $self->{BASEHIST}->copy;
    }
    if(exists $self->{SEQGC}){
	$new->{SEQGC} = [ @{$self->{SEQGC}} ];
    }
    if(exists $self->{COPYHIST}){
	$new->{COPYHIST} = $self->{COPYHIST}->copy;
    }
    if(exists $self->{SEQUENCES}){
	$new->{SEQUENCES} = { %{$self->{SEQUENCES}} };
    }
    if(exists $self->{SAMPLED_SEQS}){
	$new->{SAMPLED_SEQS} = $self->{SAMPLED_SEQS};
    }
    if(exists $self->{ADAPTER}){
	$new->{ADAPTER} = [ @{$self->{ADAPTER}} ];
    }
    return $new;
}


=head2 saveData

 Title   : saveData
 Usage   : $qstat->saveData($filename) || die "Failed to save Qstat to $filename\n";
 Function: Writes the content of the object into the named file
 Example :
 Returns : true on success
 Args    : Path of the file to write

=cut

sub saveData{
    my $self = shift;
    my $filename = shift;

    my $pdlCommas = $PDL::use_commas;
    $PDL::use_commas = 1;

    # Create a Zip-archive for storing the data
    my $zip = Archive::Zip->new();

    # Write all scalars, use name as filename, value as content
    $zip->addDirectory('SCALARS/');
    foreach my $key (keys %{$self}){
	unless(ref $self->{$key}){
	    my $item = $zip->addString($self->{$key},  'SCALARS/'.$key);
	    $item->desiredCompressionMethod( COMPRESSION_DEFLATED );
	    $item->desiredCompressionLevel( 1 );
	}
    }

    # Q-Histogram
    if(exists $self->{QHIST}){
	my $item = $zip->addString(sprintf('pdl(%s)',$self->{QHIST}),  "QHIST");
	$item->desiredCompressionMethod( COMPRESSION_DEFLATED );
	$item->desiredCompressionLevel( 1 );
    }
    # Q30 length
    if(exists $self->{Q30LENGTH}){
	my $item = $zip->addString(Dumper($self->{Q30LENGTH}),  "Q30LENGTH");
	$item->desiredCompressionMethod( COMPRESSION_DEFLATED );
	$item->desiredCompressionLevel( 1 );
    }
    # BaseHistogram
    if(exists $self->{BASEHIST}){
	my $item = $zip->addString(sprintf('pdl(%s)',$self->{BASEHIST}),  "BASEHIST");
	$item->desiredCompressionMethod( COMPRESSION_DEFLATED );
	$item->desiredCompressionLevel( 1 );
    }
    # SeqGC
    if(exists $self->{SEQGC}){
	my $item = $zip->addString(Dumper($self->{SEQGC}),  "SEQGC");
	$item->desiredCompressionMethod( COMPRESSION_DEFLATED );
	$item->desiredCompressionLevel( 1 );
    }
    # Sequence copy distribution
    if(exists $self->{COPYHIST} || exists $self->{SEQUENCES}){
	my $copyHist = $self->getCopyHist();
	if(defined $copyHist){
	    my $item = $zip->addString(sprintf('pdl(%s)',$self->{COPYHIST}),  "COPYHIST");
#	my $item = $zip->addString(Dumper($self->{SEQUENCES}),  "SEQUENCES");
	    $item->desiredCompressionMethod( COMPRESSION_DEFLATED );
	    $item->desiredCompressionLevel( 1 );
	}
    }
	# Sampled seqs
    if(exists $self->{SAMPLED_SEQS}){
	my $item = $zip->addString($self->{SAMPLED_SEQS},  "SAMPLED_SEQS");
	$item->desiredCompressionMethod( COMPRESSION_DEFLATED );
	$item->desiredCompressionLevel( 1 );
    }
    # Adapter
    if(exists $self->{ADAPTER}){
	my $item = $zip->addString(Dumper($self->{ADAPTER}),  "ADAPTER");
	$item->desiredCompressionMethod( COMPRESSION_DEFLATED );
	$item->desiredCompressionLevel( 1 );
    }

    unless(-e dirname($filename)){
	mkpath(dirname($filename),2770);
    }

    unless ( $zip->writeToFileNamed($filename) == AZ_OK ) {
	confess "Failed to write Qstat data to $filename: $!\n";
    }

    $PDL::use_commas = $pdlCommas;
    return 1;
}

=pod

=head2 loadData

 Title   : loadData
 Usage   : $qstat->loadData($filename) || die "Failed to load Qstat from $filename\n";
 Function: Populates the file with data from from file
 Example :
 Returns : true on success
 Args    : Path of the file to read

=cut

sub loadData{
    my $self = shift;
    my $filename = shift;
    print STDERR "loading statdata from $filename\n" if($self->{DEBUG});
    # Open zip file as object
    my $zip = Archive::Zip->new();
    unless( $zip->read( $filename ) == AZ_OK ){
	confess "Failed to read Qstat data from $filename: $!\n";
    }

    # Read all scalars, varname as filename, value as content
    foreach my $item ($zip->membersMatching('SCALARS/.+')){
	my $name = $item->fileName();
	print STDERR "$name\n" if($self->{DEBUG});
	$name =~ s(SCALARS/)();
	my $data = $item->contents();
	if(Archive::Zip::computeCRC32($data) == $item->crc32){
	    $self->{$name} = $item->contents();
	}else{
	    die "The archive $filename seems corrupted. Failed to verify crc32 on $name\n";
	}
    }

    # Get the statistics
    if(my $item = $zip->memberNamed("QHIST")){
	print STDERR $item->fileName(), "\n" if($self->{DEBUG});
	my $data = $item->contents();
	my $str = '$self->{QHIST} = ' . $data;
	if(Archive::Zip::computeCRC32($data) == $item->crc32){
	    eval $str; confess $@ if $@;
	}else{
	    die "The archive $filename seems corrupted. Failed to verify crc32 on QHIST\n";
	}
    }
    if(my $item = $zip->memberNamed("Q30LENGTH")){
	print STDERR $item->fileName(), "\n" if($self->{DEBUG});
	my $data = $item->contents();
	if(Archive::Zip::computeCRC32($data) == $item->crc32){
	    my $VAR1;
	    eval $data; confess $@ if $@;
	    $self->{Q30LENGTH}= $VAR1;
	}else{
	    die "The archive $filename seems corrupted. Failed to verify crc32 on Q30LENGTH\n";
	}

    }
    if(my $item = $zip->memberNamed("BASEHIST")){
	print STDERR $item->fileName(), "\n" if($self->{DEBUG});
	my $data = $item->contents();
	my $str = '$self->{BASEHIST} = ' . $data;
	eval $str; confess $@ if $@;
    }
    if(my $item = $zip->memberNamed("SEQGC")){
	print STDERR $item->fileName(), "\n" if($self->{DEBUG});
	my $data = $item->contents();
	if(Archive::Zip::computeCRC32($data) == $item->crc32){
	    my $VAR1;
	    eval $data; confess $@ if $@;
	    $self->{SEQGC} = $VAR1;
	}else{
	    die "The archive $filename seems corrupted. Failed to verify crc32 on SEQGC\n";
	}
    }
    if(my $item = $zip->memberNamed("SEQUENCES")){
	print STDERR $item->fileName(), "\n" if($self->{DEBUG});
	my $data = $item->contents();
	if(Archive::Zip::computeCRC32($data) == $item->crc32){
	    my $VAR1;
	    eval $data; confess $@ if $@;
	    $self->{SEQUENCES}= $VAR1;
	}else{
	    die "The archive $filename seems corrupted. Failed to verify crc32 on SEQUENCES\n";
	}
    }
    if(my $item = $zip->memberNamed("COPYHIST")){
	print STDERR $item->fileName(), "\n" if($self->{DEBUG});
	my $data = $item->contents();
	if(Archive::Zip::computeCRC32($data) == $item->crc32){
	    my $str = '$self->{COPYHIST} = ' . $data;
	    eval $str; confess $@ if $@;
	}else{
	    die "The archive $filename seems corrupted. Failed to verify crc32 on COPYHIST\n";
	}
    }
    if(my $item = $zip->memberNamed("SAMPLED_SEQS")){
	print STDERR $item->fileName(), "\n" if($self->{DEBUG});
	my $data = $item->contents();
	if(Archive::Zip::computeCRC32($data) == $item->crc32){
	    $self->{SAMPLED_SEQS}= $data;
	}else{
	    die "The archive $filename seems corrupted. Failed to verify crc32 on SAMPLED_SEQS\n";
	}
    }
    if(my $item = $zip->memberNamed("ADAPTER")){
	print STDERR $item->fileName(), "\n" if($self->{DEBUG});
	my $data = $item->contents();
	if(Archive::Zip::computeCRC32($data) == $item->crc32){
	    my $VAR1;
	    eval $data; confess $@ if $@;
	    $self->{ADAPTER}= $VAR1;
	}else{
	    die "The archive $filename seems corrupted. Failed to verify crc32 on ADAPTER\n";
	}
    }
    return 1;
}

# 500 cycles is too much for dumping the QHIST matrix with standard PDL
# Override the original string function


package PDL::Core;

my $max_elem = 10000000;  # set your max here

{
no warnings 'redefine';
sub PDL::Core::string {
   my ( $self, $format ) = @_;
   if ( $PDL::_STRINGIZING ) {
      return "ALREADY_STRINGIZING_NO_LOOPS";
   }
   local $PDL::_STRINGIZING = 1;
   my $ndims = $self->getndims;
   if ( $self->nelem > $max_elem ) {
      return "TOO LONG TO PRINT";
   }
   if ( $ndims == 0 ) {
      if ( $self->badflag() and $self->isbad() ) {
         return "BAD";
      }
      else {
         my @x = $self->at();
         return ( $format ? sprintf( $format, $x[ 0 ] ) : "$x[0]" );
      }
   }
   return "Null"  if $self->isnull;
   return "Empty" if $self->isempty;    # Empty piddle

   local $PDL::Core::sep  = $PDL::use_commas ? "," : " ";
   local $PDL::Core::sep2 = $PDL::use_commas ? "," : "";
   if ( $ndims == 1 ) {
      return PDL::Core::str1D( $self, $format );
   }
   else {
      return PDL::Core::strND( $self, $format, 0 );
   }
}
}

1;
