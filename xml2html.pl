#!/usr/bin/perl -w

use strict;
use XML::LibXSLT;
use XML::LibXML;

my $xmlFile = shift;
my $xslFile = shift;
my $htmlFile = shift;

die unless(-e $xmlFile);
die unless(-e $xslFile);

my $xslt = XML::LibXSLT->new();
my $stylesheet = $xslt->parse_stylesheet(XML::LibXML->load_xml(location=>$xslFile, no_cdata=>1));

# Strip the namespace from the xml data, adding it to the xsl is a mess
$/='';
open(my $xmlFh, $xmlFile) or die;
my $xmlData = <$xmlFh>;
$/="\n";
close($xmlFh);

$xmlData=~ s/xmlns="illuminareport.xml.molmed"//;

open(my $htmlFh, '>', $htmlFile) or die "Failed to open '$htmlFile' for writing: $!\n";

print $htmlFh
  $stylesheet->output_as_bytes(
			       $stylesheet->transform(
						      XML::LibXML->load_xml(
									    string => $xmlData
									   )
						     )
			      );

close($htmlFh);
