#!/usr/bin/perl

# This script creates owl:sameAs correspondences between URIs
# in the Census geographic data set and the Geonames data set.
# It relies on a SPARQL endpoint to get information from the
# Census data set (configurable below) and reads in the tab-
# delimited US.txt data file for Geonames data.  The RDF
# correspondences are written out in NTriples format to
# STDOUT.

$GEONAMES = 'geonames/US.txt'; # path to file

# SPARQL configuration
if (0) {
	# use my own data source
	$datasource = 'http://www.govtrack.us/sparql';
	$SPARQL_FROM = '';
} else {
	# use Virtuoso data source
	$datasource = 'http://dbpedia2.openlinksw.com:8890/sparql/';
	$SPARQL_FROM = 'FROM <tag:govshare.info,2005:rdf/census/>';
}

require "sparql.pl";

# Initialize variables

$rdftype = '<http://www.w3.org/1999/02/22-rdf-syntax-ns#type>';
$owlsameas = '<http://www.w3.org/2002/07/owl#sameAs>';
$dctitle = '<http://purl.org/dc/elements/1.1/title>';
$dcispartof = '<http://purl.org/dc/terms/isPartOf>';

# Hard-code the correspondence to the US.

print "<tag:govshare.info,2005:data/us> $owlsameas <http://www.geonames.org/countries/#US> .\n";

# Get a list of FIPS and USPS state codes.
@states = SparqlQuery($datasource, <<EOF);
SELECT ?entity ?uspscode ?fipscode $SPARQL_FROM
WHERE {
	?entity $rdftype <tag:govshare.info,2005:rdf/usgovt/State> .
	?entity <tag:govshare.info,2005:rdf/usgovt/uspsStateCode> ?uspscode .
	?entity <tag:govshare.info,2005:rdf/usgovt/fipsStateCode> ?fipscode .
}
EOF
print STDERR "Fetched " . scalar(@states) . " states.\n";
foreach my $result (@states) {
	$StateUri{$$result{uspscode}} = '<' . $$result{entity} . '>';
	$StateFips{$$result{uspscode}} = $$result{fipscode};
}

# Get a list of county state-county FIPS codes.
# Do it by state so we don't have a query that returns > 3000 records
# since the query source might cut us off.
foreach my $stateuri (values(%StateUri)) {
	my @counties = SparqlQuery($datasource, <<EOF);
SELECT ?entity ?code $SPARQL_FROM
WHERE {
	?entity $rdftype <tag:govshare.info,2005:rdf/usgovt/County> .
	?entity $dcispartof $stateuri .
	?entity <tag:govshare.info,2005:rdf/usgovt/fipsStateCountyCode> ?code .
}
LIMIT 4000
EOF
	foreach my $result (@counties) {
		$CountyUri{$$result{code}} = '<' . $$result{entity} . '>';
	}
}
print STDERR "Fetched " . scalar(keys(%CountyUri)) . " counties.\n";

# Now loop through the geonames database

open GEONAMES, "<$GEONAMES";
binmode(GEONAMES, ":utf8");
while (!eof(GEONAMES)) {
	$_ = <GEONAMES>;
	chop;
	($id, $name, $asciiname, $altnames, $lat, $long,
		$fclass, $fcode, $countrycode, $cc2,
		$admin1, $admin2, $population, $elevation, $gtopo,
		$tz, $moddate) = split(/\t/);

	if ($fcode eq 'ADM1') {
		# This is a state. We've already pre-fetched its ADM1 code.

		if (!defined($StateUri{$admin1})) { warn "State $admin1 is not in Census dataset."; next; }
		print "$StateUri{$admin1} $owlsameas <http://sws.geonames.org/$id/> .\n";

	} elsif ($fcode eq 'ADM2') {
		# This is a county. We've pre-fetched these too.

		if (!defined($StateFips{$admin1})) { warn "State $admin1 is not in Census dataset."; next; }
		my $uri = $CountyUri{$StateFips{$admin1} . ':' . $admin2};
		if (!defined($uri)) { warn "County $admin1:$admin2 is not in Census data set"; next; }
		print "$uri $owlsameas <http://sws.geonames.org/$id/> .\n";

	} elsif ($fcode eq 'AMDD' || $fcode eq 'PPL') {
		# This might be either a town or a village as far as the Census
		# dataset is concerned.

		#my $class;
		#if ($fcode eq 'AMDD') { $class = 'Town'; }
		#elsif ($fcode eq 'PPL') { $class = 'Village'; }

		# We have to look it up by name. But, we have at least
		# the URI of the county that we are in.

		if (!defined($StateFips{$admin1})) { warn "State $admin1 is not in Census dataset (processing $name)."; next; }
		my $countyuri = $CountyUri{$StateFips{$admin1} . ':' . $admin2};
		if (!defined($countyuri)) { warn "County $admin1:$admin2 is not in Census data set (processing $name)"; next; }

		if (!defined($CountyPlaces{$countyuri})) {
			# For each county, load in all of its towns and villages.
			my @Towns = SparqlQuery($datasource, <<EOF);
SELECT ?entity ?name $SPARQL_FROM
WHERE {
	# ?entity $rdftype <tag:govshare.info,2005:rdf/usgovt/$class> .
	?entity $dcispartof $countyuri .
	?entity $dctitle ?name .
}
EOF

			my @Villages = SparqlQuery($datasource, <<EOF);
SELECT ?entity ?name $SPARQL_FROM
WHERE {
	# ?entity $rdftype <tag:govshare.info,2005:rdf/usgovt/$class> .
	?entity $dcispartof [ $dcispartof $countyuri ] .
	?entity $dctitle ?name .
}
EOF

			print STDERR "For $countyuri fetched " . scalar(@Towns) . " towns, " . scalar(@Villages) . " villages.\n";

			$CountyPlaces{$countyuri} = [[@Towns], [@Villages]];
		}

		my @CachedTowns = @{ $CountyPlaces{$countyuri}[0] };
		my @CachedVillages = @{ $CountyPlaces{$countyuri}[1] };

		my @places;
		foreach my $p (@CachedTowns) {
			if ($name eq $$p{name}) { push @places, $$p{entity}; }
		}
		foreach my $p (@CachedVillages) {
			if ($name eq $$p{name}) { push @places, $$p{entity}; }
		}

		if (scalar(@places) == 0) {
			print STDERR "No entry for $name in $countyuri\n";
		} elsif (scalar(@places) == 1) {
			my $uri = $places[0];
			print "<$uri> $owlsameas <http://sws.geonames.org/$id/> .\n";
		} else {
			print STDERR "No unique entry for $name in $countyuri\n";
		}
	}

	#print "$id\t$name $fcode $admin1 $admin2\n";

}
close GEONAMES;
