#!/opt/perl-5.8.8/bin/perl -w

use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/lib";
use aliased 'NCBI::RDF::UriResolver';

my $resolver = UriResolver->new;
$resolver->debug(1) if ($ARGV[0] && $ARGV[0] eq '--debug');
$resolver->run;

