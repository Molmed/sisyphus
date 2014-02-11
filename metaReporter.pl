#!/usr/bin/perl -w

use FindBin;                # Find the script location
use lib "$FindBin::Bin/lib";# Add the script libdir to libs
use Molmed::Sisyphus::Libpath;

use strict;
use XML::Simple;
use XML::LibXSLT;
use XML::LibXML;
use File::Basename;
use Data::Dumper;

=pod

=head1 NAME

metaReporter.pl - Create a meta report on a project from multiple runs

=head1 SYNOPSIS

 metaReporter.pl -help|-man
 cat list.txt | metaReporter.pl rootdir project > report.xml

=head1 OPTIONS

=over 4

=item -h|-help

prints out a brief help text.

=item -m|-man

Opens the manpage.

=item rootdir

The runfolder-containing directory

=item project

The name of the project for which to compile the report

=item list.txt

A list of flowcell id and lane, one per row, which to include in the report.

=back

=head1 DESCRIPTION

Creates an xml and html report for all lanes and samples in the specified project for the specified flowcells.

=cut


my %xmlfiles;
my $rootDir = shift;
my $projId = shift;

opendir(my $dFh, $rootDir) or die;
foreach my $dir (grep /^[^\.]/, readdir($dFh)){
    next unless(-d "$rootDir/$dir");
    if(-e "$rootDir/$dir/Summary/$projId/report.xml"
       || -e "$rootDir/$dir/Summary/$projId/report.xml.gz"){
	if(-e "$rootDir/$dir/Summary/$projId/report.xml.gz"){
	    system("gunzip $rootDir/$dir/Summary/$projId/report.xml");
	}
	if($dir =~ m/\d+_[^_]+_\d+_[AB](\w+)/){
	    $xmlfiles{$1} = "$rootDir/$dir/Summary/$projId/report.xml";
	}else{
	    die "Failed to get fcid from '$dir'\n";
	}
#    }else{
#	die "Failed to find '$rootDir/$dir/Summary/$projId/report.xml'";
    }
}

my $metaLane = {};
my $metaSample = {};

while(<>){
    chomp;
    my($fcid, $laneId) = split /\s+/, $_;
    die "no xml for $fcid\n" unless(exists $xmlfiles{$fcid});
    my $xml = XMLin($xmlfiles{$fcid}, ForceArray=>['Sample', 'Read','Lane','Tag']);
    foreach my $lane (@{$xml->{LaneMetrics}->{Lane}}){
#	print Dumper $lane;
#	exit;
	if($lane->{Id} == $laneId){
	    $lane->{Num} = $laneId;
	    $lane->{Id} = $fcid . "_L" . $laneId;
	    $lane->{fcid} = $fcid;

	    my $projDir = dirname($xmlfiles{$fcid});
	    foreach my $read (@{$lane->{Read}}){
		foreach my $key (keys %{$read}){
		    if($key =~ m/Plot/ && $read->{$key}=~m/Plot/){
			my $old = $read->{$key};
			$read->{$key} =~ s:^Plots:Plots/$fcid:;
			my $dir = dirname($read->{$key});
			unless(-e $dir){
			    system('mkdir', '-p', $dir)==0 or die;
			}
			if(-e "$projDir/$old"){
			    system('cp', "$projDir/$old", $dir)==0 or die;
			}
		    }
		}
	    }
	    push @{$metaLane->{Lane}}, $lane;
	}
    }


    foreach my $sample (@{$xml->{SampleMetrics}->{Sample}}){
	my $samId = $sample->{Id};
#	$sample->{fcid}=$fcid;

#	print Dumper($sample);
#	exit;

	my $projDir = dirname($xmlfiles{$fcid});
	foreach my $tag (@{$sample->{Tag}}){
#	    print Dumper($tag->{Lane});
#	    exit;
	    foreach my $lane (@{$tag->{Lane}}){
#		print Dumper($lane);
#		exit;
		if($lane->{Id} == $laneId){
		    $lane->{Num} = $laneId;
		    $lane->{Id} = $fcid . "_L" . $laneId;
		    $lane->{fcid} = $fcid;
		    $lane->{Tag} = $tag->{Id};

		    foreach my $read (@{$lane->{Read}}){
#			delete($read->{Q30PlotThumb});
#			delete($read->{Q30Plot});
			foreach my $key (keys %{$read}){
			    if($key =~ m/Plot/ && $read->{$key}=~m/Plot/){
				my $old = $read->{$key};
				$read->{$key} =~ s:^Plots:Plots/$fcid:;
				my $dir = dirname($read->{$key});
				unless(-e $dir){
				    system('mkdir', '-p', $dir)==0 or die;
				}
				if(-e "$projDir/$old"){
				    system('cp', "$projDir/$old", $dir)==0 or die;
				}
			    }
			}
		    }
		    push @{$metaSample->{Sample}->{$sample->{Id}}->{Lane}}, $lane;
		}
	    }
	}
    }
}

my $xs = XML::Simple->new(RootName=>undef);

print STDOUT q(<?xml version="1.0"?>
<?xml-stylesheet type="text/xsl" href="report.xsl"?>
<SequencingReport>
<MetaData>
<Project>) . $projId . q(</Project>
</MetaData>
);

print STDOUT $xs->XMLout($metaLane, RootName=>'LaneMetrics', KeyAttr => {Lane => 'Id'});
print STDOUT $xs->XMLout($metaSample, RootName=>'SampleMetrics', KeyAttr => {Sample => 'Id'});
print STDOUT "</SequencingReport>\n";

