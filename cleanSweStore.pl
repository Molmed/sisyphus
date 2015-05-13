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
 cleanSweStore.pl -projects <file with list of projects> [-execute]

=head1 OPTIONS

=over 4

=item -h|-help

prints out a brief help text.

=item -m|-man

Opens the manpage.

=item -runfolder

Path to a file containing all projects that should be removed from SweStore.

Format, runfolder and projectID seperated by tab: runfoldername1	projectId1

=item -execute

Use flag when you want to perform the deletion. If not set, the script
will only validate that the provided projects can be found and also
specify if the entire runfolder will be deleted or just a subset
of the projects.

=back

=cut

my ($project, $debug, $execute);

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
	   'projects=s' => \$project, 
	   'execute!' => \$execute,
    	   'debug' => \$debug,
      	    ) or pod2usage(-verbose => 0);

pod2usage(-verbose => 1)  if ($help);
pod2usage(-verbose => 2)  if ($man);
unless (defined($project)) {
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
open PROJECTS, $project or die "Couldn't open project file: $project!";
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

open REMOVED, "> removedFromSweStore.$timestamp.log" or die "Couldn't open output file: removedFromSweStore.$timestamp.log!\n";
open SAVED, "> leftOnSweStore.$timestamp.log" or die "Couldn't open output file: leftOnSweStore.$timestamp.log!\n";

print "Cleaning swestore!\n";
#
# Remove the provided projects from SweStore
#
foreach my $runfolder (keys %{$dataToClean}) { # Process each runfolder 
	my ($year,$month,$day) = ($runfolder =~ m/^(\d{2})(\d{2})(\d{2})_[A-Z0-9]+_[0-9]+_[A-Z0-9]/);
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
		if(/^[ ]*C-/) {
			my ($project) = ($_ =~ m/.*\/(.*)$/);
			$project =~ s/\s+//;
			$foundProjects{$project} = 1;
		}
	}
	# Calculate number of projects found
	my $numFoundProjects = (keys %foundProjects);
	# Calculate number of projects that have been provided
	my $numRemoveProjects = (keys %{$dataToClean->{$runfolder}});
	#Make sure that the provided projects exist on SweStore, if not terminate the script.
	foreach my $key (keys %{$dataToClean->{$runfolder}}) {
		if(!exists($foundProjects{$key})) {
			die "Couldn't find project $key on swestore: /ssUppnexZone/proj/a2009002/20" . $year . '-' . $month . '/' . $runfolder . "/Project\n";
		}
	}
	
	if($numFoundProjects < $numRemoveProjects) { #Cannot remove more projects than found on SweStore
		die "You can't remove more projects than what exists, found $numFoundProjects, removing $numRemoveProjects!\n";
	} elsif($numFoundProjects > $numRemoveProjects) { # Remove subset of projects found on SweStore 
		if($execute) { #Perform deletion
			foreach my $key (keys %{$dataToClean->{$runfolder}}) {
				qx(irm -f $swestorePath/20$year-$month/$runfolder/Projects/$key);
				print REMOVED "$swestorePath/20$year-$month/$runfolder/Projects/$key\n";
				delete $foundProjects{$key};
			}
			foreach my $key (keys %foundProjects) {
				print SAVED "$swestorePath/20$year-$month/$runfolder/Projects/$key\n";
			}
		}
		print("Removing a subset of the projects from $runfolder\n");
	} else { # Same number of folders in file as on SweStore, remove entire runfolder
		print "Removing runfolder $runfolder!\n";
		if($execute) { #Perform deletion
			qx(irm -f $swestorePath/20$year-$month/$runfolder);
			print REMOVED "$swestorePath/20$year-$month/$runfolder\n";
		}
	}
	
}
close(SAVED);
close(REMOVED)
