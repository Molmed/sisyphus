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

my $sender = undef;
my $mail = undef;
my $rfPath = undef;
our $debug = 0;
my ($help,$man) = (0,0);



GetOptions('runfolder=s' => \$rfPath, 
	    'mail=s' => \$mail,
	    'sender=s' => \$sender,
	    'debug' => \$debug,
) or pod2usage(-verbose => 0);

pod2usage(-verbose => 1)  if ($help);
pod2usage(-verbose => 2)  if ($man);

my $sisyphus = Molmed::Sisyphus::Common->new(PATH=>$rfPath, DEBUG=>$debug);

$sisyphus->getRunInfo();
$sisyphus->runParameters();

my $qc = QCRequirementValidation->new(DEBUG=>$debug);
my $file = "$rfPath/sisyphus_qc.xml";
$qc->loadQCRequirement($file);
my $result = $qc->validateSequenceRun($sisyphus,"$rfPath/quickReport.txt");

if(!defined($result))
{
	exit 0;
}
else
{	
	open FAILED_QC, "> $rfPath/failedQc.html" or die "Couldn't create file $rfPath/failedQC.html\n";
	print FAILED_QC '<html><body>' . "\n";
	if(ref($result) eq 'HASH') {
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
		print FAILED_QC "</body></html>\n";

	} elsif($result == $qc->MACHINE_CHEMISTRY_NOT_FOUND) {
		print FAILED_QC "<h2>Missing QC criterias</2>\n";
		print FAILED_QC "Couldn't match the used run parameters (machine/reagent/runMode) with a specified QC criteria!";
	} elsif($result == $qc->SEQUENCED_LENGTH_NOT_FOUND) {
		print FAILED_QC "<h2>Missing QC criterias</2>\n";
		print FAILED_QC "The used read length and machine/reagent/runMode combination couldn't be found in the specified QC criteria!";
	} else {
		die "Unhandled case!\n";
	}
	close(FAILED_QC);

	if(defined $mail && $mail =~ m/\w\@\w/){
	    open(my $repFh, '<', "$rfPath/failedQc.html");
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
	    $smtp->datasend("Subject: FAILED QC: " . basename($rfPath) . "\n");
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
	exit 1;
}
