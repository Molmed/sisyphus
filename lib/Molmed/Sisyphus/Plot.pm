package Molmed::Sisyphus::Plot;

use strict;
use Molmed::Sisyphus::Libpath;
use Carp;
use PDL;
use File::Basename;
use FindBin;                # Find the script location

use Molmed::Sisyphus::Common qw(mkpath);

=pod

=head1 NAME

Molmed::Sisyphus::Plot - Plot quality metrics

=head1 SYNOPSIS

use Molmed::Sisyphus::Plot;

my $plotter = Molmed::Sisyphus::Plot->new(DEBUG=>1);
$plotter->plotQvals($stats,$outfile);

=head1 DESCRIPTION

This module is used for plotting various metrics for sequencing results

=head1 CONSTRUCTORS

=head2 new()

=over 4

=item DEBUG

Print debug information.

=back

=cut

sub new{
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = {@_};

    bless ($self, $class);
    return $self;
}

=pod

=head1 FUNCTIONS

=head2 plotQvals()

 Title   : plotQvals
 Usage   : $plotter->plotQvals($stats,$outfile,$title)
 Function: Creates a 3d plot with the distribution of Q-values over cycles
 Example : my($plot, $thumb) = $plotter->plotQvals($stats,$outfile,$title)
 Returns : The name of the plot and thumbnail files
 Args    : A Molmed::Sisyphus::Qstat object to plot,
           a string with the base name of the plot file to generate
           (a .png extension will be added)
           The plot title

=cut

sub plotQval{
    my $self = shift;
    my $stat = shift;
    my $plotName = shift;
    my $plotTitle = shift;
    my $datName = "$plotName.dat";
    my $scriptName = "$plotName.gpl";
    my $thumbName = "${plotName}_thumb.png";
    $plotName = "$plotName.png";

    my $dirName = dirname($plotName);
    unless(-e $dirName){
	mkpath($dirName, 2770);
    }

    # Handle empty stat data
    unless($stat->hasData()){
	return('NA','NA');
    }

    open(my $datFh, ">", $datName) or die "Failed to create $datName: $!\n";
    print $datFh "#Cycle\tQ\tFraction\n";
    my $hist = $stat->getHistogram();
    unless(defined $hist){
	confess "Got undefined histogram!\n";
    }

    my $pfClusters = $hist->slice("0:40,1")->sum;
    my $cycles = $hist->getdim(1);

    for(my $i=0; $i<$cycles; $i++){
        my $r = $hist->slice(",$i");
        for(my $j=0; $j<41; $j++){
            print $datFh join("\t", $i+1, $j, $pfClusters>0 ? $hist->at($j,$i)/$pfClusters : 0), "\n";
        }
        print $datFh "\n"; # gnuplot pm3d requires blank lines between "groups"
    }
    close($datFh);

    open(my $gpl, ">", $scriptName) or die "Failed to create $scriptName: $!\n";
    print $gpl qq(
set terminal png font Vera 9 size 800,600
set output "$plotName"
set title "$plotTitle"
set xrange [1:$cycles]
set xlabel "Cycle"
set zlabel "Freq"
set ylabel "Q"
unset key
splot "$datName" with impulses

);
    close($gpl);
    $ENV{GDFONTPATH} = "$FindBin::Bin/Fonts";
    # Make the plot
    $self->sysWrap(0, "gnuplot", "$scriptName") == 0 or confess "Gnuplot failed on $scriptName: $!\n";
    # And a thumbnail
    $self->sysWrap(0, "convert", "-strip", "-quality", "95", "PNG8:$plotName", "-resize", "120x80", $thumbName) == 0 or confess "Convert to thumb failed on $plotName: $!\n";
    #compress the script and data
    $self->sysWrap(0, 'bzip2', $scriptName)==0 or die "Failed to compress $scriptName";
    $self->sysWrap(0, 'bzip2', $datName)==0 or die "Failed to compress $scriptName";
    return($plotName,$thumbName);
}

=pod

=head2 plotAdapters()

 Title   : plotAdapters
 Usage   : $plotter->plotAdapters($stats,$outfile,$title)
 Function: Creates a plot with the cumulative adapter sequences per cycle
 Example : my($plot, $thumb) = $plotter->plotAdapters($stats,$outfile,$title)
 Returns : The name of the plot and thumbnail files
 Args    : A Molmed::Sisyphus::Qstat object to plot,
           a string with the base name of the plot file to generate
           (a .png extension will be added)
           The plot title

=cut

sub plotAdapters{
    my $self = shift;
    my $stat = shift;
    my $plotName = shift;
    my $plotTitle = shift;
    my $datName = "$plotName.dat";
    my $scriptName = "$plotName.gpl";
    my $thumbName = "${plotName}_thumb.png";
    $plotName = "$plotName.png";

    # Handle empty stat data
    unless($stat->hasData()){
	return('NA','NA');
    }

    my $dirName = dirname($plotName);
    unless(-e $dirName){
	mkpath($dirName, 2770);
    }

    open(my $datFh, ">", $datName) or die "Failed to create $datName: $!\n";
    print $datFh "#Cycle\tQ\tAdapterFraction\n";
    my $counts = $stat->getAdapterCounts();
    unless(defined $counts){
	confess "Got undefined counts!\n";
    }
    my $n = $stat->getSequenceCount();


    my $cum = 0;
    for(my $i=0; $i<@{$counts}; $i++){
	$cum += $counts->[$i];
	print $datFh $i+1 . "\t";
	printf $datFh ('%.2f', $cum/$n*100);
	print $datFh "\n";
    }
    close($datFh);

    my $cycles = $stat->nCycles();
    open(my $gpl, ">", $scriptName) or die "Failed to create $scriptName: $!\n";
    print $gpl qq(
set terminal png font Vera 9 size 800,600
set output "$plotName"
set title "$plotTitle"

set xrange [0:$cycles]
set yrange [0:100]
set xlabel "Cycle"
set ylabel "Cumulative Adapter Sequence"

unset key
set xtics nomirror
set ytics 10 nomirror
set grid ytics lt 0
set border 3

set style data histogram
set style histogram cluster gap 1
set style fill solid border
set boxwidth 1

plot "$datName" using 2

);
    close($gpl);
    $ENV{GDFONTPATH} = "$FindBin::Bin/Fonts";
    # Make the plot
    $self->sysWrap(0, "gnuplot", "$scriptName") == 0 or confess "Gnuplot failed on $scriptName: $!\n";
    # And a thumbnail
    $self->sysWrap(0, "convert", "-strip", "-quality", "95", "PNG8:$plotName", "-resize", "120x80", $thumbName) == 0 or confess "Convert to thumb failed on $plotName: $!\n";
    #compress the script and data
    $self->sysWrap(0, 'bzip2', $scriptName)==0 or die "Failed to compress $scriptName";
    $self->sysWrap(0, 'bzip2', $datName)==0 or die "Failed to compress $scriptName";
    return($plotName,$thumbName);
}

=pod

=head2 plotBaseComposition()

 Title   : plotBaseComposition
 Usage   : $plotter->plotBaseComposition($stats,$outfile,$title)
 Function: Creates a plot with the base composition(A,C,G,T,N+GC) per cycle
 Example : my($plot, $thumb) = $plotter->plotBaseComposition($stats,$outfile,$title)
 Returns : The name of the plot and thumbnail files
 Args    : A Molmed::Sisyphus::Qstat object to plot,
           a string with the base name of the plot file to generate
           (a .png extension will be added)
           The title of the plot

=cut

sub plotBaseComposition{
    my $self = shift;
    my $stat = shift;
    my $plotName = shift;
    my $plotTitle = shift;
    my $datName = "$plotName.dat";
    my $scriptName = "$plotName.gpl";
    my $thumbName = "${plotName}_thumb.png";
    $plotName = "$plotName.png";

    # Handle empty stat data
    unless($stat->hasData()){
	return('NA','NA');
    }

    my $dirName = dirname($plotName);
    unless(-e $dirName){
	mkpath($dirName, 2770);
    }

    open(my $datFh, ">", $datName) or die "Failed to create $datName: $!\n";
    print $datFh "#Cycle\t", join("\t", qw(A C G T N)), "\n";
    my %counts = $stat->getBaseComposition();
    unless(%counts){
	confess "Got undefined counts!\n";
    }
    # Assume all seqs are of equal length
    my $n = $stat->getSequenceCount();
    for(my $i=0; $i<@{$counts{A}}; $i++){
	print $datFh $i+1 . "\t";
	foreach my $base (qw(A C G T N)) {
	    print $datFh sprintf('%.2f', $counts{$base}->[$i]/$n*100), "\t";
	}
	print $datFh "\n";
    }
    close($datFh);

    my $cycles = $stat->nCycles();
    open(my $gpl, ">", $scriptName) or die "Failed to create $scriptName: $!\n";
    print $gpl qq(
set terminal png font Vera 9 size 800,600
set output "$plotName"
datafile="$datName"
set title "$plotTitle"
set xrange [1:$cycles]
set yrange [0:100]

set xlabel "Cycle"
set ylabel "\%Base"
set xtics nomirror
set ytics 10 nomirror
set grid ytics lt 0
set border 3

set style line 1 lt 20 lw 2
set style line 2 lt 2 lw 2
set style line 3 lt 1 lw 2
set style line 4 lt 8 lw 2
set style line 5 lt 17 lw 2
set style line 6 lt 4 lw 2
set style line 7 lt 7 lw 2
set style data lines

plot datafile using 1:2 title 'A' ls 1, datafile using 1:5 title 'T' ls 2, datafile using 1:4 title 'G' ls 3, datafile using 1:3 title 'C' ls 4, datafile using 1:6 title 'N' ls 5, datafile using 1:(\$3+\$4) title 'G+C' ls 6, datafile using 1:(\$2+\$5) title 'A+T' ls 7

);
    close($gpl);
    $ENV{GDFONTPATH} = "$FindBin::Bin/Fonts";
    # Make the plot
    $self->sysWrap(0, "gnuplot", "$scriptName") == 0 or confess "Gnuplot failed on $scriptName: $!\n";
    # And a thumbnail
    $self->sysWrap(0, "convert", "-strip", "-quality", "95", "PNG8:$plotName", "-resize", "120x80", $thumbName) == 0 or confess "Convert to thumb failed on $plotName: $!\n";
    #compress the script and data
    $self->sysWrap(0, 'bzip2', $scriptName)==0 or die "Failed to compress $scriptName";
    $self->sysWrap(0, 'bzip2', $datName)==0 or die "Failed to compress $scriptName";
    return($plotName,$thumbName);
}


=pod

=head2 plotGCdistribution()

 Title   : plotGCdistribution
 Usage   : $plotter->plotGCdistribution($stats,$outfile,$title)
 Function: Creates a plot with the distribution of GC content in sequences
 Example : my($plot, $thumb) = $plotter->plotGCdistribution($stats,$outfile,$title)
 Returns : The name of the plot and thumbnail files
 Args    : A Molmed::Sisyphus::Qstat object to plot,
           a string with the base name of the plot file to generate
           (a .png extension will be added)
           The plot title

=cut

sub plotGCdistribution{
    my $self = shift;
    my $stat = shift;
    my $plotName = shift;
    my $plotTitle = shift;
    my $datName = "$plotName.dat";
    my $scriptName = "$plotName.gpl";
    my $thumbName = "${plotName}_thumb.png";
    $plotName = "$plotName.png";

    # Handle empty stat data
    unless($stat->hasData()){
	return('NA','NA');
    }

    my $dirName = dirname($plotName);
    unless(-e $dirName){
	mkpath($dirName, 2770);
    }

    open(my $datFh, ">", $datName) or die "Failed to create $datName: $!\n";
    print $datFh "#GC\tFrequency\n";
    my @dist = $stat->getGCdistribution();
    unless(@dist){
	confess "Got empty GC distribution!\n";
    }

    for(my $i=0; $i<@dist; $i++){
	print $datFh "$i\t" . sprintf('%.2f', $dist[$i]) . "\n";
    }
    close($datFh);

    open(my $gpl, ">", $scriptName) or die "Failed to create $scriptName: $!\n";
    print $gpl qq(
set terminal png font Vera 9 size 800,600
set output "$plotName"
set title "$plotTitle"

set xrange [0:100]
set yrange [*:*]
set xlabel "\%GC in sequence"
set ylabel "Frequency"

unset key
set xtics nomirror out
set ytics nomirror
set grid ytics lt 0
set border 3

set style data histogram
set style histogram cluster gap 1
set style fill solid border
set boxwidth 1

plot "$datName" using 2

);
    close($gpl);
    $ENV{GDFONTPATH} = "$FindBin::Bin/Fonts";
    # Make the plot
    $self->sysWrap(0, "gnuplot", "$scriptName") == 0 or confess "Gnuplot failed on $scriptName: $!\n";
    # And a thumbnail
    $self->sysWrap(0, "convert", "-strip", "-quality", "95", "PNG8:$plotName", "-resize", "120x80", $thumbName) == 0 or confess "Convert to thumb failed on $plotName: $!\n";
    #compress the script and data
    $self->sysWrap(0, 'bzip2', $scriptName)==0 or die "Failed to compress $scriptName";
    $self->sysWrap(0, 'bzip2', $datName)==0 or die "Failed to compress $scriptName";
    return($plotName,$thumbName);
}

=pod

=head2 plotDuplications()

 Title   : plotDuplications
 Usage   : $plotter->plotDuplications($stats,$outfile,$title)
 Function: Creates a plot with the distribution of duplicated sequences
 Example : my($plot, $thumb) = $plotter->plotDuplications($stats,$outfile,$title)
 Returns : The name of the plot and thumbnail files
 Args    : A Molmed::Sisyphus::Qstat object to plot,
           a string with the base name of the plot file to generate
           (a .png extension will be added)
           The plot title

=cut

sub plotDuplications{
    my $self = shift;
    my $stat = shift;
    my $plotName = shift;
    my $plotTitle = shift;
    my $datName = "$plotName.dat";
    my $scriptName = "$plotName.gpl";
    my $thumbName = "${plotName}_thumb.png";
    $plotName = "$plotName.png";

    # Handle empty stat data
    unless($stat->hasData()){
	return('NA','NA');
    }

    my $dirName = dirname($plotName);
    unless(-e $dirName){
	mkpath($dirName, 2770);
    }

    open(my $datFh, ">", $datName) or die "Failed to create $datName: $!\n";
    my $hist = $stat->getCopyHist();
    unless(defined($hist)){
	confess "Got empty Duplicate distribution!\n";
    }
    my @dist = $hist->list();
    my $n = $hist->sum();
    print $datFh "#Number of unique sequences=$n\n";
    print $datFh "#Copies\tFrequency\n";

    for(my $i=0; $i<@dist; $i++){
	print $datFh "$i\t" . sprintf('%.3f', $dist[$i]/$n) . "\n";
#	print $datFh "$i\t" . $dist[$i]/$n . "\n";
    }
    close($datFh);

    open(my $gpl, ">", $scriptName) or die "Failed to create $scriptName: $!\n";
    print $gpl qq(
set terminal png font Vera 9 size 800,600
set output "$plotName"
set title "$plotTitle"

set xrange [0:100]
set yrange [*:*]
set xlabel "Number of copies"
set ylabel "Fraction of unique sequences"

unset key
set xtics nomirror out
set ytics nomirror
set grid ytics lt 0
set border 3

set style data histogram
set style histogram cluster gap 1
set style fill solid border
set boxwidth 1

plot "$datName" using 2

);
    close($gpl);
    $ENV{GDFONTPATH} = "$FindBin::Bin/Fonts";
    # Make the plot
    $self->sysWrap(0, "gnuplot", "$scriptName") == 0 or confess "Gnuplot failed on $scriptName: $!\n";
    # And a thumbnail
    $self->sysWrap(0, "convert", "-strip", "-quality", "95", "PNG8:$plotName", "-resize", "120x80", $thumbName) == 0 or confess "Convert to thumb failed on $plotName: $!\n";
    #compress the script and data
    $self->sysWrap(0, 'bzip2', $scriptName)==0 or die "Failed to compress $scriptName";
    $self->sysWrap(0, 'bzip2', $datName)==0 or die "Failed to compress $scriptName";
    return($plotName,$thumbName);
}

=pod

=head2 plotQ30Length()

 Title   : plotQ30Length
 Usage   : $plotter->plotQ30Length($stats,$outfile,$title)
 Function: Creates a plot with the distribution of the length of contiguous
           stretches of Q30 in reads
 Example : my($plot, $thumb) = $plotter->plotQ30Length($stats,$outfile,$title)
 Returns : The name of the plot and thumbnail files
 Args    : A Molmed::Sisyphus::Qstat object to plot,
           a string with the base name of the plot file to generate
           (a .png extension will be added)
           The plot title

=cut

sub plotQ30Length{
    my $self = shift;
    my $stat = shift;
    my $plotName = shift;
    my $plotTitle = shift;
    my $datName = "$plotName.dat";
    my $scriptName = "$plotName.gpl";
    my $thumbName = "${plotName}_thumb.png";
    $plotName = "$plotName.png";

    # Handle empty stat data
    unless($stat->hasData()){
	return('NA','NA');
    }

    my $dirName = dirname($plotName);
    unless(-e $dirName){
	mkpath($dirName, 2770);
    }

    open(my $datFh, ">", $datName) or die "Failed to create $datName: $!\n";
    print $datFh "#Length\tFrequency\n";
    my $hist = $stat->getQ30LengthHist();
    unless(defined($hist)){
	confess "Got empty q30 length distribution!\n";
    }
    for(my $i=0; $i<@{$hist}; $i++){
	print $datFh "$i\t" . (defined($hist->[$i]) ? $hist->[$i] : 0) . "\n";
    }
    close($datFh);

    open(my $gpl, ">", $scriptName) or die "Failed to create $scriptName: $!\n";
    print $gpl qq(
set terminal png font Vera 9 size 800,600
set output "$plotName"
set title "$plotTitle"

set xrange [0:*]
set yrange [*:*]
set xlabel "Contiguous length Q>=30"
set ylabel "Fraction of sequences"

unset key
set xtics nomirror out
set ytics nomirror
set grid ytics lt 0
set border 3

set style data histogram
set style histogram cluster gap 1
set style fill solid border
set boxwidth 1

plot "$datName" using 2

);
    close($gpl);
    $ENV{GDFONTPATH} = "$FindBin::Bin/Fonts";
    # Make the plot
    $self->sysWrap(0, "gnuplot", "$scriptName") == 0 or confess "Gnuplot failed on $scriptName: $!\n";
    # And a thumbnail
    $self->sysWrap(0, "convert", "-strip", "-quality", "95", "PNG8:$plotName", "-resize", "120x80", $thumbName) == 0 or confess "Convert to thumb failed on $plotName: $!\n";
    #compress the script and data
    $self->sysWrap(0, 'bzip2', $scriptName)==0 or die "Failed to compress $scriptName";
    $self->sysWrap(0, 'bzip2', $datName)==0 or die "Failed to compress $scriptName";
    return($plotName,$thumbName);
}

=pod

=head2 plotQ30Length()

 Title   : plotQPerBase
 Usage   : $plotter->plotQPerBase($stats,$outfile,$title)
 Function: Creates a plot with mean Q value for each base at 
           every cycle .
 Example : my($plot, $thumb) = $plotter->plotQPerBase($stats,$outfile,$title)
 Returns : The name of the plot and thumbnail files
 Args    : A Molmed::Sisyphus::Qstat object to plot,
           a string with the base name of the plot file to generate
           (a .png extension will be added)
           The plot title

=cut

sub plotQPerBase{
    my $self = shift;
    my $stat = shift;
    my $plotName = shift;
    my $plotTitle = shift;
    my $datName = "$plotName.dat";
    my $scriptName = "$plotName.gpl";
    my $thumbName = "${plotName}_thumb.png";
    $plotName = "$plotName.png";

    # Handle empty stat data
    unless($stat->hasData()){
	return('NA','NA');
    }

    my $dirName = dirname($plotName);
    unless(-e $dirName){
	mkpath($dirName, 2770);
    }

    open(my $datFh, ">", $datName) or die "Failed to create $datName: $!\n";
    print $datFh "#Cycle\tMean A\tSTDV A\tMean C\tSTDV C\tMean G\tSTDV G\tMean T\tSTDV T\n";
    my $xy = $stat->getQValuePerBaseXY();
    
    unless(defined($xy)){
	confess "Got empty Q per base list!\n";
    }
    for(my $i=0; $i<@{$xy}; $i++){
	print $datFh (defined($xy->[$i]) ? $xy->[$i] : 0) . "\n";
    }
    close($datFh);

    open(my $gpl, ">", $scriptName) or die "Failed to create $scriptName: $!\n";
    print $gpl qq(
set terminal png font Vera 9 size 800,600
set output "$plotName"
datafile="$datName"
set title "$plotTitle"

set yrange [0:45]

set xlabel "Cycle number"
set ylabel "Mean Q value"
set xtics nomirror
set ytics 10 nomirror
set grid ytics lt 0
set border 3

set style line 1 lt 20 lw 2
set style line 2 lt 2 lw 2
set style line 3 lt 1 lw 2
set style line 4 lt 8 lw 2
set style data lines
set key bottom

plot datafile using 1:2:3 title 'A' w yerrorbars ls 1, datafile using 1:4:5 title 'C' w yerrorbars  ls 2, datafile using 1:6:7 title 'G' w yerrorbars  ls 3, datafile using 1:8:9 title 'A' w yerrorbars  ls 4

);
    close($gpl);
    $ENV{GDFONTPATH} = "$FindBin::Bin/Fonts";
    # Make the plot
    $self->sysWrap(0, "gnuplot", "$scriptName") == 0 or confess "Gnuplot failed on $scriptName: $!\n";
    # And a thumbnail
    $self->sysWrap(0, "convert", "-strip", "-quality", "95", "PNG8:$plotName", "-resize", "120x80", $thumbName) == 0 or confess "Convert to thumb failed on $plotName: $!\n";
    #compress the script and data
    $self->sysWrap(0, 'bzip2', $scriptName)==0 or die "Failed to compress $scriptName";
    $self->sysWrap(0, 'bzip2', $datName)==0 or die "Failed to compress $scriptName";
    return($plotName,$thumbName);
}


sub sysWrap{
    my $self = shift;
    my $try = shift;
    my $retval = system(@_);
    if($retval && $try < 5){
	$try++;
	sleep 60; # Let the filesystem catch up
	print STDERR "Trying to re-run " . join(' ', @_) . "(Try $try)\n";
	return ($self->sysWrap($try, @_));
    }
    return $retval;
}


1
