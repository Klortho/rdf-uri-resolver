#! /usr/bin/env perl
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/lib";
use aliased 'NCBI::RDF::UriResolver';

use Data::Dumper;
use Getopt::Long;
use LWP::UserAgent;
use Test::More;
use URI::Encode qw(uri_encode);
use YAML;

local $Data::Dumper::Indent = 1;
my $default_service_url = 'http://rdf.ncbi.nlm.nih.gov';

my %options;
my $opts_ok = GetOptions(\%options,
    'help|?',
    'verbose',
    'url=s',
);
if (!$opts_ok || $options{help}) {

    print <<USAGE;
Usage:  test.pl [options] [<test_name>]
Runs tests of the rdf-uri-resolver library. There are two kinds of tests: local
and remote. The local tests run against a locally-instantiated UriResolver object.
The remote tests run against a CGI on a remote server. Make sure the server is up 
and running at the appropriate URL.

If no <test_name> is given, then all the tests are run. If "local" is given, then
only the suite of local tests is run. If "remote" is given, then all of the remote
tests are run. Otherwise, the individual remote test names are defined in
tests.yaml.

Options

--help|-? - print this usage information and exit
--verbose - output verbose messages
--url=[url] - the URL of the service; defaults to $default_service_url.
USAGE

    exit !$opts_ok;
}
my $verbose = $options{verbose} || 0;
my $url = $options{url} || $default_service_url;

my $ua = LWP::UserAgent->new();
print "Testing service at $url\n";

# Which test(s) should we run?
my $run_all = 1;      # by default, run all tests
my $run_local = 0;
my $run_remote = 0;
my %run_tests = ();   # Specific tests to run
while (my $arg = shift @ARGV) {
    $run_all = 0;
    if ($arg eq 'local') {
        $run_local = 1;
    }
    elsif ($arg eq 'remote') {
        $run_remote = 1;
    }
    else {
        $run_tests{$arg} = 1;
    }
}
$run_local ||= $run_all;
$run_remote ||= $run_all;



#-------------------------------------------------------------------------------
# Local tests - these instantiate a UriResolver object, and test it directly

if ($run_local) {
    my $resolver = UriResolver->new;
    $resolver->debug(1) if $verbose;

    $resolver->read_config_if_necessary();
    #print Dumper($resolver->config);

    # Test parsing the config file

    my $config = $resolver->config;
    ok( $config, "parsed the config.xml file" );

    my $exampleProj = $config->{projects}{example};
    ok( $exampleProj, "found an example project" );

    my $exampleRedirects = $exampleProj->{redirects};
    ok( @$exampleRedirects == 4, "got four example redirects" );


    # Test some actual URI paths.  Use Capture::Tiny to capture the STDOUT from the CGI's
    # run() method.

    my $testToRun = $ARGV[0] ? $ARGV[0] : 1;
    my ($stdout, $stderr, @result);

    my @redirectTests = (
        {
            'REQUEST_URI' => '/example/vocabulary',
            'HTTP_ACCEPT' => '',
            'expected' => '/example/vocabulary.owl',
        },
        {
            'REQUEST_URI' => '/example/1/1001',
            'HTTP_ACCEPT' => '',
            'expected' => 'http://rdf.ncbi.nlm.nih.gov/example/target/1.html?id=1001',
        },
        # Test accept headers
        {
            'REQUEST_URI' => '/example/2/1002',
            'HTTP_ACCEPT' => 'application/rdf+xml',
            'expected' => 'http://rdf.ncbi.nlm.nih.gov/example/target/2.rdf?id=1002',
        },
        {
            'REQUEST_URI' => '/example/2/1003',
            'HTTP_ACCEPT' => 'application/json',
            'expected' => 'http://rdf.ncbi.nlm.nih.gov/example/target/2.json?id=1003',
        },
        {
            'REQUEST_URI' => '/example/2/1004',
            'HTTP_ACCEPT' => 'text/html',
            'expected' => 'http://rdf.ncbi.nlm.nih.gov/example/target/2a.html?id=1004',
        },
        # Test using an extension to simulate an accept header
        {
            'REQUEST_URI' => '/example/2/1005.rdf',
            'HTTP_ACCEPT' => '',
            'expected' => 'http://rdf.ncbi.nlm.nih.gov/example/target/2.rdf?id=1005',
        },
        {
            'REQUEST_URI' => '/example/2/1006.json',
            'HTTP_ACCEPT' => '',
            'expected' => 'http://rdf.ncbi.nlm.nih.gov/example/target/2.json?id=1006',
        },

        # Test the target-mime-extensions
        {
            'REQUEST_URI' => '/example/3/1007',
            'HTTP_ACCEPT' => '',
            'expected' => 'http://rdf.ncbi.nlm.nih.gov/example/target/3/1007',
        },
        {
            'REQUEST_URI' => '/example/3/1008',
            'HTTP_ACCEPT' => 'application/rdf+xml',
            'expected' => 'http://rdf.ncbi.nlm.nih.gov/example/target/3/1008.rdf',
        },
        {
            'REQUEST_URI' => '/example/3/1009',
            'HTTP_ACCEPT' => 'application/json',
            'expected' => 'http://rdf.ncbi.nlm.nih.gov/example/target/3/1009.json',
        },

    #    {
    #        'REQUEST_URI' => '',
    #        'HTTP_ACCEPT' => '',
    #        'expected' => '',
    #    },
    );

    foreach my $rtest (@redirectTests) {
        print "-------------------------------------------------\n" if $verbose;
        my $requestUri = $rtest->{REQUEST_URI};
        my $httpAccept = $rtest->{HTTP_ACCEPT};
        my $expected = $rtest->{expected};
        my $resolution = $resolver->resolve($requestUri, $httpAccept);
        print Dumper($resolution) if $verbose;

        ok( $resolution->{status} eq 'redirect', "$requestUri causes redirect" );
        ok( $resolution->{target} eq $expected, "$requestUri => $expected" );
    }
}

#-------------------------------------------------------------------------------
# Remote tests - test against a remote service.

# Read in the list of tests
my $tests = Load(do {
    local $/ = undef;
    my $fn = "tests.yaml";
    open my $F, "<", $fn or die "Can't read $fn";
    <$F>;
});
print Dumper($tests) if $verbose;


foreach my $test (@$tests) {
    if ($run_remote || $run_tests{$test->{name}}) {
        test_one($test);
    }
}



done_testing();


# Run one test
sub test_one {
    my $test = shift;
    my $test_name = $test->{name};
    my $request = $test->{request} || {};
    my $expected = $test->{expected};

    my $request_method = 'GET';
    if ($request->{method}) {
        $request_method = $request->{method};
        delete $request->{method};
    }

    my $path = '/';
    if ($request->{path}) {
        $path = $request->{path};
        delete $request->{path};
    }

    my @http_headers = ();
    if (my $accept = $request->{accept}) {
        push @http_headers, ('Accept', $accept);
        delete $request->{accept};
    }

    my $test_url = $url . $path;

    print "\$request: " . Dumper($request) if $verbose;

    # Execute the request; either GET or POST
    my $response;
    if ($request_method eq 'GET') {
        # Construct the GET URL from the request parameters
        my $get_url = $test_url . ((keys $request == 0) ? '' :
            '?' . join('&', map {
                $_ . '=' . uri_encode($request->{$_})
            } keys $request));
        print "Testing $test_name: $request_method: $get_url\n" if $verbose;
        #$response = $ua->get($get_url, 'Accept', "text/html");
        my $request = HTTP::Request->new(
            GET => $get_url,
            \@http_headers
        );
        $response = $ua->simple_request($request);
    }
    else {
        if ($verbose) {
            print "Testing $test_name: ". $request_method . ":\n";
            print "  " . join("\n  ", map {
                    "$_=" . ($_ eq 'q' ? string_start($request->{$_}) : $request->{$_})
                } keys %$request) . "\n";
        }
        $response = $ua->post($test_url, $request);
    }

    my $expected_code = $expected->{code} || 200;
    is ($response->code(), $expected_code, 
        "Test $test_name: got expected response code $expected_code");

    #ok (!$response->is_error(), "Good response for $filename") or
    #    diag("  Response status line was '" . $response->status_line . "'");

    my $content  = $response->decoded_content();
    if ($verbose) {
        print "  returned '" . string_start($content) . "'\n";
    }

    if ($expected->{'content-contains'}) {
        ok (index($content, $expected->{'content-contains'}) != -1,
            "Test $test_name: response contains expected string");
    }

    my $resp_content_type = $response->header('content-type');
    if (my $expected_content_type = $expected->{'content-type'}) {
        is ($resp_content_type, $expected_content_type,
            "Test $test_name: expected content-type: " . $expected_content_type);
    }
    if (my $exp_media_type = $expected->{'content-type-media'}) {
        (my $resp_media_type = $resp_content_type) =~ s/;.*//;
        is ($resp_media_type, $exp_media_type,
            "Test $test_name: expected content media type: " . $exp_media_type);
    }

    if (my $exp_location = $expected->{location}) {
        my $resp_location = $response->header('location');
        is ($resp_location, $exp_location,
            "Test $test_name: expected location '$exp_location'");
    }
}




# This is for printing out a long string.  If it is > 100 characters, it is
# truncated, and an ellipsis ("...") is added.
sub string_start {
    my $s = shift;
    chomp $s;
    my $ss = substr($s, 0, 100);
    $ss =~ s/\n/\\n/gs;
    return $ss . (length($s) > 100 ? "..." : "");
}



