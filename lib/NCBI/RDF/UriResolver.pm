package NCBI::RDF::UriResolver;
# This is the main module for the RDF URIResolver script.

use Moose;
use MooseX::StrictConstructor;
use XML::LibXML;


my $READ_CONFIG_INTERVAL = 10;

# These are not used anymore:
#my %mimeTypes = (
#    'rdf'    => 'application/rdf+xml,application/xml,text/xml',
#    'rdfxml' => 'application/rdf+xml,application/xml,text/xml',
#    'xml'    => 'application/rdf+xml,application/xml,text/xml',
#    'rdfxml-abbrev' => 'application/rdf+xml+abbrev',
#    'json'   => 'application/json',
#    'ttl'    => 'text/turtle',
#    'turtle' => 'text/turtle',
#    'n3' => 'text/n3',
#    'jsonld' => 'application/x-json+ld',
#    'ldjson' => 'application/x-json+ld',
#    'json-ld' => 'application/x-json+ld',
#    'ld-json' => 'application/x-json+ld',
#    'html'   => 'application/xhtml+xml,text/html',
#    'htm'   => 'application/xhtml+xml,text/html',
#    'ntriples' => 'text/plain',
#);

with qw(
    PMC::MooseX::FastCGI
);

use Config::Any;
use Data::Dumper;

# Debug flag
has debug => (
    is => 'rw',
    isa => 'Int',
    default => 0,
);

# The last time the config file was read
has config_read_at => (
    is => 'rw',
    isa => 'Int'
);

# The name of the config file
has config_file => (
    is => 'rw',
    isa => 'Str',
    default => 'config.xml',
    # Here's how to get it to default to the name of the script but with
    # the '.conf' extension.
    # sub {
    #     (my $name = $0) =~ s/\.[^\.]*$//;
    #     $name . ".conf";
    # },
);

# The configuration data, as read in from the config file
has config => (
    is => 'rw',
    isa => 'HashRef'
);

has new_config => (
    is => 'rw',
    isa => 'HashRef',
);




# This reads the config file if it's never been read before, or if
# $READ_CONFIG_INTERVAL seconds have elapsed.
sub read_config_if_necessary {
    my ($self) = @_;

    return if $self->config_read_at &&
              ($self->config_read_at + $READ_CONFIG_INTERVAL > time());

    my $config_file = $self->config_file;
    die "$config_file not found\n" if !-r $config_file;

    # New config file parsing
    my $configElem = XML::LibXML->load_xml(location => $config_file)->documentElement();

    my $newConfig = {};

    # Get the mime-extensions
    my $mimeExts = $newConfig->{'mime-extensions'} = [];
    # Hash to cross-reference from extension to accept header
    my $ext2Accept = $newConfig->{'extension-to-accept'} = {};
    my $mimeExtsElem = $configElem->getChildrenByTagName('mime-extensions')->[0];
    foreach my $mimeExtElem ($mimeExtsElem->getChildrenByTagName('mime-extension')) {
        my @exts = split /,/, $mimeExtElem->getAttribute('extensions');
        my $mimeTypes = $mimeExtElem->getAttribute('mime-types');
        my $mimeExt = {
            'extensions' => [ @exts ],
            'mime-types' => [ split /,/, $mimeTypes ],
        };
        map {
            $ext2Accept->{$_} = $mimeTypes;
        } @exts;
        push @$mimeExts, $mimeExt;
    }

    # Get the projects
    my $projects = $newConfig->{projects} = {};
    foreach my $projElem ($configElem->getChildrenByTagName('project')) {
        my $projConfig = $projects->{$projElem->getAttribute('name')} = {};

        # Get each redirect
        my $redirects = $projConfig->{redirects} = [];
        foreach my $redirectElem ($projElem->getChildrenByTagName('redirect')) {
            my $r = {
                'pattern' => $redirectElem->getAttribute('pattern'),
                'target' => $redirectElem->getAttribute('target'),
            };
            push @$redirects, $r;

            my $mimeExts = $redirectElem->getAttribute('target-mime-extensions');
            if ($mimeExts) {
                $r->{'mime-exts'} = $mimeExts;
            }

            my @acceptElems = $redirectElem->getChildrenByTagName('accept');
            if (@acceptElems) {
                my $accepts = $r->{'accepts'} = [];
                foreach my $acceptElem (@acceptElems) {
                    push @$accepts, {
                        'values' => $acceptElem->getAttribute('values'),
                        'target' => $acceptElem->getAttribute('target'),
                    };
                }
            }
        }
    }

    $self->config_read_at(time());
    $self->config($newConfig);
}

# Initialize the FCGI
sub fastcgi_init {
    my ($self) = shift;
    $self->read_config_if_necessary;
}

sub process_request {
    my ($self, $q) = @_;
    if ($self->debug) {
        print $q->header("text/plain");
        print "Environment Variables:\n";
        foreach my $ev (keys %ENV) {
            print "  $ev: '" . $ENV{$ev} . "'\n";
        }
        print "----------------------\n";
    }

    $self->read_config_if_necessary;

    # Use SCRIPT_URI to get the scheme (http or https)
    my $https =
        (exists $ENV{HTTPS} && $ENV{HTTPS}) ||
        (exists $ENV{SCRIPT_URL} && ($ENV{SCRIPT_URL} =~ /^https:/i)) ||
        (exists $ENV{HTTP_X_FORWARDED_PROTO} && ($ENV{HTTP_X_FORWARDED_PROTO} =~ /^https/i));
    print "https:  $https\n" if $self->debug;

    # Parse the request URL.  This script should work identically in any of
    # several different environments (for debugging purposes).  E.g.
    #     http://foo.bar/cfm/web/rdf/index.cgi/project/resource
    #     http://rdf.ncbi.nlm.nih.gov/project/resource
    #     http://rdf.ncbi.nlm.nih.gov/index.fcgi/project/resource

    # Depending on the Apache rules that get us here, the environment variables
    # might vary widely.  Usually use REQUEST_URI, except in the real production
    # server, through NCBI web fronts.  In that case, use HTTP_CAF_URL.
    # For example, for the URL http://rdf.ncbi.nlm.nih.gov/example/vocabulary:
    #    REQUEST_URI: '/rdf/example/vocabulary'
    #    HTTP_CAF_URL: 'http://rdf.ncbi.nlm.nih.gov/example/vocabulary'

    my $requestUri;
    if (exists($ENV{HTTP_CAF_URL})) {
        $requestUri = $ENV{HTTP_CAF_URL};
        $requestUri =~ s/^https?:\/\/[^\/]*//;
    }
    else {
        $requestUri = $ENV{REQUEST_URI};
    }
    print "requestUri = $requestUri\n" if $self->{debug};

    # Get the list of mime types this client accepts
    my $httpAccept = $ENV{HTTP_ACCEPT};

    my $resolution = $self->resolve($requestUri, $httpAccept);
    print '$resolution: ' . Dumper($resolution) if $self->{debug};
    if ($resolution->{status} eq 'error') {
        $self->badUrl($q, $resolution->{message});
        return;
    }
    if ($resolution->{status} eq 'redirect') {
        my $target = $resolution->{target};
        # Preserve the 'https' scheme, if used:
        $target =~ s/^http/https/ if $https;
        print "target: $target\n" if $self->debug;
        print $q->redirect(
            -uri => $target,
            -status => '303 See Other',
        );
        return;
    }

    return;
}

#-------------------------------------------------------------
# This does the main work
sub resolve {
    my ($self, $requestUri, $httpAccept) = @_;
    $httpAccept ||= '';   # gets rid of warning about uninitialized value, when run from cmd line

    # Pull out the scriptUrl
    if (!$requestUri || $requestUri !~ s/
            (                      # start of the script url (which might be just a slash)
              \/                   # always has a leading slash
              (rdf\/)?             # optional 'rdf' path prefix
              (.*index\.f?cgi\/)?  # optional path-to-script
            )
        //x)
    {
        return {
            'status' => 'error',
            'message' => 'Empty URL path',
        };
    }
    my $scriptUrl = $1;
    print "scriptUrl = $scriptUrl\n" if $self->{debug};

    # Get the project and the resource
    if ($requestUri !~ m/
            ([A-Za-z0-9_\-.]+)     # project
            (\/.*)                 # resource
        /x)
    {
        return {
            'status' => 'error',
            'message' => 'Missing project or resource',
        };
    }
    my $project   = $1;
    print "project = $project\n" if $self->{debug};
    my $resource  = $2;
    print "resource = $resource\n" if $self->{debug};

    # Validate
    if ( $resource =~ /\?/ ) {        # query strings are not allowed
        return {
            'status' => 'error',
            'message' => "Query strings are not allowed",
        };
    }

    # Find this project in the config file
    my $config = $self->config;
    my $projConfig = $config->{projects}{$project};
    if (!$projConfig) {
        return {
            'status' => 'error',
            'message' => "Can\'t find project $project",
        };
    }

    # Get the accept headers
    # If the resource URI had a recognized extension, then use that
    my @clientAccepts;
    my $ext2Accept = $config->{'extension-to-accept'};

    my $ext = $resource;
    $ext =~ s/.*\.(.+)/$1/;
    if ($ext && $ext2Accept->{$ext}) {
        $httpAccept = $ext2Accept->{$ext};
        $resource =~ s/(.*)\..+/$1/;
    }

    # FIXME:  this is very naive right now.  See issue #1.
    @clientAccepts = split /,/, $httpAccept;
    foreach my $ca (@clientAccepts) {
        # Get rid of any quality flag.  Note that this edits the array value in place.
        $ca =~ s/;.*//;
    }
    #print "\@clientAccepts = (" . (join ", ", @clientAccepts) . ")\n" if $self->debug;

    # Look for redirects
    foreach my $redirect (@{$projConfig->{redirects}}) {
        # Check if the URL matches the pattern
        my $pattern = $redirect->{pattern};
        if ($resource =~ m/^$pattern$/) {
            my $_1 = $1;
            my $_2 = $2;
            my $_3 = $3;

            # Default target is the one on the main <redirect> elements
            my $target = $redirect->{target};

            # If the target begins with a "/", then it is relative to the project's
            # directory on the server
            if ($target =~ /^\//) {
                $target = $scriptUrl . $project . $target;
            }

            # The 'target-mime-extensions' attribute is shorthand for a set of
            # accept children.  Implement that here.
            if ($redirect->{'mime-exts'}) {
                my @tmes = split /,/, $redirect->{'mime-exts'};
                my @newAccepts;
                foreach my $tme (@tmes) {
                    push @newAccepts, {
                        'target' => $target . '.' . $tme,
                        'values' => $config->{'extension-to-accept'}{$tme},
                    };
                }
                $redirect->{accepts} = \@newAccepts;
            }
            print Dumper($config) if $self->debug;

            # If there are <accept> children, then we'll try to do a match on
            # HTTP accept header
            my $matchAccepts = $redirect->{accepts};
            if ($matchAccepts) {
                # First construct a hash cross-referencing accept header values to
                # accept hashes.
                my %acceptVals;
                foreach my $matchAccept (@$matchAccepts) {
                    # Get the @values attribute as an array of mime types
                    my $mavals = $matchAccept->{values};
                    map { $acceptVals{$_} = $matchAccept } (split /,/, $mavals);
                }
                #print "acceptVals = (" . (join ", ", keys %acceptVals) . ")\n" if $self->debug;

                # Now find the first client-provided accept type that work
                my ($ca) = grep {exists $acceptVals{$_}} @clientAccepts;
                if ($ca) {
                    $target = $acceptVals{$ca}{target};
                }
            }

            $target =~ s/\$1/$_1/;
            $target =~ s/\$2/$_2/;
            $target =~ s/\$3/$_3/;

            return {
                status => 'redirect',
                target => $target,
            };
        }
    }

    return {
        status => 'error',
        message => 'No match found for this URL.',
    };
}

#-------------------------------------------------------------
sub badUrl {
    my ($self, $q, $msg) = @_;
    print $q->header(-type => "text/plain",
                     -status => "404 Not found",);
    print "404 Not found.\n\n$msg\n";
}

1;
