use XML::LibXML;
use XML::LibXML::XPathContext;
use LWP::UserAgent;
use HTTP::Request::Common qw(GET POST);

my $XMLPARSER = XML::LibXML->new();
my $UA = LWP::UserAgent->new();
my $sparqlns = 'http://www.w3.org/2005/sparql-results#';

sub SparqlQuery {
	my ($url, $query) = @_;
	
	my $req = POST $url, [ query => $query ];
	my $resp = $UA->request($req);
	if (!$resp->is_success) {
		die "Query failed:\n$url?query=$query\n" . $resp->code . " " . $resp->message;
	}

	my $doc = $XMLPARSER->parse_string($resp->content);

	my $xc = XML::LibXML::XPathContext->new();
	$xc->registerNs('sparql', $sparqlns);

	my @ret;
	foreach my $result ($xc->findnodes('//sparql:result', $doc)) {
		my %bindings;
		foreach my $binding ($xc->findnodes('sparql:binding', $result)) {
			$bindings{$binding->getAttribute('name')} = $xc->findvalue('node()[name()="uri" or name() = "literal"]', $binding);
			$bindings{$binding->getAttribute('name') . '__valuetype'} = $xc->findvalue('name(*)', $binding);
			$bindings{$binding->getAttribute('name') . '__datatype'} = $xc->findnodes('*', $binding)->pop()->getAttribute('datatype');
		}
		push @ret, { %bindings };
	}

	return @ret;
}
