#!/usr/bin/perl -w

use strict;
use FindBin;                # Find the script location
use File::Basename;
use File::Copy;
use Cwd qw(abs_path);
use lib "$FindBin::Bin/lib";# Add the script libdir to libs
use Molmed::Sisyphus::Common;

my $dir = shift || die "Directory path to gzip required\n";
my $md5file = shift || die "MD5 file to verify archive against required\n";
my $destination = shift || dirname(abs_path($dir)) . "/" . basename($dir) . ".tar.gz";
my $force = shift || 0;

# Set the number of threads to half the number of available procs (used by pigz)
my $threads = `cat /proc/cpuinfo |grep "^processor"|wc -l`;
$threads = $threads/2;

# Verify that the destination does not already exist
if (-e $destination) {
	if ($force) {
		warn "$destination already exists, removing..\n";
		unlink($destination) or die "Failed to remove $destination\n";
	}
	else {
		die "$destination already exists\n";
	}
}

# Create a Common object to handle the operations
my $obj = Molmed::Sisyphus::Common->new(PATH=>dirname($dir), DEBUG => 1);
$obj->{THREADS} = $threads;

# If the sisyphus.md5 exists, make a backup before zipping, since that will modify it. If it doesn't exist, make sure to remove the created file once we're done
my $md5bak = undef;
my $sismd5 = $obj->{PATH} . "/MD5/sisyphus.md5"; 
if (-e $sismd5) {
	$md5bak = "$sismd5.bak";
	copy($sismd5,$md5bak) or die "Failed to make backup of $sismd5\n";
}

# Do the tarballing, including verifying archive and removing original folder
my $tarball = $obj->gzipFolder(basename($dir),$md5file);
unless(move($tarball,$destination)) {
	unlink($destination);
	die "Failed to rename $tarball to $destination\n";
}

# Calculate the md5sum of the gzip file
my $md5 = $obj->getMd5($destination, -noCache => 1);

# Clean up the generated md5 files
if ($md5bak) {
	move($md5bak,$sismd5) or warn "Failed to restore backup $md5bak to $sismd5\n";
}
else {
	unlink($sismd5) or warn "Failed to remove generated $sismd5\n";
	rmdir(dirname($sismd5)) or warn dirname($sismd5) . " was not empty, could not remove\n";
}

# Print out the md5 of the generated tarball
print("$md5  $destination\n");
