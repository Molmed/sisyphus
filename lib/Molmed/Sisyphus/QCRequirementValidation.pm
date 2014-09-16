package Molmed::Sisyphus::QCRequirementValidation;

use base 'Exporter';
our @EXPORT_OK = ('mkpath');

use strict;
use warnings;

use Molmed::Sisyphus::Libpath;

use XML::Simple;
use Data::Dumper;

use constant RUN_TYPE_NOT_FOUND => 102;
use constant SEQUENCED_LENGTH_NOT_FOUND => 103;
use constant ERROR_READING_QUICKREPORT => 104;
use constant ERROR_READING_QC_CRITERIAS => 105;

use Scalar::Util;

sub new{
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = {@_};

    $self->{VERBOSE} = defined $self->{DEBUG} && $self->{DEBUG}  ? 1 : 0;

    bless ($self, $class);

    return $self;
}

=pod

=head1 FUNCTIONS

=head2 loadQCRequirement()

 Title   : loadQCRequirement
 Usage   : $qc->loadQCRequirement($file)
 Function: 
 Example :
 Returns : hash reference containing requirements
 Args    : file path (absolute or relative to runfolder)

=cut

sub loadQCRequirement {
	my $self = shift;
	my $file = shift;

	eval {
		$self->{QC_REQUIREMENT} = XMLin($file);		
	};
	return ERROR_READING_QC_CRITERIAS if $@;

	return 0;
}

=pod

=head1 FUNCTIONS

=head2  validateSequenceRun()

 Title   : validateSequenceRun
 Usage   : $qc->validateSequenceRun($file)
 Function: 
 Example :
 Returns : hash reference containing requirements
 Args    : file path (absolute or relative to runfolder)

=cut

sub validateSequenceRun {
	my $self = shift;
	my $sisphus = shift;
	my $qcResultFile = shift;
	
	my $qcResult;
	my $qcResultHeaderMap;
	die "QC requirements haven't been loaded!\n" if(!defined($self->{QC_REQUIREMENT}));
	my $qcResultFILE;
	#print Dumper$self->{QC_REQUIREMENT});
	unless (open($qcResultFILE, $qcResultFile)) {
		return ERROR_READING_QUICKREPORT;
	}

	my $failedRuns;
	while(<$qcResultFILE>) {
		chomp;
		my @row = split(/\t/, $_);

		if(/^Lane/)
		{
			my $counter = 0;
			foreach (@row) {
				$qcResultHeaderMap->{$_} = $counter;
				$counter++;
			}
		}
		else
		{
			my $qcRequirementsFound = 0;
			foreach (@{$self->{QC_REQUIREMENT}->{'platforms'}->{'platform'}}) {
				if($_->{'controlSoftware'} eq $sisphus->getApplicationName() && 
				   $_->{'version'} eq $sisphus->getReagentKitVersion()) {
					if(($_->{'controlSoftware'} =~ /^MiSeq/ ) || ($_->{'controlSoftware'} =~ /^HiSeq/ && 
					    $_->{'mode'} eq  $sisphus->getRunMode())) {
						$qcRequirementsFound = 1;
						if($self->{VERBOSE}) {
							print STDOUT "Info: " . $_->{'controlSoftware'} . "\t" . 
							       $_->{'version'} . 
							       ($_->{'controlSoftware'} =~ /^HiSeq/ ? "\t".$sisphus->getRunMode() : "") . "\n" ;
						}
						my $result = $self->validateResult($sisphus,\@row,$qcResultHeaderMap,$_); 

						if(defined($result) && ref($result) eq 'HASH')
						{
							$failedRuns->{$row[$qcResultHeaderMap->{'Lane'}]}->{$row[$qcResultHeaderMap->{'Read'}]} = $result;
						} elsif(defined($result)) {
							return $result;
						}
					}
				}
			}
			if(!$qcRequirementsFound) {
				print STDERR "Couldn't find any specified QC requirements for the used run parameters!\n";
				return RUN_TYPE_NOT_FOUND;
			}
		}
	}
	
	close($qcResultFILE);

	if(scalar keys %{$failedRuns} == 0)
	{
		print "Passed QC\n" if($self->{VERBOSE});
		return undef;
	}
	else
	{
		if($self->{VERBOSE}) {
			print "The following lanes failed:\n";
			foreach my $lane (sort keys %{$failedRuns}) {
				foreach my $read (sort keys %{$failedRuns->{$lane}}) {
					print "Lane: $lane\tRead: $read\n";
					foreach my $failure (sort keys %{$failedRuns->{$lane}->{$read}}) {
						if($failure eq 'sampleFraction')
						{
							print " -Insufficient data for the following samples:\n";
							foreach my $sample (keys %{$failedRuns->{$lane}->{$read}->{$failure}}) {
								print " --Sample: $sample\tResult:$failedRuns->{$lane}->{$read}->{$failure}->{$sample}->{res}\tRequired:$failedRuns->{$lane}->{$read}->{$failure}->{$sample}->{req}\n";
							}
						}
						else
						{
							print " -$failure\tResult:$failedRuns->{$lane}->{$read}->{$failure}->{res}\tRequired:$failedRuns->{$lane}->{$read}->{$failure}->{req}\n";
						}
					}
				}
			}
		}
		return $failedRuns;
	}
}


sub validateResult {
	my $self = shift;
	my $sisphus = shift;
	my $result = shift;
	my $resultMapping = shift;
        my $qcRequirements = shift;

	my $failures;
	
	if($qcRequirements->{'unidentified'} < $result->[$resultMapping->{'Unidentified'}])
	{
		print "Failed unidentified requirement: $result->[$resultMapping->{'Unidentified'}] ($qcRequirements->{'unidentified'})!\n" if($self->{VERBOSE});
		$failures->{unidentified}->{'req'} = $qcRequirements->{'unidentified'};
		$failures->{unidentified}->{'res'} = $result->[$resultMapping->{'Unidentified'}];
	}
	else
	{
		print "Passed unidentified requirement: $result->[$resultMapping->{'Unidentified'}] ($qcRequirements->{'unidentified'})!\n" if($self->{VERBOSE});
	}
	if($qcRequirements->{'numberOfCluster'} > $result->[$resultMapping->{'ReadsPF (M)'}])
        {
                print "Failed generated cluster requirement: $result->[$resultMapping->{'ReadsPF (M)'}] ($qcRequirements->{'numberOfCluster'})!\n" if($self->{VERBOSE});
		$failures->{numberOfCluster}->{'req'} = $qcRequirements->{'numberOfCluster'};
                $failures->{numberOfCluster}->{'res'} = $result->[$resultMapping->{'ReadsPF (M)'}];
        }
	else
	{
		print "Passed generated cluster requirement: $result->[$resultMapping->{'ReadsPF (M)'}] ($qcRequirements->{'numberOfCluster'})!\n" if($self->{VERBOSE});
	}
	my $readLength = $result->[$resultMapping->{Read}] == 1 ? $sisphus->getRead1Length() : $sisphus->getRead2Length();

	if(!defined($qcRequirements->{lengths}->{"l$readLength"})) {
		print STDERR "Couldn't find the used read length $readLength in the sisyphus_qc.xml file!\n";
		return SEQUENCED_LENGTH_NOT_FOUND;
	}

	if($qcRequirements->{lengths}->{"l$readLength"}->{q30} > $result->[$resultMapping->{'Yield Q30 (G)'}])
	{
		print "Failed Q30 yield requirement: $result->[$resultMapping->{'Yield Q30 (G)'}] (" . $qcRequirements->{lengths}->{"l$readLength"}->{q30} . ")!\n" if($self->{VERBOSE});
		$failures->{q30}->{'req'} = $qcRequirements->{lengths}->{"l$readLength"}->{q30};
                $failures->{q30}->{'res'} = $result->[$resultMapping->{'Yield Q30 (G)'}];

	}
	else
	{
		print "Passed Q30 yield requirement: $result->[$resultMapping->{'Yield Q30 (G)'}] (" . $qcRequirements->{lengths}->{"l$readLength"}->{q30} . ")!\n" if($self->{VERBOSE});
	}

	if($result->[$resultMapping->{'ErrRate'}] eq '-' || $qcRequirements->{lengths}->{"l$readLength"}->{errorRate} < $result->[$resultMapping->{'ErrRate'}])
        {
                print "Failed ErrorRate requirement: $result->[$resultMapping->{'ErrRate'}] (" . $qcRequirements->{lengths}->{"l$readLength"}->{errorRate} . ")!\n" if($self->{VERBOSE});
		$failures->{errorRate}->{'req'} = $qcRequirements->{lengths}->{"l$readLength"}->{errorRate};
                $failures->{errorRate}->{'res'} = $result->[$resultMapping->{'ErrRate'}];
        }
        else
        {
                print "Passed ErrorRate requirement: $result->[$resultMapping->{'ErrRate'}] (".$qcRequirements->{lengths}->{"l$readLength"}->{errorRate}.")!\n" if($self->{VERBOSE});
        }
	my @samples = split(/,[ ]/,$result->[$resultMapping->{'Sample Fractions'}]);
	my $numberOfSamples = @samples;
	my $minData = $qcRequirements->{'numberOfCluster'} / 2 / $numberOfSamples;
	foreach(@samples) {
		$_ =~ s/^[ ]+//;
		my @info = split(/:/,$_);
		if(($info[0]/100*$result->[$resultMapping->{'ReadsPF (M)'}]) < $minData)
		{
			print "Sample $info[1] haven't received sufficient amount data: " . ($info[0]/100*$result->[$resultMapping->{'ReadsPF (M)'}]) . " ($minData)\n" if($self->{VERBOSE});
			$failures->{sampleFraction}->{$info[1]}->{'req'} = $minData;
                	$failures->{sampleFraction}->{$info[1]}->{'res'} = $info[0]/100*$result->[$resultMapping->{'ReadsPF (M)'}];
		}
		else
		{
			print "Sample $info[1] have received sufficient amount of data: " . ($info[0]/100*$result->[$resultMapping->{'ReadsPF (M)'}]) . " ($minData)\n" if($self->{VERBOSE}); 
		}
	}
	return (scalar keys %{$failures}) > 0 ? $failures : undef;
}
