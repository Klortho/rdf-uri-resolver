# NCBI RDF URI Resolver

## Configuring / adding redirect rules

Edit the `config.xml` file to add redirect rules.  They are based on
regular expression matches of the URL, and should be self-explanatory.

The `example` project contains some examples:

* [http://rdf.ncbi.nlm.nih.gov/example/1/1234](http://rdf.ncbi.nlm.nih.gov/example/1/1234) redirects to
  [http://rdf.ncbi.nlm.nih.gov/example/target/1.html?id=1234](http://rdf.ncbi.nlm.nih.gov/example/target/1.html?id=1234).
* [http://rdf.ncbi.nlm.nih.gov/example/2/1234](http://rdf.ncbi.nlm.nih.gov/example/2/1234) redirects similarly, but
  the file extension of the target file depends on the http accept header.

To get the redirects to depend on the HTTP Accept header, all an entry to the
`<mime-extensions>` at the top, and then add extension that you want to support to
the `target-mime-extensions` in the project's config section.

For example, PubChem supports redirecting to a different URL depending on the Accept header
value. This project's config section contains the following (note that
`n3` is in the list of target extensions):

```xml
<!-- pubchem, generic pattern sends everything to their server -->
<redirect pattern='/(.+)'
          target='http://pubchem.ncbi.nlm.nih.gov/rest/rdf/$1'
          target-mime-extensions='jsonld,json,html,turtle,ntriples,rdf,n3'/>
```

Therefore, if the following request is made:

* URL: http://rdf.ncbi.nlm.nih.gov/pubchem/compound/CID2244
* HTTP Accept header: "text/n3"

It will redirect to http://pubchem.ncbi.nlm.nih.gov/rest/rdf/compound/CID2244.n3


## Testing

### Automated test script

Run ./test.pl <testnum> from the command line.  Give the `--help` parameter for
usage information.  It includes two types of tests: local and remote.  Note that
the remote tests can be executed against the service running on some other
server.


### Debugging from command line

You can run it from the command line, to test a particular URI, like
this:

    REQUEST_URI=/example/1/1234 ./index.cgi

To get verbose debugging messages:

    REQUEST_URI=/example/1/1234 ./index.cgi --debug

To spoof the Accept header:

    REQUEST_URI=/example/2/1234 HTTP_ACCEPT=application/rdf+xml ./index.cgi

### Test server

Before deploying, you can set this up to run in a test server environment
by, for example, putting a softlink in your server's DOCUMENT_ROOT to
this repository, and then accessing, for example,

    http://localhost/rdf-uri-resolver/index.cgi/example/1/1234

The part of the URL after the script name corresponds to path portion
of the real RDF URI.


### Post-deployment checks

Verify that each of these works as expected

```
curl -v -L -o vocabulary.owl \
  http://rdf.ncbi.nlm.nih.gov/pubchem/vocabulary
```

```
curl -v -L -H "Accept: application/rdf+xml" -o CID2244.rdf \
  http://rdf.ncbi.nlm.nih.gov/pubchem/compound/CID2244
```

```
curl -v -L -H "Accept: text/html" -o CID2244.html \
  http://rdf.ncbi.nlm.nih.gov/pubchem/compound/CID2244
```

```
curl -v -L -H "Accept: text/turtle" -o CID2244.ttl \
  http://rdf.ncbi.nlm.nih.gov/pubchem/compound/CID2244
```

```
curl -v -L -H "Accept: application/json" -o CID2244.json \
  http://rdf.ncbi.nlm.nih.gov/pubchem/compound/CID2244
```

```
curl -v -L -H "Accept: text/plain" -o CID2244.ntriples \
  http://rdf.ncbi.nlm.nih.gov/pubchem/compound/CID2244
```

The default is RDF/XML:

```
curl -v -L -o CID2244 \
  http://rdf.ncbi.nlm.nih.gov/pubchem/compound/CID2244
```

