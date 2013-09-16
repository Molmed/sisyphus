#!/usr/bin/perl -w

use strict;
use List::Util 'shuffle';

my $fileName1 = shift;
my $fileName2 = shift;

generateFile1($fileName1);
generateFile2($fileName2);

sub generateFile1{
    # 1. Adaptersekvens startar på varje cykel i 1% av alla reads.
    # Dvs, adaptersekvens börjar på cykel 1 i 1% av sekvenserna,
    # i cykel 2 för 1% av sekvenserna...cykel 100 1% av sekvenserna.
    # Använd alla baser slumpvis, 25% av varje, för övrig sekvens.
    # I samma fil, ange Q-värden så att alla Q-värden finns
    # representerade i samma antal i första cykeln.
    # Minska sedan alla Q-värden med 1 för varje cykel,
    # ner till noll.

    my @seqs;
    my $adapter1 = "AGATCGGAAGAGCACACGTC";
#    my $adapter2 = "AGATCGGAAGAGCGTCGTGT";
    for(my $i=0; $i<100; $i++){
	for(my $j=0; $j<10000; $j++){
	    my $s = randomSeq(0.25,0.25,0.25,0.25,$i) . $adapter1 . randomSeq(0.25,0.25,0.25,0.25,100-$i-length($adapter1));
	    $s = substr($s,0, 100);
	    push @seqs, $s;
	}
    }

    my @qstrings;
    for(my $i=0; $i<41; $i++){
	for(my $j=0; $j<25000; $j++){
	    my $qstr = '';
	    my $q = $i;
	    for(my $c=0; $c<100; $c++){
		$q = $q>0 ? $q - 1 : 0;
		$qstr .= chr($q+33);
	    }
	    push @qstrings, $qstr;
	}
    }

    my @seqs2 = shuffle(@seqs);
    my @qstrings2 = shuffle(@qstrings);

    open(my $fh, '>', $_[0]);
    for(my $i=0; $i<@seqs2; $i++){
	print $fh "\@seq$i\n" . $seqs2[$i] . "\n+\n" . $qstrings2[$i] . "\n";
    }

    close($fh);
}

sub generateFile2{
    # Skapa sekvenser med 15% G, 20% C, 30% T och 35% A.
    # I samma fil, se till att 80% av sekvenserna är
    # unika, 10% finns i två kopior, 5% i tre kopior,
    # 2,5% i 4 kopior samt 0,5% av vardera 5-10 kopior.
    # I samma fil, ange Q-värden över 30 för alla baser
    # i de första 10.000 sekvenserna, minska sedan
    # antalet baser med Q över 30 med en bas för varje
    # 10.000 sekvenser.

    my @seqs;
    for(my $i=0; $i<8e5; $i++){
	push @seqs, randomSeq(0.35,0.20,0.15,0.30,100);
    }

    print STDERR "1: ", count(@seqs), " seqs\n";

    for(my $i=0; $i<1e5/2; $i++){
	my $seq = randomSeq(0.35,0.20,0.15,0.30,100);
	push @seqs, $seq, $seq;
    }

    print STDERR "2: ", count(@seqs), " seqs\n";

    for(my $i=0; $i<int(5e4/3); $i++){
	my $seq = randomSeq(0.35,0.20,0.15,0.30,100);
	push @seqs, $seq, $seq, $seq;
    }

    print STDERR "3: ", count(@seqs), " seqs\n";

    for(my $i=0; $i<int(2.5e4/4); $i++){
	my $seq = randomSeq(0.35,0.20,0.15,0.30,100);
	push @seqs, $seq, $seq, $seq, $seq;
    }

    print STDERR "4: ", count(@seqs), " seqs\n";

    for(my $j=5; $j<10; $j++){
	for(my $i=0; $i<int(5e3/$j); $i++){
	    my $seq = randomSeq(0.35,0.20,0.15,0.30,100);
	    for(my $k=0; $k<$j; $k++){
		push @seqs, $seq;
	    }
	}
	print STDERR (4+$j), ": ", count(@seqs), " seqs\n";
    }

    my @qstrings;
    my $q20 = chr(20+33);
    my $q30 = chr(30+33);
    for(my $i=0; $i<100; $i++){
	my $n = 100 - $i;
	for(my $j=0; $j<1e4; $j++){
	    # Place the q>=30 stretch randomly along sequence
	    my $str1 = '';
	    my $str2 = $q30 x $n;
	    my $str3 = '';
	    if($n<100){
		my $m = sprintf('%.0f', rand(1) * (100 - $n));
		my $k = 100 - $n - $m;
		$str1 = $q20 x $m;
		$str3 = $q20 x $k;
	    }
	    push @qstrings, "$str1$str2$str3";
	}
    }


    my @seqs2 = shuffle(@seqs);
    my @qstrings2 = shuffle(@qstrings);

    open(my $fh, '>', $_[0]);
    for(my $i=0; $i<@seqs2; $i++){
	print $fh "\@seq$i\n" . $seqs2[$i] . "\n+\n" . $qstrings2[$i] . "\n";
    }

    close($fh);
}

sub count{
    return @_ + 0;
}

sub randomSeq{
    my($a,$c,$g,$t,$len) = @_;
    my $seq = '';
    for(my $i=0; $i<$len; $i++){
	my $r = rand(1);
	if($r < $a){
	    $seq .= 'A';
	}elsif($r < ($a+$c)){
	    $seq .= 'C';
	}elsif($r < ($a+$c+$g)){
	    $seq .= 'G';
	}else{
	    $seq .= 'T';
	}
    }
    return($seq);
}
