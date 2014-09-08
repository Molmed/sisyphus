#!/usr/bin/perl -w

use FindBin;                # Find the script location
use lib "$FindBin::Bin/lib";
use Getopt::Long;
use Molmed::Sisyphus::Common;
use Molmed::Sisyphus::QCRequirementValidation;

use strict;
use warnings;

my $rfPath = undef;
our $debug = 0;
my ($help,$man) = (0,0);

GetOptions('runfolder=s' => \$rfPath, 
) or pod2usage(-verbose => 0);

pod2usage(-verbose => 1)  if ($help);
pod2usage(-verbose => 2)  if ($man);

my $sisyphus = Molmed::Sisyphus::Common->new(PATH=>$rfPath, DEBUG=>$debug);

$sisyphus->getRunInfo();
$sisyphus->runParameters();

my $qc = QCRequirementValidation->new(DEBUG=>$debug);
my $file = "sisyphus_qc.xml";
$qc->loadQCRequirement($file);
my $result = $qc->validateSequenceRun($sisyphus,"quickReport.txt");

if(!defined($result))
{
	print "Passed QC!\n";
}
else
{
	foreach my $lane (keys %{$result}) {
		print "Lane $lane failed the following QC-criteria:\n";
		foreach my $read (keys %{$result->{$lane}}) {
			print "\tRead $read:\n";
			foreach my $criteria (keys %{$result->{$lane}->{$read}}) {
				if($criteria eq 'sampleFraction') {
					print "\t\t$criteria:\n";
					foreach my $sample (
							sort {$result->{$lane}->{$read}->{$criteria}->{$a}->{res} <=> $result->{$lane}->{$read}->{$criteria}->{$b}->{res}} 
							keys  %{$result->{$lane}->{$read}->{$criteria}}) {
						printf("\t\t\t%s: %.3f (%.3f)\n", $sample, $result->{$lane}->{$read}->{$criteria}->{$sample}->{res}, $result->{$lane}->{$read}->{$criteria}->{$sample}->{req});
					}
				}
				else {
					print "\t\t$criteria\t$result->{$lane}->{$read}->{$criteria}->{res} ($result->{$lane}->{$read}->{$criteria}->{req})\n";
				}
			}
		}
	}
}
