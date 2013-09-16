package Molmed::Sisyphus::Kalkyl::SlurmJob;

use strict;
use Carp;
use Molmed::Sisyphus::Common qw(mkpath);

our $AUTOLOAD;

=pod

=head1 NAME

Molmed::Sisyphus::Kalkyl::SlurmJob - Common functions for handling jobs at the UPPMAX kluster kalkyl

=head1 SYNOPSIS

use Molmed::Sisyphus::Kalkyl::SlurmJob;

my $job =  Molmed::Sisyphus::Kalkyl::SlurmJob->new(
  DEBUG=>$debug,    # bool
  SCRIPTDIR=>$scriptDir, # Directory for writing the script
  EXECDIR=>$wd,     # Directory from which to run the script
  NAME=>$jobName,   # Name of job, also used in script name
  PROJECT=>$projId, # project for resource allocation
  TIME=>$runTime,   # Maximum runtime, formatted as d-hh:mm:ss
  QOS=>$qos,        # Qos flag for higher priority (short,interact,seqver)
  PARTITION=>$partition, # core or node (or devel)
 );

=head1 CONSTRUCTORS

=head2 new()

Creates and returns a new SlurmJob object.

=over 4

=item SCRIPTDIR

Directory to which the batch script is written

=over 4

=item EXECDIR

Directory from which the batch script is executed

=over 4

=item NAME

Name of job, also used in script name

=over 4

=item PROJECT

UPPMAX project to use for resource allocation

=over 4

=item TIME

Maximum runtime, formatted as d-hh:mm:ss

=over 4

=item PARTITION

core, node or devel

=over 4

=item DEBUG

Print debug information.

=back

=cut

sub new{
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = {@_};

    foreach my $key (qw(SCRIPTDIR EXECDIR NAME PROJECT TIME PARTITION)){
	unless(exists $self->{$key}){
	    confess "new called without $key\n";
	}
    }

    $self->{_jobid}=0; # Not yet submitted
    $self->{_depend}=[];

    # Define a bash function for handling errors
    $self->{_body}= q(
check_errs()
{
  # Function. Parameter 1 is the return code
  # Para. 2 is text to display on failure.
  # Kill all child processes before exit.

  if [ "${1}" -ne "0" ]; then
    echo "ERROR # ${1} : ${2}"
    for job in `jobs -p`
    do
        kill -9 $job
    done
    exit ${1}
  fi
}

);

    bless ($self, $class);
    return $self;
}

=head1 FUNCTIONS

=head2 newDummy()

 Title   : newDummy
 Usage   : SlumJob->newDummy($jobid);
 Function: Creates a new SlurmJob object for an existing job that has already been submitted. This can then be used for dependencies.
 Example :
 Returns : New (dysfunctional) SlumJob object.
 Args    : A slurm job id which this object should represent.

=cut

sub newDummy{
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = {};
    $self->{_jobid}=shift;
    bless ($self, $class);
    return $self;
}

=head2 addCommand()

 Title   : addCommand
 Usage   : $job->addCommand($command, $errStr);
 Function: Adds a (bash) command to the body of the batch script
 Example :
 Returns : nothing
 Args    : A string of bash code and optionally an error message to display if the command failed

=cut

sub addCommand{
    my $self = shift;
    my $command = shift;
    my $errStr = shift || "FAILED";
    $self->{_body} .= "\n" . $command . "\n" . 'check_errs $? "' . $errStr . '"' . "\n";
}

=head2 addCode()

 Title   : addCode
 Usage   : $job->addCode($command, $errString);
 Function: Adds a (bash) codestring to the body of the batch script
 Example :
 Returns : nothing
 Args    : An arbitrary string of bash code

=cut

sub addCode{
    my $self = shift;
    my $command = shift;
    $self->{_body} .= "\n" . $command . "\n";
}


=head2 addDep()

 Title   : addDep
 Usage   : $job->addDep($otherJob);
 Function: Adds a dependency on another slurmjob
 Example :
 Returns : nothing
 Args    : one or more Kalkyl::SlurmJob objects or slurm job ids

=cut

sub addDep{
    my $self = shift;
    foreach my $dep (@_){
	if(ref($dep) eq ref($self)){
	    push @{$self->{_depend}}, $dep;
	}else{
	    push @{$self->{_depend}}, $self->newDummy($dep);
	}
    }
}

=head2 jobId()

 Title   : jobId
 Usage   : $job->jobId();
 Function: returns the slurm jobid
 Example :
 Returns : The slurm job id
           0 if the job has not been submitted
 Args    : none

=cut

sub jobId{
    my $self = shift;
    return($self->{_jobid});
}

=head2 dependencies()

 Title   : dependencies
 Usage   : $job->dependiencies();
 Function: returns the Kalkyl::SlurmJobs that this job depends upon
 Example :
 Returns : array of Kalkyl::SlurmJobs
 Args    : none

=cut

sub dependencies{
    my $self = shift;
    return(@{$self->{_depend}});
}

=head2 status()

 Title   : status
 Usage   : $job->status();
 Function: Checks the status of the job
 Example :
 Returns : 1 if the job has completed successfully
           0 if the job is waiting/running
           -1 if the job has failed
           undef if the job is not yet submitted
 Args    : none

=cut

sub status{
    my $self = shift;
    if($self->{_jobid}==0){
	return undef;
    }

    my $job = $self->{_jobid};
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

    # Ask slurm for info about the job
    open(my $sqFh, "$squeueProg --format='%.7i %.2t' -t PENDING,RUNNING,SUSPENDED,COMPLETED,CANCELLED,FAILED,TIMEOUT,NODE_FAIL,COMPLETING -j $job|")
      or confess "Failed to open pipe from $squeueProg: $!\n";
    while(<$sqFh>){
	chomp;
        my @r = split /\s+/, $_;
        if($r[0]=~ m/^(\d+)$/ && $1==$job){
	    close($sqFh);
	    return $states{$r[1]};
	}
    }
    close($sqFh);

    # Too old for the slurm db, check accounting files
    if(-d "/bubo/sw/share/slurm/kalkyl/accounting"){
      my $accountDir = "/bubo/sw/share/slurm/kalkyl/accounting";
      opendir(my $aDir, $accountDir)
	or confess("Failed to open dir '$accountDir'");
      my @files = sort( {sortAccountFiles($a,$b)} grep(/^[^.]/, readdir($aDir)));
      foreach my $af (@files){
#	print STDERR "$af\n";
	#open(my $afFh, "$accountDir/$af") or confess("Failed to open file '$accountDir/$af'");
	my $line = `grep " jobid=$job " $accountDir/$af`;
	if($line){
	  if($line =~ m/jobstate=COMPLETED/){
	    print STDERR "$job Completed\n";
	    return 1;
	  }else{
	    print STDERR "$job Failed\n";
	    return -1;
	  }
	}
      }
    }
    confess("Failed to get slurm state for $job\n");
}

sub sortAccountFiles{
  my $a = shift;
  my $b = shift;
  $a=~s/-//g;
  $b=~s/-//g;
  return($b<=>$a);
}

=head2 submit()

 Title   : submit
 Usage   : $job->submit({recurse=>0,queue=>1});
 Function: Creates the job script and submits it to slurm
 Example :
 Returns : 1 on successful submission, otherwise 0
 Args    : recurse - if true, try to submit dependencies
           queue - if true, use the slurm queue and do not wait
                   for completion of dependencies before submitting

=cut

sub submit{
    my $self=shift;
    my $args = shift;

    my $queue = exists($args->{queue}) ? $args->{queue} : 1;
    my $recurse = exists($args->{recurse}) ? $args->{recurse} : 1;

    my $depStatus = $self->checkDependencies($queue);

    if($depStatus == -1){
	confess "A dependency has failed. Aborting\n";
    }elsif($depStatus == 0 && !$recurse){
	confess "Dependencies not met, and recursing is off\n";
    }elsif($depStatus == 0){
	# Check if the dependencies are started by temporarily setting queue=1
	my $ds = $self->checkDependencies(1);
	if($ds==0){
	    # Try to start the dependencies
	    my $tries = 0;
	    while($tries < 3){
		if($self->startDependencies($args)){
		    last;
		}else{
		    if($tries > 2){
			confess "Failed to start dependencies for $self->{NAME}\n";
			return 0;
		    }
		    $tries++;
		    sleep(60);
		}
	    }
	}
    }

    # If we are here, then we have managed to start any deps
    # So now we just have to wait for them to finish successfully
    # (Unless we are using the queue)
    until($depStatus == 1){
	$depStatus = $self->checkDependencies($queue);
	sleep 60 unless($depStatus);
    }

    my $scriptName = "$self->{SCRIPTDIR}/$self->{NAME}.sh";
    unless( -e $self->{SCRIPTDIR} ){
	mkpath( $self->{SCRIPTDIR}, 2770 );
    }
    unless( -e $self->{EXECDIR} ){
	mkpath( $self->{EXECDIR}, 2770 );
    }
    unless( -e "$self->{SCRIPTDIR}/logs" ){
	mkpath( "$self->{SCRIPTDIR}/logs", 2770 );
    }
    open(my $scriptFh, ">", "$scriptName") or confess "Failed to open '$scriptName': $!\n";
    my $project = $self->{PROJECT};
    my $time = $self->{TIME};
    my $name = $self->{NAME};
    my $logName = "$self->{SCRIPTDIR}/logs/$self->{NAME}.\%j.log";
    my $part = $self->{PARTITION};
    my $n = 1;
    if($part eq 'node'){
	$n = 8;
    }

    print $scriptFh <<EOF;
#!/bin/bash -l
#SBATCH -A $project
#SBATCH -p $part -n $n
#SBATCH -t $time
#SBATCH -J $name
#SBATCH -o $logName
#SBATCH -e $logName
EOF

    if(exists $self->{QOS} && defined $self->{QOS} && $self->{QOS} =~ m/\S/){
	print $scriptFh "#SBATCH --qos=$self->{QOS}\n";
    }
    if(exists $self->{STARTTIME}){
	print $scriptFh qq(#SBATCH --begin="$self->{STARTTIME}"\n);
    }
    my @deps = $self->dependencies();
    my $depflag = '';
    if($queue && @deps > 0){
	my @depId;
	foreach my $dep ($self->dependencies){
	    push @depId, $dep->jobId();
	}
	$depflag = "-d afterok:" . join(':', @depId);
    }

    print $scriptFh "\n$self->{_body}\n";

    close($scriptFh);

    my $jobid = `cd $self->{EXECDIR} && sbatch $depflag $scriptName`;
    if($? != 0){
	confess("sbatch $scriptName returned non zero exit status: $?\n");
    }
    $jobid =~ s/Submitted batch job //;
    $jobid =~ s/\s+$//;
    $self->{_jobid} = $jobid;
    sleep 5; # Just to let things settle before continue
    return 1;
}

=head2 checkDependencies()

 Title   : checkDependencies
 Usage   : $job->checkDependencies();
 Function: Returns 1 if all dependencies have completed
 Example :
 Returns : bool
 Args    : queue - if true, return true if the job is submitted,
                   even if it is not yet complete

=cut

sub checkDependencies{
    my $self=shift;
    my $queue = shift;

    foreach my $dep (@{$self->{_depend}}){
	my $status = $dep->status;
	if($status == -1){ # A dependency has failed
	    confess("$self->{NAME}: Dependency $dep->{NAME} has FAILED\n");
	    return(-1);
	}
	return 0 unless(defined $status); # Not yet submitted
	return 0 if( $status==0 && $queue==0 ); # Job is in the queue or processing, and that is ok
    }
    return 1;
}

=head2 startDependencies()

 Title   : startDependencies
 Usage   : $job->startDependencies({recurse=>0,queue=>1});
 Function: Checks for dependencies and tries to start those that are not already started
 Example :
 Returns : 1 on successful submission, otherwise 0
 Args    : recurse - if true, try to submit dependencies
           queue - if true, use the slurm queue and do not wait
                   for completion of dependencies before submitting

=cut

sub startDependencies{
    my $self=shift;
    my $args = shift;

    foreach my $dep (@{$self->{_depend}}){
	my $status = $dep->status;
	unless(defined $status){ # Status undef if not submitted (has no jobid)
	    my $tmp = $dep->submit($args);
	    unless($tmp){
		carp "$self->{NAME}: Failed to submit dependency $dep->{NAME}\n";
		return 0;
	    }
	}
    }
    return 1;
}

1;
