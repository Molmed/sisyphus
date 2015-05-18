#!/usr/bin/perl -w
##
use Getopt::Long;
use Pod::Usage;

use strict;
use warnings;

=pod

=head1 NAME

cleanSweStore.pl - clean swestore from old projects

=head1 SYNOPSIS

 cleanSweStore.pl -help|-man
 cleanSweStore.pl -projectFile <file with a list of projects> [-execute]

=head1 OPTIONS

=over 4

=item -h|-help

prints out a brief help text.

=item -m|-man

Opens the manpage.

=item -projectFile

Path to a file containing all projects that should be removed from SweStore.
The file should contain two columns per row where the first column is the
runfoldername and the second column is the projecID. One row per project must 
be created if a runfolder contain multiple projects that should be removed.

=item -execute

Use flag when you want to perform the deletion. If not set, the script
will only validate that the provided projects can be found and also
specify if the entire runfolder will be deleted or just a subset
of the projects.

=back

=cut

my ($inputProjectFile, $debug, $execute);

my $swestorePath = "/ssUppnexZone/proj/a2009002";

my ($help,$man) = (0,0);

# Project input file should have the following format
# runfoldername1	projectId1
# runfoldername1	projectId2
# runfoldername2	projectId3
# ...
# runfoldernameN\tprojectIdN
#

GetOptions('help|?'=>\$help,
	   'man'=>\$man,
	   'projectFile=s' => \$inputProjectFile, 
	   'execute!' => \$execute,
    	   'debug' => \$debug,
      	    ) or pod2usage(-verbose => 0);

pod2usage(-verbose => 1)  if ($help);
pod2usage(-verbose => 2)  if ($man);
unless (defined($inputProjectFile)) {
	print "You must provide a list of projects to clean, format: runfoldername\tprojectid\n";
	pod2usage(-verbose => 1);
	exit;
}

#
# Save all runfolder and the associated projects into a hash structure
#
# var => {
#	runfolder_name1 => {
#		projId1 => 1,
#		projId2 => 1,
#	}
#	runfolder_name2 => {
#		projId3 => 1,
#	        projId4 => 1,
#	}#
# }
#
open PROJECTS, $inputProjectFile or die "Couldn't open project file: $inputProjectFile!";
my $dataToClean;
while(<PROJECTS>){
	if(!/^#/) {
		chomp;
		my ($runfolder,$project) = split(/\t/, $_);
		$project =~ s/\s+//;
		$dataToClean->{$runfolder}->{$project} = 1;
	}
}
close(PROJECTS);
my $timestamp = time;

my ($REMOVED, $NOTREMOVED,$LEFTONSWESTORE);

#do not want to load, no idea why
#qx(module load irods);

print "Cleaning swestore!\n";

if($execute) {
	open $REMOVED, "> removedFromSweStore.$timestamp.log" or die "Couldn't open output file: removedFromSweStore.$timestamp.log!\n";
	open $NOTREMOVED, "> notRemovedFromSweStore.$timestamp.log" or die "Couldn't open output file: notRemovedFromSweStore.$timestamp.log!\n";
	open $LEFTONSWESTORE, "> leftOnSweStore.$timestamp.log" or die "Couldn't open output file: leftOnSweStore.$timestamp.log!\n";
}

my $counterRemoved = 0;
my $counterNotRemoved = 0;
#
# Remove the provided projects from SweStore
#
foreach my $runfolder (keys %{$dataToClean}) { # Process each runfolder 
	my ($year,$month,$day) = ($runfolder =~ m/^(\d{2})(\d{2})(\d{2})_[A-Z0-9-]+_[0-9]+_[A-Z0-9-]+/);
	# Find each  stored project at SweStore, for the specified runfolder
	my $projects = qx(ils $swestorePath/20$year-$month/$runfolder/Projects/);
	#Result from ils
	#
	# ils /ssUppnexZone/proj/a2009002/2014-06/140605_D00118_0144_AC44G7ACXX/Projects/
	# /ssUppnexZone/proj/a2009002/2014-06/140605_D00118_0144_AC44G7ACXX/Projects:
	# C- /ssUppnexZone/proj/a2009002/2014-06/140605_D00118_0144_AC44G7ACXX/Projects/MK-0401
	# C- /ssUppnexZone/proj/a2009002/2014-06/140605_D00118_0144_AC44G7ACXX/Projects/MK-0429
	#
	my @projectPath = split(/\n/,$projects);
	my %foundProjects;
	# Only extract information from lines containing "C-"
	foreach (@projectPath) {
		if(/^\s*C-/) {
			my ($project) = ($_ =~ m/.*\/([A-Z]{2}-?[0-9]{2,4})$/);
			if($project) {
				$project =~ s/\s+//;
				$foundProjects{$project} = 1;
			}
		}
	}
	#Remove projects from SweStore
	foreach my $key (keys %{$dataToClean->{$runfolder}}) {
		if(exists($foundProjects{$key})) {
			print("Removing project $key from $runfolder\n");
			if($execute) { #Perform deletion
				qx(irm -rf $swestorePath/20$year-$month/$runfolder/Projects/$key);
				print $REMOVED "$swestorePath/20$year-$month/$runfolder/Projects/$key\n";
				delete $foundProjects{$key};
			}
			$counterRemoved++;
			delete $dataToClean->{$key};
		} else {
			print("Couldn't find project $key for $runfolder\n");
			$counterNotRemoved++;
			if($execute) { #Perform deletion
                                print $NOTREMOVED "$runfolder\t$key\n";
                        }
		}
	}
	foreach my $key (keys %foundProjects) {
		if($execute) { #Perform deletion
			print $LEFTONSWESTORE "$runfolder\t$key\n";
		}
	}

					
}
if($execute) {
	close($NOTREMOVED);
	close($REMOVED);
	close($LEFTONSWESTORE);
}

print "Cleaning completed:\n\t$counterRemoved projects removed\n\t$counterNotRemoved couldn't be removed\n";
