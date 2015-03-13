#!/usr/bin/perl -w

use FindBin;                # Find the script location
use lib "$FindBin::Bin/lib";
use Getopt::Long;
use Molmed::Sisyphus::Common;
use Molmed::Sisyphus::QCRequirementValidation;
use File::Basename;

use strict;
use warnings;

use constant FAILED_QC_REQUIREMENTS => 101;

my $sender = 'seq@medsci.uu.se';
my $mail = undef;
my $rfPath = undef;
my $qcFile = undef;
my $qcReport = undef;
our $debug = 0;
my ($help,$man) = (0,0);


GetOptions('runfolder=s' => \$rfPath, 
	    'mail=s' => \$mail,
	    'sender=s' => \$sender,
	    'qcFile=s' => \$qcFile,
	    'qcReport=s' => \$qcReport,
	    'debug' => \$debug,
) or pod2usage(-verbose => 0);

pod2usage(-verbose => 1)  if ($help);
pod2usage(-verbose => 2)  if ($man);

$qcReport = "$rfPath/quickReport.txt" if(!defined($qcReport));

$qcFile = "$rfPath/sisyphus_qc.xml" if(!defined($qcFile));


my $sisyphus = Molmed::Sisyphus::Common->new(PATH=>$rfPath, DEBUG=>$debug);

$sisyphus->getRunInfo();
$sisyphus->runParameters();

my $qc = Molmed::Sisyphus::QCRequirementValidation->new(DEBUG=>$debug);

my $loadQCconfig = $qc->loadQCRequirement($qcFile);
my $result = 0;
my $warning = 0;
if($loadQCconfig != $qc->ERROR_READING_QC_CRITERIAS) {
	($result, $warning) = $qc->validateSequenceRun($sisyphus,$qcReport);

	if(!defined($result) && !defined($warning))
	{
		exit 0;
	}
}

if(defined($result)) {
	open FAILED_QC, "> $rfPath/failedQc.html" or die "Couldn't create file $rfPath/failedQC.html\n";
	print FAILED_QC '<html><body>' . "\n";

	if($loadQCconfig == $qc->ERROR_READING_QC_CRITERIAS) {
		print FAILED_QC "<h2>Couldn't read $qcFile</2>\n";
		print FAILED_QC "File: $qcFile";
	} elsif(ref($result) eq 'HASH') {
		foreach my $lane (keys %{$result}) {
			print FAILED_QC "<h2>Lane $lane failed the following QC-criteria:</h2>\n";
			print STDERR "Lane $lane failed the following QC-criteria:\n";
			foreach my $read (keys %{$result->{$lane}}) {
				print FAILED_QC "<ul>\n\t<li>Read $read:\n\t\t<ul>\n";
				print STDERR "\tRead $read:\n";
				foreach my $criteria (keys %{$result->{$lane}->{$read}}) {
					if($criteria eq 'sampleFraction') {
						print FAILED_QC "\t\t\t\t<li>$criteria:\n\t\t\t\t<ul>\n";
						print STDERR"\t\t$criteria:\n";
						foreach my $sample (
								sort {$result->{$lane}->{$read}->{$criteria}->{$a}->{res} <=> $result->{$lane}->{$read}->{$criteria}->{$b}->{res}} 
								keys  %{$result->{$lane}->{$read}->{$criteria}}) {
							printf FAILED_QC "\t\t\t\t\t\t<li>%s: %.3f (%.3f)</li>\n", $sample, $result->{$lane}->{$read}->{$criteria}->{$sample}->{res}, $result->{$lane}->{$read}->{$criteria}->{$sample}->{req};
							printf STDERR "\t\t\t\t%s: %.3f (%.3f)\n", $sample, $result->{$lane}->{$read}->{$criteria}->{$sample}->{res}, $result->{$lane}->{$read}->{$criteria}->{$sample}->{req};
						}
						print FAILED_QC "\t\t\t\t\t</ul>\n\t\t\t</li>\n";
					}
					else {
						print FAILED_QC "\t\t\t<li>$criteria\t$result->{$lane}->{$read}->{$criteria}->{res} ($result->{$lane}->{$read}->{$criteria}->{req})</li>\n";
						print STDERR "\t\t$criteria\t$result->{$lane}->{$read}->{$criteria}->{res} ($result->{$lane}->{$read}->{$criteria}->{req})\n";
					}
				}
				print FAILED_QC "\t\t</ul>\n\t</li>\n</ul>\n";
			}
		}
	} elsif($result == $qc->RUN_TYPE_NOT_FOUND) {
		print STDERR "Couldn't match the used run parameters (machine/reagent/runMode) with a specified QC criteria!\n";
		print FAILED_QC "<h2>Missing QC criterias</2>\n";
		print FAILED_QC "Couldn't match the used run parameters (machine/reagent/runMode) with a specified QC criteria!\n";
	} elsif($result == $qc->SEQUENCED_LENGTH_NOT_FOUND) {
		print STDERR "The used read length and machine/reagent/runMode combination couldn't be found in the specified QC criteria!\n";
		print FAILED_QC "<h2>Missing QC criterias</2>\n";
		print FAILED_QC "The used read length and machine/reagent/runMode combination couldn't be found in the specified QC criteria!\n";
	} elsif($result == $qc->ERROR_READING_QUICKREPORT){
		print STDERR "Couldn't read quickReport.txt: $rfPath/quickReport.txt!\n";
		print FAILED_QC "<h2>Couldn't read quickReport.txt</2>\n";
		print FAILED_QC "File: $rfPath/quickReport.txt\n";
	} elsif($result == SEQUENCED_UNIDENTIFIED_NOT_FOUND) {
		print STDERR "Couldn't find any criterias for unidentified using the supplied machine/reagent/runMode combination!\n";
		print FAILED_QC "<h2>Missing QC criterias</2>\n";
		print FAILED_QC "Couldn't find any criterias for unidentified using the supplied machine/reagent/runMode combination!\n";
	} elsif($result == SEQUENCED_NUMBER_OF_CLUSTERS_NOT_FOUND) {
		print STDERR "Couldn't find any criterias for number of clusters using the supplied machine/reagent/runMode combination!\n";
		print FAILED_QC "<h2>Missing QC criterias</2>\n";
		print FAILED_QC "Couldn't find any criterias for number of clusters using the supplied machine/reagent/runMode combination!\n";
	} elsif($result == SEQUENCED_Q30_NOT_FOUND) {
		print STDERR "Couldn't find any criterias for Q30 using the supplied machine/reagent/runMode/length combination!\n";
		print FAILED_QC "<h2>Missing QC criterias</2>\n";
		print FAILED_QC "Couldn't find any criterias for Q30 using the supplied machine/reagent/runMode/length combination!\n";
	} elsif($result == SEQUENCED_ERROR_RATE_NOT_FOUND)) {
		print STDERR "Couldn't find any criterias for error rate using the supplied machine/reagent/runMode/length combination!\n";
		print FAILED_QC "<h2>Missing QC criterias</2>\n";
		print FAILED_QC "Couldn't find any criterias for error rate using the supplied machine/reagent/runMode/length combination!\n";
	} else {
		die "Unhandled case!\n";
	}
	print FAILED_QC "</body></html>\n";
	close(FAILED_QC);
}

if(defined($warning)) {
	open WARNING_QC, "> $rfPath/warningQc.html" or die "Couldn't create file $rfPath/warningQC.html\n";
	print WARNING_QC '<html><body>' . "\n";
	if(ref($warning) eq 'HASH') {
		foreach my $lane (keys %{$warning}) {
			print WARNING_QC "<h2>Lane $lane warning for the following QC-criteria:</h2>\n";
			print STDERR "Lane $lane warning for the following QC-criteria:\n";
			foreach my $read (keys %{$warning->{$lane}}) {
				print WARNING_QC "<ul>\n\t<li>Read $read:\n\t\t<ul>\n";
				print STDERR "\tRead $read:\n";
				foreach my $criteria (keys %{$warning->{$lane}->{$read}}) {
					if($criteria eq 'sampleFraction') {
						print WARNING_QC "\t\t\t\t<li>$criteria:\n\t\t\t\t<ul>\n";
						print STDERR"\t\t$criteria:\n";
						foreach my $sample (
								sort {$warning->{$lane}->{$read}->{$criteria}->{$a}->{res} <=> $warning->{$lane}->{$read}->{$criteria}->{$b}->{res}} 
								keys  %{$warning->{$lane}->{$read}->{$criteria}}) {
							printf WARNING_QC "\t\t\t\t\t\t<li>%s: %.3f (%.3f)</li>\n", $sample, $warning->{$lane}->{$read}->{$criteria}->{$sample}->{res}, $warning->{$lane}->{$read}->{$criteria}->{$sample}->{req};
							printf STDERR "\t\t\t\t%s: %.3f (%.3f)\n", $sample, $warning->{$lane}->{$read}->{$criteria}->{$sample}->{res}, $warning->{$lane}->{$read}->{$criteria}->{$sample}->{req};
						}
						print WARNING_QC "\t\t\t\t\t</ul>\n\t\t\t</li>\n";
					}
					else {
						print WARNING_QC "\t\t\t<li>$criteria\t$warning->{$lane}->{$read}->{$criteria}->{res} ($warning->{$lane}->{$read}->{$criteria}->{req})</li>\n";
						print STDERR "\t\t$criteria\t$warning->{$lane}->{$read}->{$criteria}->{res} ($warning->{$lane}->{$read}->{$criteria}->{req})\n";
					}
				}
				print WARNING_QC "\t\t</ul>\n\t</li>\n</ul>\n";
			}
		}
	} 

	print WARNING_QC "</body></html>\n";
	close(WARNING_QC);
}
sub sendMail {
	my $mail = shift;
	my $rfPath = shift;
	my $file = shift;
	my $sender = shift;
	my $subject = shift;

	open(my $repFh, '<', "$rfPath/$file");
    	my $msg = "";
	while(<$repFh>){
		$msg .= $_;
	}
	close($repFh);
	require Net::SMTP;
	#Create a new object with 'new'.
	my $smtp = Net::SMTP->new("smtp.uu.se");
	#Send the MAIL command to the server.
	$smtp->mail($sender);
	#Send the server the 'Mail To' address.
	$smtp->to($mail);
	#Start the message.
	$smtp->data();
	#Send the message.
	$smtp->datasend("From: $sender\n");
	$smtp->datasend("To: $mail\n");
	$smtp->datasend("Subject: $subject " . basename($rfPath) . "\n");
	$smtp->datasend("MIME-Version: 1.0\n");
	$smtp->datasend("Content-Type: text/html; charset=us-ascii\n");
	$smtp->datasend("\n");
	$smtp->datasend("$msg\n\n");
	#End the message.
	print $msg;
	$smtp->dataend();
	#Close the connection to your server.
	$smtp->quit();
}

if(defined $mail && $mail =~ m/\w\@\w/){
	if(defined($result)) {	
     		my $subject = '[Sisyphus] [FAILED QC]:';
		my $file = "failedQc.html";
		sendMail($mail, $rfPath , $file, $sender, $subject);
	}
	if(defined($warning)) {
		my $subject = '[Sisyphus] [WARNING QC]:';
                my $file = "warningQc.html";
                sendMail($mail, $rfPath , $file, $sender, $subject);
	}
}

exit 1;

