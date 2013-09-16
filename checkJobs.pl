#!/usr/bin/perl -w

use strict;
use Getopt::Long;

=pod

=head1 NAME

checkJobs.pl - Checks the status of one or more jobs run on the cluster Kalkyl

=head1 SYNOPSIS

 sisyphus.pl -help|-man
 sisyphus.pl jobid1 <jobid2 ...>

=head1 OPTIONS

=over 4

=item -h|-help

prints out a brief help text.

=item -m|-man

Opens the manpage.

=back

=head1 DESCRIPTION

Takes a list of slurm job ids and checks their status.
Exits with 0 if all jobs have completed successfully.
Exits with 2 if any job is still running
Exits with 1 if any job failed

=cut

# From the squeue man page
#       -t <state_list>, --states=<state_list>
#              Specify the states of jobs to view.  Accepts a  comma  sepa-
#              rated  list  of  state names or "all". If "all" is specified
#              then jobs of all states will be reported.  If  no  state  is
#              specified  then  pending,  running,  and completing jobs are
#              reported. Valid states (in both extended and  compact  form)
#              include:  PENDING (PD), RUNNING (R), SUSPENDED (S), COMPLET-
#              ING (CG), COMPLETED (CD), CONFIGURING (CF), CANCELLED  (CA),
#              FAILED  (F),  TIMEOUT  (TO),  and  NODE_FAIL  (NF). Note the
#              <state_list> supplied is case insensitve ("pd" and "PD" work
#              the  same).   See the JOB STATE CODES section below for more
#              information.
# %t  Job  state,  compact form: PD (pending), R (running), CA
#                  (cancelled), CF(configuring), CG (completing), CD  (com-
#                  pleted),  F  (failed),  TO (timeout), and NF (node fail-
#                  ure).  See the JOB STATE CODES section  below  for  more
#                  information.  (Valid for jobs only)

my $jobs = join ',', @ARGV;
my $squeueProg = "/usr/bin/squeue";

my %states = (PD => sub{exit 2},
	      R  => sub{exit 2},
	      S  => sub{exit 2},
	      CG => sub{exit 2},
	      CF => sub{exit 2},
	      CA => sub{exit 1},
	      F  => sub{exit 1},
	      TO  => sub{exit 1},
	      NF  => sub{exit 1},
	      CD => sub{return 1});

# Ask slurm for info about the jobs
open(SQ, "$squeueProg --format='%.7i %.2t' -t PENDING,RUNNING,SUSPENDED,COMPLETED,CANCELLED,FAILED,TIMEOUT,NODE_FAIL,COMPLETING -j $jobs|")
  or die "Failed to open pipe from $squeueProg: $!\n";
while(<SQ>){
    my @r = split /\s+/, $_;
    if($r[0]=~ m/^\d+$/){
	&{$states{$r[1]}};
    }
}

