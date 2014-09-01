#!/usr/bin/perl -w

use strict;
use FindBin;                # Find the script location
use lib "$FindBin::Bin/lib";# Add the script libdir to libs
use Molmed::Sisyphus::Common;

my $dir = shift || die "Directory path to gzip required\n";
my $md5file = shift || die "MD5 file to verify archive against required\n";
my $destination = shift || "$dir.tar.gz";

# Set the number of threads to half the number of available procs (used by pigz)
my $threads = `cat /proc/cpuinfo |grep "^processor"|wc -l`;
$threads = $threads/2;

# Create a Common object to handle the operations
my $obj = Molmed::Sisyphus::Common->new(PATH=>$dir);
$obj->{THREADS} = $threads;

# Do the tarballing, including verifying archive and removing original folder
my $tarball = $obj->gzipFolder($obj->{PATH},$md5file);
rename($tarball,$destination) or die "Failed to rename $tarball to $destination";

# Calculate the md5sum of the gzip file and dump it to stdout
my $md5 = $obj->getMd5($destination);
print("$md5  $destination\n");
