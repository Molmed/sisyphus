package Molmed::Sisyphus::QCRequirementValidation;

use base 'Exporter';
our @EXPORT_OK = ('mkpath');

use strict;
use warnings;

use Molmed::Sisyphus::Libpath;

use XML::Simple;

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
 Function: load data found qc xml file
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
 Function: Process each lane and validate the generated result.
 Example :
 Returns : hash reference containing requirements
	   Output format
           {
		'lane index' => {
			'read index' => {
				'criteria name' => {	
					'req' => value #required value
					'res' => value #actual value
				}
			}
		}
	   }
           Example
	   {
		'1' => {
			'1' => {
				'numberOfCluster' => {
					'res' => 139,
					'req' => '140'
				}
			},
			'2' => {
				'numberOfCluster' => {
					'res' => 139,
					'req' => 140
				}
			}
                 },
		'3' => {
			'1' => {
				'errorRate' => {
					'res' => '2.1',
					'req' => '2.0'
				}
			}
		},
	   }
 Args    : sisyphus object
	   the entire QC xml file	   

=cut

sub validateSequenceRun {
	my $self = shift;
	my $sisyphus = shift;
	my $qcResultFile = shift;
	
	my $qcResult;

	my $qcResultHeaderMap;
	die "QC requirements haven't been loaded!\n" if(!defined($self->{QC_REQUIREMENT}));
	my $qcResultFILE;

	unless (open($qcResultFILE, $qcResultFile)) {
		return ERROR_READING_QUICKREPORT;
	}

	my $failedRuns = {};
	my $warningRuns = {};
	#Loop each row in the quickReport
	while(<$qcResultFILE>) {
		chomp;
		#Seperate each column
		my @row = split(/\t/, $_);
		if(/^Lane/)
		{
			#Create a hash used to map columns with criteria name
			my $counter = 0;
			foreach (@row) {
				$qcResultHeaderMap->{$_} = $counter;
				$counter++;
			}
		}
		else
		{
			#Process the data
			my $qcRequirementsFound = 0;
			foreach (@{$self->{QC_REQUIREMENT}->{'platforms'}->{'platform'}}) {
				#Check runParameters that will be used to select QC criterias
				if($_->{'controlSoftware'} eq $sisyphus->getApplicationName() && 
				   $_->{'version'} eq $sisyphus->getReagentKitVersion()) {
					#For HiSeq the runMode should be checked
					if(($_->{'controlSoftware'} =~ /^MiSeq/ ) || ($_->{'controlSoftware'} =~ /^HiSeq/ && 
					    $_->{'mode'} eq  $sisyphus->getRunMode())) {
						$qcRequirementsFound = 1;
						if($self->{VERBOSE}) {
							print STDOUT "Info: " . $_->{'controlSoftware'} . "\t" . 
							       $_->{'version'} . 
							       ($_->{'controlSoftware'} =~ /^HiSeq/ ? "\t".$sisyphus->getRunMode() : "") . "\n" ;
						}
						#Validate the data with the selected QC criteria
						my ($result,$warnings) = $self->validateResult($sisyphus,\@row,$qcResultHeaderMap,$self->{QC_REQUIREMENT},$_); 
						
						#Save warnings: result hash->{'lane index'}->{'read index'}
						if(defined($warnings)) {
							$warningRuns->{$row[$qcResultHeaderMap->{'Lane'}]}->{$row[$qcResultHeaderMap->{'Read'}]} = $warnings;
						}
						
						#Save failed: result hash->{'lane index'}->{'read index'}
						if(defined($result) && ref($result) eq 'HASH')
						{
							$failedRuns->{$row[$qcResultHeaderMap->{'Lane'}]}->{$row[$qcResultHeaderMap->{'Read'}]} = $result;
						}
						elsif(defined($result) && $result == SEQUENCED_LENGTH_NOT_FOUND) {
							return SEQUENCED_LENGTH_NOT_FOUND;
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

=pod

=head1 FUNCTIONS

=head2  validateResult()

 Title   : validateResult
 Usage   : $qc->validateResult($sisyphus, $result, $resultMapping, $qcXML, $qcRequirements)
 Function: Goes through each QC requirement.
 Example :
 Returns : ($failures ,$warnings) an array containing hash reference result for failures and warnings
	   Output format
           {
		'criteria name' => {
			'req' => value #required value
			'res' => value #actual value
		}
	   }
           Example
	   {
          	'unidentified' => {
			'req' => '5.0',
			'res' => '7.7'
		},
          	'errorRate' => {
			'req' => '2.0',
			'res' => '0.32'
		}
		'SLE_H_FF_pool141_tag12' => {
			'req' => '8.75',
			'res' => 0
                }
           }
 Args    : sisyphus object
	   hash reference that contain result that have been imported from a quickReport
	   mapping object used to extract correct columns from the result hash
	   the entire QC xml file
           the part of the QC requirements that match the used runParameters

=cut

sub validateResult {
	my $self = shift;
	my $sisyphus = shift;
	my $result = shift;
	my $resultMapping = shift;
	my $qcXML = shift;
        my $qcRequirements = shift;

	my $failures;
	my $warnings;

	#Retrieve values used to override the default QC values
	my $passReq = $qcXML->{overrides}->{pass}->{"lane" . $result->[$resultMapping->{'Lane'}]};
	#Retrieve values used to check if a warning should be sent out for one or multiple QC criterias.
	my $warningReq = $qcXML->{overrides}->{warning}->{"lane" . $result->[$resultMapping->{'Lane'}]};

	#Validate that not too many unidentified have been generated
	($failures ,$warnings) = $self->checkUnidentified($qcRequirements, $passReq, $warningReq, $result, $resultMapping, $failures, $warnings);
	#Validate that enough clusters have been generated.
	($failures ,$warnings) = $self->checkNumberOfClusters($qcRequirements, $passReq, $warningReq, $result, $resultMapping, $failures, $warnings);

	#Retrieve the read length that have been used
	my $readLength = $result->[$resultMapping->{Read}] == 1 ? "l" . $sisyphus->getRead1Length() : "l" . $sisyphus->getRead2Length();
	#Validate that the read length that have been used, exists as default or a override instance
	if(!(exists($passReq->{$readLength})) &&
	    !exists($qcRequirements->{lengths}->{$readLength})) {
		print STDERR "Couldn't find the used read length $readLength in the sisyphus_qc.xml file!\n";
		return SEQUENCED_LENGTH_NOT_FOUND;
	}

	#Validate that the Q30 yield is big enough.
	($failures ,$warnings) = $self->checkQ30($qcRequirements, $passReq, $warningReq, $readLength, $result, $resultMapping, $failures, $warnings);
	#Validate that the error rate isn't too high.
	($failures ,$warnings) = $self->checkErrorRate($qcRequirements, $passReq, $warningReq, $readLength, $result, $resultMapping, $failures, $warnings);
	#Check that all samples have enough data.
	($failures ,$warnings) = $self->checkPooling($qcRequirements, $passReq, $warningReq, $result, $resultMapping, $failures, $warnings);
	
	return ((scalar keys %{$failures}) > 0 ? $failures : undef,(scalar keys %{$warnings}) > 0 ? $warnings : undef);

}

=pod

=head1 FUNCTIONS

=head2  checkUnidentified()

 Title   : checkUnidentified
 Usage   : $qc->checkUnidentified($qcRequirements, $passReq, $warningReq, $result, $resultMapping, $failures, $warnings)
 Function: 
 Example :
 Returns : ($failures ,$warnings) an array containing hash reference result for failures and warnings 
 Args    : the part of the QC requirements that match the used runParameters
	   hash which define if standard requirements should be overridden
	   hash which define if warnings should be sent out.
	   hash reference that contain result that have been imported from a quickReport.
	   mapping object used to extract correct columns from the result hash.
	   hash with already failed parameters.
           hash with parameters that will have warnings.

=cut

sub checkUnidentified {
	my $self = shift;

	my $qcRequirements = shift;
	my $passReq = shift;
	my $warningReq = shift;

	my $result = shift;
	my $resultMapping = shift;

	my $failures = shift;
	my $warnings = shift;
	
	#First check if the standard criterias should be overridden. If so, use the override parameters to validate the result.
	#Else the standard parameters should be used
	if((exists($passReq->{'unidentified'}) && $passReq->{'unidentified'} < $result->[$resultMapping->{'Unidentified'}]) ||
           (!exists($passReq->{'unidentified'}) && $qcRequirements->{'unidentified'} < $result->[$resultMapping->{'Unidentified'}]))
	{
		print "Failed unidentified requirement: $result->[$resultMapping->{'Unidentified'}] ($qcRequirements->{'unidentified'})!\n" if($self->{VERBOSE});
		#Save failed values.
		$failures->{unidentified}->{'req'} = $qcRequirements->{'unidentified'};
		$failures->{unidentified}->{'res'} = $result->[$resultMapping->{'Unidentified'}];
	}
	else
	{
		#Check if a warning should saved, it will be saved if the result passes standard/override parameters but are bigger then the warning value.
		if(exists($warningReq->{'unidentified'}) && $warningReq->{'unidentified'} < $result->[$resultMapping->{'Unidentified'}]) {	
			$warnings->{unidentified}->{'req'} = $qcRequirements->{'unidentified'};
			$warnings->{unidentified}->{'res'} = $result->[$resultMapping->{'Unidentified'}];
		}
		print "Passed unidentified requirement: $result->[$resultMapping->{'Unidentified'}] ($qcRequirements->{'unidentified'})!\n" if($self->{VERBOSE});
	}

	#Return failures and warnings
	return ($failures ,$warnings);
}

=pod

=head1 FUNCTIONS

=head2  checkNumberOfClusters()

 Title   : checkNumberOfClusters
 Usage   : $qc->checkNumberOfClusters($qcRequirements, $passReq, $warningReq, $result, $resultMapping, $failures, $warnings)
 Function: Validate that enough clusters have been generated
 Example :
 Returns : ($failures ,$warnings) an array containing hash reference result for failures and warnings 
 Args    : the part of the QC requirements that match the used runParameters
	   hash which define if standard requirements should be overridden
	   hash which define if warnings should be sent out.
	   hash reference that contain result that have been imported from a quickReport.
	   mapping object used to extract correct columns from the result hash.
	   hash with already failed parameters.
           hash with parameters that will have warnings.

=cut

sub checkNumberOfClusters{
	my $self = shift;

	my $qcRequirements = shift;
	my $passReq = shift;
	my $warningReq = shift;

	my $result = shift;
	my $resultMapping = shift;

	my $failures = shift;
	my $warnings = shift;

	#First check if the standard criterias should be overridden. If so, use the override parameters to validate the result.
	#Else the standard parameters should be used
	if((exists($passReq->{'numberOfCluster'}) && $passReq->{'numberOfCluster'} > $result->[$resultMapping->{'ReadsPF (M)'}]) ||
	   (!exists($passReq->{'numberOfCluster'}) && $qcRequirements->{'numberOfCluster'} > $result->[$resultMapping->{'ReadsPF (M)'}]))
        {
		print "Failed generated cluster requirement: $result->[$resultMapping->{'ReadsPF (M)'}] ($qcRequirements->{'numberOfCluster'})!\n" if($self->{VERBOSE});
		#Save failed values.
		$failures->{numberOfCluster}->{'req'} = $qcRequirements->{'numberOfCluster'};
	        $failures->{numberOfCluster}->{'res'} = $result->[$resultMapping->{'ReadsPF (M)'}];
        }
	else
	{
		#Check if a warning should saved, it will be saved if the result passes standard/override parameters but are smaller then the warning value.
		if(exists($warningReq->{'numberOfCluster'}) && $warningReq->{'numberOfCluster'} > $result->[$resultMapping->{'ReadsPF (M)'}]) {
			$warnings->{numberOfCluster}->{'req'} = $qcRequirements->{'numberOfCluster'};
	                $warnings->{numberOfCluster}->{'res'} = $result->[$resultMapping->{'ReadsPF (M)'}];
		}
		print "Passed generated cluster requirement: $result->[$resultMapping->{'ReadsPF (M)'}] ($qcRequirements->{'numberOfCluster'})!\n" if($self->{VERBOSE});
	}

	#Return failures and warnings
	return ($failures ,$warnings);
}

=pod

=head1 FUNCTIONS

=head2  checkQ30()

 Title   : checkQ30
 Usage   : $qc->checkQ30($qcRequirements, $passReq, $warningReq, $result, $resultMapping, $failures, $warnings)
 Function: Validate that the Q30 yield isn't too small
 Example :
 Returns : ($failures ,$warnings) an array containing hash reference result for failures and warnings 
 Args    : the part of the QC requirements that match the used runParameters
	   hash which define if standard requirements should be overridden
	   hash which define if warnings should be sent out.
	   hash reference that contain result that have been imported from a quickReport.
	   mapping object used to extract correct columns from the result hash.
	   hash with already failed parameters.
           hash with parameters that will have warnings.

=cut

sub checkQ30{
	my $self = shift;

	my $qcRequirements = shift;
	my $passReq = shift;
	my $warningReq = shift;

	my $readLength = shift;
	my $result = shift;
	my $resultMapping = shift;

	my $failures = shift;
	my $warnings = shift;

	#First check if the standard criterias should be overridden. If so, use the override parameters to validate the result.
	#Else the standard parameters should be used
	if((exists($passReq->{$readLength}->{q30}) && $passReq->{$readLength}->{q30} > $result->[$resultMapping->{'Yield Q30 (G)'}]) ||
	   (!exists($passReq->{$readLength}->{q30}) && $qcRequirements->{lengths}->{$readLength}->{q30} > $result->[$resultMapping->{'Yield Q30 (G)'}]))
	{
		print "Failed Q30 yield requirement: $result->[$resultMapping->{'Yield Q30 (G)'}] (" . $qcRequirements->{lengths}->{$readLength}->{q30} . ")!\n" if($self->{VERBOSE});
		#Save failed values.
		$failures->{q30}->{'req'} = $qcRequirements->{lengths}->{$readLength}->{q30};
                $failures->{q30}->{'res'} = $result->[$resultMapping->{'Yield Q30 (G)'}];
	}
	else
	{
		#Check if a warning should saved, it will be saved if the result passes standard/override parameters but are smaller then the warning value.
		if(exists($warningReq->{$readLength}->{q30}) && $warningReq->{$readLength}->{q30} > $result->[$resultMapping->{'Yield Q30 (G)'}]) {
			$warnings->{q30}->{'req'} = exists($warningReq->{$readLength}->{q30}) ? 
				$warningReq->{$readLength}->{q30} : $qcRequirements->{lengths}->{$readLength}->{q30};

                	$warnings->{q30}->{'res'} = $result->[$resultMapping->{'Yield Q30 (G)'}];
		}
		print "Passed Q30 yield requirement: $result->[$resultMapping->{'Yield Q30 (G)'}] (" . $qcRequirements->{lengths}->{$readLength}->{q30} . ")!\n" if($self->{VERBOSE});
	}
	
	#Return failures and warnings
	return ($failures ,$warnings);
}

=pod

=head1 FUNCTIONS

=head2  checkErrorRate()

 Title   : checkErrorRate
 Usage   : $qc->checkErrorRate($qcRequirements, $passReq, $warningReq, $result, $resultMapping, $failures, $warnings)
 Function: Validate that the error rate isn't too big or that it should be missing.
 Example :
 Returns : ($failures ,$warnings) an array containing hash reference result for failures and warnings 
 Args    : the part of the QC requirements that match the used runParameters
	   hash which define if standard requirements should be overridden
	   hash which define if warnings should be sent out.
	   hash reference that contain result that have been imported from a quickReport.
	   mapping object used to extract correct columns from the result hash.
	   hash with already failed parameters.
           hash with parameters that will have warnings.

=cut

sub checkErrorRate{
	my $self = shift;

	my $qcRequirements = shift;
	my $passReq = shift;
	my $warningReq = shift;

	my $readLength = shift;
	my $result = shift;
	my $resultMapping = shift;

	my $failures = shift;
	my $warnings = shift;
	
	#First check if the standard criterias should be overridden. If so, use the override parameters to validate the result.
	if((exists($passReq->{$readLength}->{errorRate}) && 
	    #Check if error rate is missing from result. If so, it must also be defined as 
            #missing in the qc file, for the override parameters, in order to pass
            (($passReq->{$readLength}->{errorRate} eq '-' && $result->[$resultMapping->{'ErrRate'}] eq '-') ||
	    #If error rate isn't missing, compare the values  defined in the override tag.
            (!($result->[$resultMapping->{'ErrRate'}] eq "-") && $passReq->{$readLength}->{errorRate} >= $result->[$resultMapping->{'ErrRate'}]))) ||
	    #Use standard criterias
	   (!exists($passReq->{$readLength}->{errorRate}) &&
		#Check if error rate is missing from result. If so, it must also be defined as 
                #missing in the qc file, for the default parameters, in order to pass
		(($result->[$resultMapping->{'ErrRate'}] eq '-' && $qcRequirements->{lengths}->{$readLength}->{errorRate} eq '-') || 
		#If error rate isn't missing, compare the values  defined in the standard tag.
		((!($result->[$resultMapping->{'ErrRate'}] eq '-') && $qcRequirements->{lengths}->{$readLength}->{errorRate} > $result->[$resultMapping->{'ErrRate'}])))))
        {
		#Check if a warning should saved, it will be saved if the result passes standard/override parameters but are bigger then the warning value (or missing).
		if(exists($warningReq->{$readLength}->{errorRate}) && $warningReq->{$readLength}->{errorRate} < $result->[$resultMapping->{'ErrRate'}])
		{
			$warnings->{errorRate}->{'req'} = exists($warningReq->{$readLength}->{errorRate}) ? 
				$warningReq->{$readLength}->{errorRate} : 
				$qcRequirements->{lengths}->{$readLength}->{errorRate};

			$warnings->{errorRate}->{'res'} = $result->[$resultMapping->{'ErrRate'}];
		}
		print "Passed ErrorRate requirement: $result->[$resultMapping->{'ErrRate'}] (".$qcRequirements->{lengths}->{$readLength}->{errorRate}.")!\n" if($self->{VERBOSE});
        }
	else
	{
                print "Failed ErrorRate requirement: $result->[$resultMapping->{'ErrRate'}] (" . $qcRequirements->{lengths}->{$readLength}->{errorRate} . ")!\n" if($self->{VERBOSE});
		#Save failed values.
		$failures->{errorRate}->{'req'} = $qcRequirements->{lengths}->{$readLength}->{errorRate};
                $failures->{errorRate}->{'res'} = $result->[$resultMapping->{'ErrRate'}];
        }
	
	#Return failures and warnings
	return ($failures ,$warnings);
}

=pod

=head1 FUNCTIONS

=head2  checkPooling()

 Title   : checkPooling
 Usage   : $qc->checkPooling($qcRequirements, $passReq, $warningReq, $result, $resultMapping, $failures, $warnings)
 Function: Validate that each sample have recieved enough data or that the pooling requirements should be ignored.
 Example :
 Returns : ($failures ,$warnings) an array containing hash reference result for failures and warnings 
 Args    : the part of the QC requirements that match the used runParameters
	   hash which define if standard requirements should be overridden
	   hash which define if warnings should be sent out.
	   hash reference that contain result that have been imported from a quickReport.
	   mapping object used to extract correct columns from the result hash.
	   hash with already failed parameters.
           hash with parameters that will have warnings.

=cut

sub checkPooling{
	my $self = shift;

	my $qcRequirements = shift;
	my $passReq = shift;
	my $warningReq = shift;

	my $result = shift;
	my $resultMapping = shift;

	my $failures = shift;
	my $warnings = shift;

	#First check if pooling should be ignored for the entire run.
	unless(defined($qcRequirements->{overridePoolingRequirement}) && $qcRequirements->{overridePoolingRequirement} eq 1) {
		#Calculate min data for each sample.
		my @samples = split(/,[ ]/,$result->[$resultMapping->{'Sample Fractions'}]);
		my $numberOfSamples = @samples;
		my $minData = $qcRequirements->{'numberOfCluster'} / 2 / $numberOfSamples;
		#Validate that each sample have enough data (or have been defined to ignore pooling values)
		foreach(@samples) {
			$_ =~ s/^[ ]+//;
			my @info = split(/:/,$_);
			#First check if pooling value should be ignored.
			if((!(exists($passReq->{overridePoolingRequirement}) && $passReq->{overridePoolingRequirement}) == 1) && 
			     #Check if the pool haven't recieved enough data.
                             ($info[0]/100*$result->[$resultMapping->{'ReadsPF (M)'}]) < $minData)
			{
				print "Sample $info[1] haven't received sufficient amount data: " . ($info[0]/100*$result->[$resultMapping->{'ReadsPF (M)'}]) . " ($minData)\n" if($self->{VERBOSE});
				#Check if a warning should be saved instead of a failure
				if(exists($warningReq->{overridePoolingRequirement}) && $warningReq->{overridePoolingRequirement} == 1) {
					$warnings->{sampleFraction}->{$info[1]}->{'req'} = $minData;
        	        		$warnings->{sampleFraction}->{$info[1]}->{'res'} = $info[0]/100*$result->[$resultMapping->{'ReadsPF (M)'}];
				}
				else
				{
					#Save failed values.
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

	#Return failures and warnings
	return ($failures ,$warnings);
}
