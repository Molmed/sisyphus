#!/usr/bin/perl -w

use FindBin;                # Find the script location
use lib "$FindBin::Bin/lib";# Add the script libdir to libs

use strict;
use XML::Simple;
use Carp;

my $xml = shift;
my $data = XMLin($xml, ForceArray=>['Tag', 'Read', 'Lane', 'Sample']) || confess "Failed to read $xml\n";

my %lanes;

foreach my $sample (@{$data->{SampleMetrics}->{Sample}}){
    foreach my $tag (@{$sample->{Tag}}){
	foreach my $lane (@{$tag->{Lane}}){
	    foreach my $read (@{$lane->{Read}}){
		next unless($read->{Id} == 1);
#		print join("\t", $lane->{Id}, $tag->{Id}, $read->{PctLane}), "\n";
		push @{$lanes{$lane->{Id}}}, [$sample, $read->{PctLane}];
	    }
	}
    }
}
foreach my $lane (sort {$a<=>$b} keys %lanes){
  my @vals = @{$lanes{$lane}};
  foreach my $v (sort {$a->[1]<=>$b->[1]} @vals){
    printf("$lane\t$v->[0]->{Id}\t".'%.2f'."\n", $v->[1]);
  }
}


