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
	my $warningRuns;
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
						my ($result,$warnings) = $self->validateResult($sisphus,\@row,$qcResultHeaderMap,$self->{QC_REQUIREMENT},$_); 
						
						if(defined($warnings)) {
							$warningRuns->{$row[$qcResultHeaderMap->{'Lane'}]}->{$row[$qcResultHeaderMap->{'Read'}]} = $warnings;
						}
						
						if(defined($result) && ref($result) eq 'HASH')
						{
							$failedRuns->{$row[$qcResultHeaderMap->{'Lane'}]}->{$row[$qcResultHeaderMap->{'Read'}]} = $result;
						}#elsif(defined($result)) {
						#	return $result;
						#}
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

	if(scalar keys %{$failedRuns} == 0 && scalar keys %{$warningRuns} == 0)
	{
		print "Passed QC\n" if($self->{VERBOSE});
		return (undef, undef);
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
			print "The following lanes gave warnings:\n";
			foreach my $lane (sort keys %{$warningRuns}) {
				foreach my $read (sort keys %{$warningRuns->{$lane}}) {
					print "Lane: $lane\tRead: $read\n";
					foreach my $warning (sort keys %{$warningRuns->{$lane}->{$read}}) {
						if($warning eq 'sampleFraction')
						{
							print " -Insufficient data for the following samples:\n";
							foreach my $sample (keys %{$warningRuns->{$lane}->{$read}->{$warning}}) {
								print " --Sample: $sample\tResult:$warningRuns->{$lane}->{$read}->{$warning}->{$sample}->{res}\tRequired:$warningRuns->{$lane}->{$read}->{$warning}->{$sample}->{req}\n";
							}
						}
						else
						{
							print " -$warning\tResult:$warningRuns->{$lane}->{$read}->{$warning}->{res}\tRequired:$warningRuns->{$lane}->{$read}->{$warning}->{req}\n";
						}
					}
				}
			}
		}

		$failedRuns = undef if(scalar keys %{$failedRuns} == 0);
		$warningRuns = undef if(scalar keys %{$warningRuns} == 0);
		return ($failedRuns,$warningRuns);
	}
}


sub validateResult {
	my $self = shift;
	my $sisphus = shift;
	my $result = shift;
	my $resultMapping = shift;
	my $qcXML = shift;
        my $qcRequirements = shift;

	my $failures;
	my $warnings;

	if((exists($qcXML->{overrides}->{pass}->{"lane" . $result->[$resultMapping->{'Lane'}]}->{'unidentified'}) &&
            	$qcXML->{overrides}->{pass}->{"lane" . $result->[$resultMapping->{'Lane'}]}->{'unidentified'} < $result->[$resultMapping->{'Unidentified'}]) ||
           (!exists($qcXML->{overrides}->{pass}->{"lane" . $result->[$resultMapping->{'Lane'}]}->{'unidentified'}) && 
	    	$qcRequirements->{'unidentified'} < $result->[$resultMapping->{'Unidentified'}]))
	{
		
		print "Failed unidentified requirement: $result->[$resultMapping->{'Unidentified'}] ($qcRequirements->{'unidentified'})!\n" if($self->{VERBOSE});
		$failures->{unidentified}->{'req'} = $qcRequirements->{'unidentified'};
		$failures->{unidentified}->{'res'} = $result->[$resultMapping->{'Unidentified'}];
	}
	else
	{
		if(exists($qcXML->{overrides}->{warning}->{"lane" . $result->[$resultMapping->{'Lane'}]}->{'unidentified'}) &&
		    $qcXML->{overrides}->{warning}->{"lane" . $result->[$resultMapping->{'Lane'}]}->{'unidentified'} < $result->[$resultMapping->{'Unidentified'}]) {
			$warnings->{unidentified}->{'req'} = $qcRequirements->{'unidentified'};
			$warnings->{unidentified}->{'res'} = $result->[$resultMapping->{'Unidentified'}];
		}
		print "Passed unidentified requirement: $result->[$resultMapping->{'Unidentified'}] ($qcRequirements->{'unidentified'})!\n" if($self->{VERBOSE});
	}
	if((exists($qcXML->{overrides}->{pass}->{"lane" . $result->[$resultMapping->{'Lane'}]}->{'numberOfCluster'}) &&
            	$qcXML->{overrides}->{pass}->{"lane" . $result->[$resultMapping->{'Lane'}]}->{'numberOfCluster'} > $result->[$resultMapping->{'ReadsPF (M)'}]) ||
	   (!exists($qcXML->{overrides}->{pass}->{"lane" . $result->[$resultMapping->{'Lane'}]}->{'numberOfCluster'}) &&
	    	$qcRequirements->{'numberOfCluster'} > $result->[$resultMapping->{'ReadsPF (M)'}]))
        {
		print "Failed generated cluster requirement: $result->[$resultMapping->{'ReadsPF (M)'}] ($qcRequirements->{'numberOfCluster'})!\n" if($self->{VERBOSE});
		$failures->{numberOfCluster}->{'req'} = $qcRequirements->{'numberOfCluster'};
	        $failures->{numberOfCluster}->{'res'} = $result->[$resultMapping->{'ReadsPF (M)'}];
        }
	else
	{
		if(exists($qcXML->{overrides}->{warning}->{"lane" . $result->[$resultMapping->{'Lane'}]}->{'numberOfCluster'}) &&
		    $qcXML->{overrides}->{warning}->{"lane" . $result->[$resultMapping->{'Lane'}]}->{'numberOfCluster'} > $result->[$resultMapping->{'ReadsPF (M)'}]) {
			$warnings->{numberOfCluster}->{'req'} = $qcRequirements->{'numberOfCluster'};
	                $warnings->{numberOfCluster}->{'res'} = $result->[$resultMapping->{'ReadsPF (M)'}];
		}
		print "Passed generated cluster requirement: $result->[$resultMapping->{'ReadsPF (M)'}] ($qcRequirements->{'numberOfCluster'})!\n" if($self->{VERBOSE});
	}
	my $readLength = $result->[$resultMapping->{Read}] == 1 ? $sisphus->getRead1Length() : $sisphus->getRead2Length();

	if(!(exists($qcXML->{overrides}->{pass}->{"lane" . $result->[$resultMapping->{'Lane'}]}->{'l$readLength'})) &&
	    !exists($qcRequirements->{lengths}->{"l$readLength"})) {
		print STDERR "Couldn't find the used read length $readLength in the sisyphus_qc.xml file!\n";
		return SEQUENCED_LENGTH_NOT_FOUND;
	}

	if((exists($qcXML->{overrides}->{pass}->{"lane" . $result->[$resultMapping->{'Lane'}]}->{"l$readLength"}->{q30}) &&
            	$qcXML->{overrides}->{pass}->{"lane" . $result->[$resultMapping->{'Lane'}]}->{"l$readLength"}->{q30} > $result->[$resultMapping->{'Yield Q30 (G)'}]) ||
	   (!exists($qcXML->{overrides}->{pass}->{"lane" . $result->[$resultMapping->{'Lane'}]}->{"l$readLength"}->{q30}) &&
		$qcRequirements->{lengths}->{"l$readLength"}->{q30} > $result->[$resultMapping->{'Yield Q30 (G)'}]))
	{
		print "Failed Q30 yield requirement: $result->[$resultMapping->{'Yield Q30 (G)'}] (" . $qcRequirements->{lengths}->{"l$readLength"}->{q30} . ")!\n" if($self->{VERBOSE});
		$failures->{q30}->{'req'} = $qcRequirements->{lengths}->{"l$readLength"}->{q30};
                $failures->{q30}->{'res'} = $result->[$resultMapping->{'Yield Q30 (G)'}];
	}
	else
	{
		if(exists($qcXML->{overrides}->{warning}->{"lane" . $result->[$resultMapping->{'Lane'}]}->{"l$readLength"}->{q30}) &&
		   $qcXML->{overrides}->{warning}->{"lane" . $result->[$resultMapping->{'Lane'}]}->{"l$readLength"}->{q30} > $result->[$resultMapping->{'Yield Q30 (G)'}]) {
			$warnings->{q30}->{'req'} = exists($qcXML->{overrides}->{warning}->{"lane" . $result->[$resultMapping->{'Lane'}]}->{"l$readLength"}->{q30}) ? 
				$qcXML->{overrides}->{warning}->{"lane" . $result->[$resultMapping->{'Lane'}]}->{"l$readLength"}->{q30} : 
				$qcRequirements->{lengths}->{"l$readLength"}->{q30};

                	$warnings->{q30}->{'res'} = $result->[$resultMapping->{'Yield Q30 (G)'}];
		}
		print "Passed Q30 yield requirement: $result->[$resultMapping->{'Yield Q30 (G)'}] (" . $qcRequirements->{lengths}->{"l$readLength"}->{q30} . ")!\n" if($self->{VERBOSE});
	}

	if((exists($qcXML->{overrides}->{pass}->{"lane" . $result->[$resultMapping->{'Lane'}]}->{"l$readLength"}->{errorRate}) && 
	    (($qcXML->{overrides}->{pass}->{"lane" . $result->[$resultMapping->{'Lane'}]}->{"l$readLength"}->{errorRate} eq '-' && $result->[$resultMapping->{'ErrRate'}] eq '-') ||
            (!($result->[$resultMapping->{'ErrRate'}] eq "-") && $qcXML->{overrides}->{pass}->{"lane" . $result->[$resultMapping->{'Lane'}]}->{"l$readLength"}->{errorRate} >= $result->[$resultMapping->{'ErrRate'}]))) ||
	   (!exists($qcXML->{overrides}->{pass}->{"lane" . $result->[$resultMapping->{'Lane'}]}->{"l$readLength"}->{errorRate}) &&
		(($result->[$resultMapping->{'ErrRate'}] eq '-' && $qcRequirements->{lengths}->{"l$readLength"}->{errorRate} eq '-') || 
		((!($result->[$resultMapping->{'ErrRate'}] eq '-') && $qcRequirements->{lengths}->{"l$readLength"}->{errorRate} > $result->[$resultMapping->{'ErrRate'}])))))
        {
		if(exists($qcXML->{overrides}->{warning}->{"lane" . $result->[$resultMapping->{'Lane'}]}->{"l$readLength"}->{errorRate}) &&
		    $qcXML->{overrides}->{warning}->{"lane" . $result->[$resultMapping->{'Lane'}]}->{"l$readLength"}->{errorRate} < $result->[$resultMapping->{'ErrRate'}])
		{
			$warnings->{errorRate}->{'req'} = exists($qcXML->{overrides}->{warning}->{$result->[$resultMapping->{'Lane'}]}->{"l$readLength"}->{errorRate}) ? 
				$qcXML->{overrides}->{warning}->{"lane" . $result->[$resultMapping->{'Lane'}]}->{"l$readLength"}->{errorRate} : 
				$qcRequirements->{lengths}->{"l$readLength"}->{errorRate};

			$warnings->{errorRate}->{'res'} = $result->[$resultMapping->{'ErrRate'}];
		}
		print "Passed ErrorRate requirement: $result->[$resultMapping->{'ErrRate'}] (".$qcRequirements->{lengths}->{"l$readLength"}->{errorRate}.")!\n" if($self->{VERBOSE});
        }
	else
	{
                print "Failed ErrorRate requirement: $result->[$resultMapping->{'ErrRate'}] (" . $qcRequirements->{lengths}->{"l$readLength"}->{errorRate} . ")!\n" if($self->{VERBOSE});
		$failures->{errorRate}->{'req'} = $qcRequirements->{lengths}->{"l$readLength"}->{errorRate};
                $failures->{errorRate}->{'res'} = $result->[$resultMapping->{'ErrRate'}];
        }
      
	unless(defined($qcRequirements->{overridePoolingRequirement}) && $qcRequirements->{overridePoolingRequirement} eq 1) {
		my @samples = split(/,[ ]/,$result->[$resultMapping->{'Sample Fractions'}]);
		my $numberOfSamples = @samples;
		my $minData = $qcRequirements->{'numberOfCluster'} / 2 / $numberOfSamples;
		foreach(@samples) {
			$_ =~ s/^[ ]+//;
			my @info = split(/:/,$_);
			if((!(exists($qcXML->{overrides}->{pass}->{"lane" . $result->[$resultMapping->{'Lane'}]}->{overridePoolingRequirement}) ||
			     $qcXML->{overrides}->{pass}->{"lane" . $result->[$resultMapping->{'Lane'}]}->{overridePoolingRequirement}) == 1) &&
 ($info[0]/100*$result->[$resultMapping->{'ReadsPF (M)'}]) < $minData)
			{
				print "Sample $info[1] haven't received sufficient amount data: " . ($info[0]/100*$result->[$resultMapping->{'ReadsPF (M)'}]) . " ($minData)\n" if($self->{VERBOSE});
				if(exists($qcXML->{overrides}->{warning}->{"lane" . $result->[$resultMapping->{'Lane'}]}->{overridePoolingRequirement}) &&
				   $qcXML->{overrides}->{warning}->{"lane" . $result->[$resultMapping->{'Lane'}]}->{overridePoolingRequirement} == 1) {
					$warnings->{sampleFraction}->{$info[1]}->{'req'} = $minData;
        	        		$warnings->{sampleFraction}->{$info[1]}->{'res'} = $info[0]/100*$result->[$resultMapping->{'ReadsPF (M)'}];
				}
				else
				{
					$failures->{sampleFraction}->{$info[1]}->{'req'} = $minData;
                                        $failures->{sampleFraction}->{$info[1]}->{'res'} = $info[0]/100*$result->[$resultMapping->{'ReadsPF (M)'}];
				}
			}
			else
			{
				print "Sample $info[1] have received sufficient amount of data: " . ($info[0]/100*$result->[$resultMapping->{'ReadsPF (M)'}]) . " ($minData)\n" if($self->{VERBOSE}); 
			}
		}
	}

	return ((scalar keys %{$failures}) > 0 ? $failures : undef,(scalar keys %{$warnings}) > 0 ? $warnings : undef);

}
