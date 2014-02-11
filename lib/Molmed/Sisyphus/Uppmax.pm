package Molmed::Sisyphus::Uppmax;

use strict;
use Molmed::Sisyphus::Libpath;
use Carp;

our $AUTOLOAD;

=pod

=head1 NAME

Molmed::Sisyphus::Uppmax - Common functions for use at the UPPMAX clusters

=head1 SYNOPSIS

use Molmed::Sisyphus::Uppmax;

my $uppmax =  Molmed::Sisyphus::Uppmax->new(
  DEBUG=>$debug
 );

=head1 CONSTRUCTORS

=head2 new()

=over 4

=item DEBUG

Print debug information.

=back

=cut

sub new{
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = {@_};

    bless ($self, $class);
    return $self;
}

=pod

=head1 FUNCTIONS

=head2 checkJobs()

 Title   : checkJobs
 Usage   : $uppmax->checkJobs(@jobids)
 Function: Checks the status of the listed slurm job ids.
 Example :
 Returns : 1 if all jobs are completed
           0 if jobs are still waiting/runnning
          -1 if any of the jobs have failed
 Args    : A list of slurm job ids to check

=cut

sub checkJobs{
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
    my $self;
    if(ref $_[0]){
	$self = shift @_;
    }
    my $jobs = join ',', @_;
    my $squeueProg = "/usr/bin/squeue";

    my %states = (PD => 0, # pending
		  R  => 0, # running
		  S  => 0, # suspended
		  CG => 0, # completing
		  CF => 0, # configuring
		  CA => -1, # cancelled
		  F  => -1, # failed
		  TO  => -1, # timeout
		  NF  => -1, # node failure
		  CD => 1); # completed

    # Ask slurm for info about the jobs
    open(my $sqFh, "$squeueProg --format='%.7i %.2t' -t PENDING,RUNNING,SUSPENDED,COMPLETED,CANCELLED,FAILED,TIMEOUT,NODE_FAIL,COMPLETING -j $jobs|")
	or die "Failed to open pipe from $squeueProg: $!\n";
    while(<$sqFh>){
	my @r = split /\s+/, $_;
	if($r[0]=~ m/^\d+$/){
	    unless($states{$r[1]}==1){
		close($sqFh);
		return $states{$r[1]};
	    }
	}
    }
    close($sqFh);
    return 1;
}

=head2 startJob()

 Title   : startJob
 Usage   : $uppmax->startJob($command,$wd)
 Function: submits a new batch job to slurm
 Example :
 Returns : returns the slurm job id for the new job
 Args    : the command to submit and, optionally, a directory to run the command from

=cut


=head2 sbatchHeader()

 Title   : startJob
 Usage   : $uppmax->startJob($command,$wd)
 Function: submits a new batch job to slurm
 Example :
 Returns : returns the slurm job id for the new job
 Args    : the command to submit and, optionally, a directory to run the command from

=cut

1;
