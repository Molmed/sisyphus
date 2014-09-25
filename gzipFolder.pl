#!/usr/bin/perl -w

use strict;
use FindBin;                # Find the script location
use File::Basename;
use File::Copy;
use Cwd qw(abs_path);
use List::Util qw( max );
use lib "$FindBin::Bin/lib";# Add the script libdir to libs
use Molmed::Sisyphus::Common;

my $dir = shift || die "Directory path to gzip required\n";
my $md5file = shift || die "MD5 file to verify archive against required\n";

# Set the number of threads to half the number of available procs (used by pigz)
my $threads = `cat /proc/cpuinfo |grep "^processor"|wc -l`;
$threads = max(1,$threads/2);

# Create a Common object to handle the operations
my $obj = Molmed::Sisyphus::Common->new(PATH=>dirname($dir));
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

# Calculate the md5sum of the gzip file
my $md5 = $obj->getMd5($tarball);

# Clean up the generated md5 files
if ($md5bak) {
	move($md5bak,$sismd5) or warn "Failed to restore backup $md5bak to $sismd5\n";
}
else {
	unlink($sismd5) or warn "Failed to remove generated $sismd5\n";
	rmdir(dirname($sismd5)) or warn dirname($sismd5) . " was not empty, could not remove\n";
}

# Print out the md5 of the generated tarball
print("$md5  $tarball\n");
