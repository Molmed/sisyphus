#!/usr/bin/perl -w

=head1 NAME

countTags.pl - Count the occurances of each tag in a fastq-file

=head1 SYNOPSIS

zcat Unaligned/Undetermined_indices/Sample_lane1/lane1_Undetermined_L001_R1_001.fastq.gz > Unaligned/Undetermined_indices/Sample_lane1/tags.txt

=cut

my $n=0;
my %tags;
while(<>){
  if(m/^@.*:([ACTGN]+)$/){
    $tags{$1}++;
    $n++;
  }
  my $foo=<>;
  $foo=<>;
  $foo=<>;
}

foreach my $tag (sort {$tags{$a}<=>$tags{$b}} keys %tags){
  print "$tag\t$tags{$tag}\t$n\t" . sprintf('%.2f', $tags{$tag}/$n*100) . "\%\n";
}

#@HWI-ST344:173:D0RJVACXX:7:1101:2611:2208 1:N:0:GAAGGT

