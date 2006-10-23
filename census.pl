#!/usr/bin/perl

# This script transforms the 2000 U.S. Census geography (usgeo) and
# national data files for Summary File 1 and Summary File 3 into
# Notation 3 RDF.
#
# Copyright (C) 2006 Joshua Tauberer.  Released under the
# Creative Commons Attribution-NonCommercial-ShareAlike 2.5 License.
#
# It is expected that this file be in the same directory
# containing this script:
#   usgeo_uf1.txt                   (191M)
# Additionally, if you want to transform the enormous Summary Files,
# you will need these four (sets of) files:
#   usgeo_uf3.txt                   (187M)
#   SF1__all_0Final_National.zip    (1GB)
#   SF3__all_0_National-part1.zip   (2GB)
#   table_layouts/*
#
# The files come from the Census website:
#   http://www2.census.gov/census_2000/datasets/
#
# Get the usgeo_uf1.txt file from:
#   http://www2.census.gov/census_2000/datasets/Summary_File_1/0Final_National/usgeo_uf1.zip
# And if you want to process the Summary Files, then also get:
#   http://www2.census.gov/census_2000/datasets/Summary_File_1/0Final_National/all_0Final_National.zip
#   http://www2.census.gov/census_2000/datasets/Summary_File_3/0_National/usgeo_uf3.zip
#   http://www2.census.gov/census_2000/datasets/Summary_File_3/0_National/all_0_National-part1.zip
#
# You will also need the SAS layout files.  Grab SF1SAS.zip and
# SF3SAS.zip from in here:
#   http://www.census.gov/support/2000/
# And then create the following directory structure:
#   ./table_layouts/sf1/ (extract files from SF1SAS.zip here)
#   ./table_layouts/sf3/ (extract files from SF3SAS.zip here)
# Then you must patch the files with the patch provided with this
# script: census_table_layouts.patch.  This corrects some format
# errors in the files and adjusts some things to make them more
# easily processed by this script.  Run:
#   patch -p0 < census_table_layouts.patch
#
# You can now run this script with Perl.  To process just the
# geographic data, run:
#   perl census.pl GEO
# That will create four files in a new 'rdf' subdirectory (~20MB).
#
# To process the Summary File data, run:
#   perl census.pl SUMFILES
# Various RDF files will be piped through gzip and written into a
# 'rdf' subdirectory, which will be created if it doesn't already
# exist.  These files total around 1 GB and have in the neighborhood
# of 200 million RDF triples (I haven't counted them all yet).
# -------------------------------------------------------------------

# see: http://www.census.gov/support/SF1ASCII.html
%CENSUSSTATES = (1 => AL, 2 => AK, 4 => AZ, 5 => AR, 6 => CA, 8 => CO,
9 => CT, 10 => DE, 11 => DC, 12 => FL, 13 => GA, 15 => HI, 16 => ID, 17
=> IL, 18 => IN, 19 => IA, 20 => KS, 21 => KY, 22 => LA, 23 => ME, 24 =>
MD, 25 => MA, 26 => MI, 27 => MN, 28 => MS, 29 => MO, 30 => MT, 31 =>
NE, 32 => NV, 33 => NH, 34 => NJ, 35 => NM, 36 => NY, 37 => NC, 38 =>
ND, 39 => OH, 40 => OK, 41 => OR, 42 => PA, 44 => RI, 45 => SC, 46 =>
SD, 47 => TN, 48 => TX, 49 => UT, 50 => VT, 51 => VA, 53 => WA, 54 =>
WV, 55 => WI, 56 => WY, 60 => AS, 66 => GU, 69 => MP, 72 => PR, 78 => VI); 


if ($ARGV[0] eq 'TESTLAYOUT') {
	print ParseSumFileLayout($ARGV[1]);
} elsif ($ARGV[0] eq 'GEO') {
	ProcessGeoTables(1, 1);
} elsif ($ARGV[0] eq 'SUMFILES') {
	ProcessSummaryFile('SF1__all_0Final_National', 1);
	ProcessSummaryFile('SF3__all_0_National-part1', 3);
}

sub ProcessSummaryFile {
	my ($file, $n) = @_;

	ProcessGeoTables($n, $n == 1);

	my $tabledir = "table_layouts/sf$n";
	opendir DIR, $tabledir;
	foreach my $table (readdir(DIR)) {
		if ($table !~ /sf$n(\d\d)\.sas$/i) { next; }
		my $tablenum = $1;

		ProcessSumFileTable($file, "$tabledir/$table", $tablenum);
	}
	closedir DIR;
}

sub ProcessGeoTables {
	my ($sumfile, $writerdf) = @_;

	undef %LOGRECNOURI;
	undef %LOGRECNOTYPE;

	my @FIELDS = split(/,/, "FILEID:6,STUSAB:2,SUMLEV:3,GEOCOMP:2,CHARITER:3,CIFSN:2,LOGRECNO:7,REGION:1,DIVISION:1,STATECE:2,STATE:2,COUNTY:3,COUNTYSC:2,COUSUB:5,COUSUBCC:2,COUSUBSC:2,PLACE:5,PLACECC:2,PLACEDC:1,PLACESC:2,TRACT:6,BLKGRP:1,BLOCK:4,IUC:2,CONCIT:5,CONCITCC:2,CONCITSC:2,AIANHH:4,AIANHHFP:5,AIANHHCC:2,AIHHTLI:1,AITSCE:3,AITS:5,AITSCC:2,ANRC:5,ANRCCC:2,MSACMSA:4,MASC:2,CMSA:2,MACCI:1,PMSA:4,NECMA:4,NECMACCI:1,NECMASC:2,EXI:1,UA:5,UASC:2,UATYPE:1,UR:1,CD106:2,CD108:2,CD109:2,CD110:2,SLDU:3,SLDL:3,VTD:6,VTDI:1,ZCTA3:3,ZCTA5:5,SUBMCD:5,SUBMCDCC:2,AREALAND:14,AREAWATR:14,NAME:90,FUNCSTAT:1,GCUNI:1,POP100:9,HU100:9,INTPLAT:9,INTPLON:10,LSADC:2,PARTFLAG:1,SDELEM:5,SDSEC:5,SDUNI:5,TAZ:6,UGA:5,PUMA5:5,PUMA1:5,RESERVE2:15,MACC:5,UACP:5,RESERVED:7");
	my %FIELDSIZE;
	foreach my $f (@FIELDS) {
		$f =~ /(\w+):(\d+)/;
		$f = $1;
		$FIELDSIZE{$f} = $2;
	}

	my %URI; # tracks the last state seen, the last county seen, etc.
	my %POP; # track the last population seen at each level

	if ($writerdf) {
		my $outputfileroot = "rdf/";
		`mkdir -p rdf`;

		open STATE, ">$outputfileroot" . "states.n3";
		open COUNTY, ">$outputfileroot" . "counties.n3";
		open COUNTYSUB, ">$outputfileroot" . "towns.n3";
		open COUNTYSUBPLACE, ">$outputfileroot" . "villages.n3";

		foreach my $file (STATE, COUNTY, COUNTYSUB, COUNTYSUBPLACE) {
			print $file <<EOF;
\@prefix rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#> .
\@prefix dc: <http://purl.org/dc/elements/1.1/> .
\@prefix dcterms: <http://purl.org/dc/terms/> .
\@prefix geo: <http://www.w3.org/2003/01/geo/wgs84_pos#> .
\@prefix census: <tag:govshare.info,2005:rdf/census/> .
\@prefix usgovt: <tag:govshare.info,2005:rdf/usgovt/> .
EOF
			}
	}

	#open CENSUS, "unzip -p SF1__all_0Final_National.zip usgeo_uf1.zip | gunzip |";
	open(CENSUS, "<usgeo_uf$sumfile.txt") or die "usgeo_uf$sumfile.txt: $@";
	while (!eof(CENSUS)) {
		$line = <CENSUS>; chop $line;
		my $start = 0;
		my %info;
		foreach my $f (@FIELDS) {
			my $val = substr($line, $start, $FIELDSIZE{$f});
			$val =~ s/^\s+//;
			$val =~ s/\s+$//;
			$start += $FIELDSIZE{$f};
			$info{$f} = ESC($val);
		}
	
		if ($info{GEOCOMP} ne "00") { next; }
		if ($info{NAME} =~ / \(part\)/) { next; }
		if ($info{CHARITER} ne "000") { die "chariter $info{CHARITER}"; }
	
		my $file;
		my $isa;
		my $uri;
		my $parent;
	
		if ($info{SUMLEV} eq "010") {
			$file  = "US";
			$uri = "tag:govshare.info,2005:data/us";
			$isa = "<tag:govshare.info,2005:rdf/politico/Country>";
		} elsif ($info{SUMLEV} eq "040") {
			$file  = "STATE";
			$parent = $URI{US};
			$uri = "$URI{US}/" . lc($CENSUSSTATES{0+$info{STATE}});
			$isa = "usgovt:State";
			print "sf$sumfile: " . lc($CENSUSSTATES{0+$info{STATE}}) . "\n";
		} elsif ($info{SUMLEV} eq "050") {
			$file  = "COUNTY";
			$parent = $URI{STATE};
			$uri = "$URI{STATE}/counties/" . URI($info{NAME});
			$isa = "usgovt:County";
		} elsif ($info{SUMLEV} eq "060") {
			$file  = "COUNTYSUB";
			$parent = $URI{COUNTY};
			$uri = "$URI{COUNTY}/" . URI($info{NAME});
			$isa = "usgovt:Town";
		} elsif ($info{SUMLEV} eq "070") {
			$file  = "COUNTYSUBPLACE";
			if ($info{NAME} =~ /Remainder of/) { next; }
		$parent = $URI{COUNTYSUB};
			$uri = "$URI{COUNTYSUB}/" . URI($info{NAME});
			$isa = "usgovt:Village";
			if ($POP{COUNTYSUB} == $info{POP100}) { next; } # this region is the same as its parent region
		}
		else { next; }

		$URI{$file} = $uri;
		$POP{$file} = $info{POP100};
	
		$info{STATEUSPS} = $CENSUSSTATES{0+$info{STATE}};
	
		my $file2 = $file;
		if ($file eq "US") { $file = "STATE" } # Put the US node in the states file

		$LOGRECNOURI{$info{LOGRECNO}} = $uri;
		$LOGRECNOTYPE{$info{LOGRECNO}} = $file;
		
		$info{INTPLAT} /= 1000000;
		$info{INTPLON} /= 1000000;

		if (!$writerdf) { next; }

		print $file "<$uri> \n";
		print $file "	rdf:type $isa ;\n";
		print $file "	usgovt:censusStateCode \"$info{STATECE}\" ;\n" if ($file2 eq "STATE");
		print $file "	usgovt:fipsStateCode \"$info{STATE}\" ;\n" if ($file2 eq "STATE");
		print $file "	usgovt:uspsStateCode \"$info{STATEUSPS}\" ;\n" if ($file2 eq "STATE");
		print $file "	usgovt:fipsCountyCode \"$info{COUNTY}\" ;\n" if ($file2 eq "COUNTY");
		print $file "	usgovt:fipsStateCountyCode \"$info{STATE}:$info{COUNTY}\" ;\n" if ($file2 eq "COUNTY");
		print $file "	dc:title \"$info{NAME}\" ;\n" if ($file2 ne "US");
		print $file "	dcterms:isPartOf <$parent> ;\n" if ($file2 ne "US");
		print $file "	geo:lat \"$info{INTPLAT}\" ;\n" if ($file ne "STATE");
		print $file "	geo:long \"$info{INTPLON}\" ;\n" if ($file ne "STATE");
		print $file "	census:population \"$info{POP100}\" ;\n";
		print $file "	census:households \"$info{HU100}\" ;\n";
		print $file "	census:landArea \"$info{AREALAND} m^2\" ;\n";
		print $file "	census:waterArea \"$info{AREAWATR} m^2\" .\n";
	}

	close CENSUS;

	if ($writerdf) {
		close STATE;
		close COUNTY;
		close COUNTYSUB;
		close COUNTYSUBPLACE;
	}
}

sub ESC {
	my $lit = shift;
	#$lit =~ /([^ A-Za-z0-9\+\-().,\/'#x])/;
	#if (defined($1)) { warn $1; }
	return $lit;
}

sub URI {
	my $name = shift;
	$name = lc($name);
	$name =~ s/\.//g;
	$name =~ s/ county//g;
	$name =~ s/ town//g;
	$name =~ s/ city//g;
	$name =~ s/ ccd//g;
	$name =~ s/ cdp//g;
	$name =~ s/\W/_/g;
	return $name;
}

sub ProcessSumFileTable {
	my ($file, $layout, $table) = @_;
	
	my $template = ParseSumFileLayout($layout);
	if ($template eq "") { return; }

	print STDERR "Summary File $file Table $table\n";

	if ($file !~ /SF(\d)/) { die $file; }
	my $sf = $1;

	my $namespaces = <<EOF;
\@prefix rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#> .
\@prefix dc: <http://purl.org/dc/elements/1.1/> .
\@prefix : <tag:govshare.info,2005:rdf/census/details/> .
EOF

	if (defined(%LOGRECNOURI)) {
		open STATE, "| gzip > rdf/sumfile$sf-$table-states.n3.gz";
		open COUNTY, "| gzip > rdf/sumfile$sf-$table-counties.n3.gz";
		open COUNTYSUB, "| gzip > rdf/sumfile$sf-$table-towns.n3.gz";
		open COUNTYSUBPLACE, "| gzip > rdf/sumfile$sf-$table-villages.n3.gz";

		print STATE $namespaces;
		print COUNTY $namespaces;
		print COUNTYSUB $namespaces;
		print COUNTYSUBPLACE $namespaces;
	} else {
		print $namespaces;
	}

	open DATA, "unzip -p " . $file . ".zip us000" . $table . "_uf$sf.zip | gunzip |";
	while (!eof(DATA)) {
		my $line = <DATA>;
		chop $line;
		$line =~ s/\r//g;
		
		my @fields = split(/,/, $line);
		
		my $fileid = shift(@fields);
		my $state_usps = shift(@fields);
		my $chariter = shift(@fields);
		my $charseq = shift(@fields);
		my $logrecno = shift(@fields);
		
		my $uri = $LOGRECNOURI{$logrecno};
		
		if (!defined(%LOGRECNOURI)) { $uri = ":"; } # running standalone

		if (!defined($uri)) { next; }

		my $t = $template;
		for (my $i = 0; $i < scalar(@fields); $i++) {
			$t =~ s/%$i%/$fields[$i]/eg;
		}

		if (!defined(%LOGRECNOURI)) {
			print "<> $t";
		} else {
			my $file = $LOGRECNOTYPE{$logrecno};
			print $file "<$uri> $t";
		}
		
		if (!defined(%LOGRECNOURI)) { last; } # running standalone
	}

	if (defined(%LOGRECNOURI)) {
		close STATE;
		close COUNTY;
		close COUNTYSUB;
		close COUNTYSUBPLACE;
	}
}

sub ParseSumFileLayout {
	my $file = shift;

	my $title;
	my $universe;
	my $specialtotal;
	my $nextstartsgroup;
	my $isfirst;
	my $tabs = '';
	my @indents;

	my $ret = "";

	open LAYOUT, "<$file";
	while (!eof(LAYOUT)) {
		my $line = <LAYOUT>;
		chop $line;
		$line =~ s/\r$//;

		if ($line =~ /^#/) { next; }
		if ($line !~ /\S/) { next; }
		if ($line =~ /\/\*Process Summary File \d+ Data File Number \d+\*\//) { next; }
		if ($line =~ /^\s*(TITLE|DATA|INFILE)/) { next; }
		if ($line =~ /FILEID|STUSAB|CHARITER|CIFSN|LOGRECNO/) { next; }

		$line =~ s/<BR>\&nbsp;\&nbsp;/ /g;

		if ($line =~ /\/\*(.*)\s*\[(\d+)\]\*\//) {
			$title = $1;
			$title =~ s/"|\\//g;
			$isfirst = 1;
			$specialtotal = '';
			$nextstartgroup = '';
			next;
		}

		if ($line =~ /\/\*Universe: (.*)\*\//) {
			$universe = $1;
			$nextstartgroup = '';
			next;
		}

		if ($line =~ /\/\*((Average|Median|Percent) .*\S)\s*--\*\//) {
			$specialtotal = $1;
			$nextstartgroup = '';
			next;
		}

		if ($line =~ /\/\*  \s*(\S.*\S)\s*--\*\//) {
			$nextstartgroup = $1;
			next;
		}
		
		if ($line =~ /^\s+(LABEL\s+)?([A-Z0-9]+)='(.*)'[\s;]*$/) {
			if ($title eq "") { next; }
			if ($title =~ /IMPUTATION/) { next; }
			if ($universe =~ /who is|who are|white|black|hispanic|asian|american indian|native hawaiian|some other race|two or more races/i) { next; } # skip race-by-race tables

			my ($id, $name) = ($2, $3);

			my $isgroup = 0;
			if ($name =~ s/:$//) { $isgroup = 1; }

			my $indent;
			$name =~ s/^(\s*)//;
			$indent = length($1);
			if ($nextstartgroup eq 'INGROUP') { $indent++; }

			while (scalar(@indents) > 0 && $indent <= $indents[scalar(@indents)-1] || ($isfirst && scalar(@indents) > 0)) {
				pop @indents;
				$ret .= "$tabs] ;\n";
				$tabs =~ s/\t//;
			}

			my $predicate = $name;
			my $groupvalue = 'rdf:value';
			$predicate = MakePredicate($predicate);

			if ($nextstartgroup ne '' && $nextstartgroup ne 'INGROUP') {
				if ($name !~ /^Total/i) { die "Had a special group before a non-'total' line: $nextstartgroup / $name"; }
				$predicate = MakePredicate($nextstartgroup);
				$nextstartgroup = 'INGROUP';
			}

			if (scalar(@indents) == 0) {
				if ($specialtotal ne '') {
					if ($name !~ /^Total/i) {
						$ret .= $tabs . MakePredicate($universe);
						$ret .= " [ dc:title \"$title\";\n";
						push @indents, 0;
					} else {
						$predicate = MakePredicate($universe);
						$indent--;
					}
				} else {
					if ($name !~ /^Total/i) {
						$groupvalue = $predicate;
						$isgroup = 1;
					}
					$predicate = MakePredicate($universe);
				}
			}
			if ($specialtotal ne '') {
				$groupvalue = MakePredicate($specialtotal);
				$isgroup = 1;
			}

			$ret .= "$tabs$predicate ";
			if ($isgroup) {
				$tabs .= "\t";
				if ($isfirst) {
					$ret .= "[ dc:title \"$title\";\n";
					$ret .= $tabs . "$groupvalue ";
				} else {
					$ret .= "[ $groupvalue ";
				}
				push @indents, $indent;
			}

			$ret .= "%%$id%% ; \t# $id\n";

			$isfirst = 0;

			next;
		}

		if ($line =~ /INPUT/) {
			my $ctr = 0;
			while (!eof(LAYOUT)) {
				my $line = <LAYOUT>;
				chop $line;

				my $islast = ($line =~ s/;//);
				$line =~ s/\s//g;
				if ($line =~ /\$/ || $line eq '') { next; }
				$ret =~ s/%%$line%%/%$ctr%/;
				$ctr++;
				if ($islast) { last; }
			}

			if ($ret =~ /%%(.*?)%%/) {
				die "Field $1 not found in input list.";
			}

			last;
		}

		die "Invalid line in SAS layout in file $file: " . $line;
	}
	close LAYOUT;

	while (scalar(@indents) > 0) {
		pop @indents;
		$ret .= "$tabs] ;\n";
	}

	$ret =~ s/;(\s*\#.*)?\n$/.$1\n/;

	return $ret;
}

sub MakePredicate {
	my $predicate = shift;
	if ($predicate eq 'rdf:value') { return $predicate; }
	$predicate =~ s/ (\w)/uc($1)/ge;
	$predicate =~ s/^(\w)/lc($1)/ge;
	$predicate =~ s/-//g;
	$predicate =~ s/\$/D/g;
	$predicate =~ s/[^a-zA-Z0-9]/_/g;
	if ($predicate =~ /^[^a-z]/) { $predicate = "_$predicate"; }
	$predicate = ":$predicate";
	return $predicate;
}
