#!/usr/bin/perl -w

use strict;
use Digest::MD5 qw(md5_hex);

my $rf = shift || die "Directory name required\n";
my %seen;

while(<>){
    next unless(m/^$rf/);
    next if(m/ -> /); # Skip symlinks
    chomp;
    my $file = $_;
    unless(-e $file){
	warn "$file not found\n";
	next;
    }
    next unless(-f $file); # Skip directories

    # Some files might occure multiple times if the rsync has been interrupted and resumed
    next if($seen{$file});

    $seen{$file} = 1;
    open(my $fh, $file) || die "Failed to open $file: $!\n";
    binmode($fh);
    my $md5 = Digest::MD5->new->addfile($fh);
    close($fh);
    print $md5->hexdigest, "  $file\n";
}

