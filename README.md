## ⚠ This repository is no longer mantained
Dutch government has changed (and greatly improved) its open data service which now completely overshadows this project. This repository now only serves as an artifact of history.

BWB Mirror
===============
This project contains some scripts to clone Dutch laws from the official government CRM to a CouchDB database. The 
resulting database is faster, easier to use and keeps track of laws through time. We also generate a table of contents.

Motivation
----------
While the Dutch government publishes Dutch laws through their own BWB service, some problems exist with it:

* The service is very slow
* Only one version of a law (the current) is available; there are no historical consolidations available
* Bulk requests are awkward (we can only download a 
  [metadata dump for all laws as a zip file](http://wetten.overheid.nl/BWBIdService/BWBIdList.xml.zip))

While the [MetaLex Document Server](http://doc.metalex.eu/) solves the first two of these problems, and arguably the 
third, it also introduces problems, like it performs destructive XML transforations and throws away the source material. 
Also, the MDS has not been updated since April 2014. 

Updater usage
-------------

### Docker

Install [Docker](https://www.docker.com/).
 
```sh
# Run from Docker registry
docker run \
       -ti \
       -e COUCH_URL_WETTEN={COUCHDB_URL} \
       -e COUCH_USER_WETTEN={COUCHDB_USERNAME} \
       -e COUCH_PASSWORD_WETTEN={COUCHDB_PASSWORD} \
       digitalheir/bwb-cloner
```

### Manual
Install [Ruby 2.1.6](https://www.ruby-lang.org/)

Set environment variables: 

|                         |                               |
| ---                     | ---                           |
| `COUCH_URL_WETTEN`      | URL to a CouchDB database     |
| `COUCH_USER_WETTEN`     | username for CouchDB database |
| `COUCH_PASSWORD_WETTEN` | password for CouchDB database |

Run script: 

```sh
gem install bundler
bundle install
ruby update_couch_db
```

Database usage
--------------
The reference database is hosted at [https://wetten.cloudant.com/](https://wetten.cloudant.com/). Read access is public. 

Following the standard [CouchDB Document API](https://wiki.apache.org/couchdb/HTTP_Document_API), one may access any 
document through the `_all_docs` view with some query parameters set, .e.g,:
[`https://wetten.cloudant.com/bwb/_all_docs?limit=10&startkey="BWBR0002178"&endkey="BWBR0002179"`](https://wetten.cloudant.com/bwb/_all_docs?limit=10&startkey="BWBR0002178"&endkey="BWBR0002179")

This will show full documents, but we may be interested in just the metadata. I have defined some additional views:

| View name          | Description                                                                                          | Example                                                                                                                                                                                 |
| ---                | ---                                                                                                  | ---                                                                                                                                                                                     |
| `all_from_metalex` | Like `all`, but shows only index files that have been converted from MetaLex                         | [http://wetten.cloudant.com/bwb/_design/RegelingInfo/_view/all_from_metalex?limit=10](http://wetten.cloudant.com/bwb/_design/RegelingInfo/_view/all_from_metalex?limit=10)              |
| `all_non_metalex`  | Like `all`, but shows only index files that have *not* been converted from MetaLex                   | [http://wetten.cloudant.com/bwb/_design/RegelingInfo/_view/all_non_metalex?limit=10](http://wetten.cloudant.com/bwb/_design/RegelingInfo/_view/all_non_metalex?limit=10)                |
| `countKinds`       | Summary showing the number of documents pertaining to a certain kind (e.g.: law, circulaire, etc.)   | [http://wetten.cloudant.com/bwb/_design/RegelingInfo/_view/countKinds](http://wetten.cloudant.com/bwb/_design/RegelingInfo/_view/countKinds)                                            |

Some technical notes
--------------------
Documents are stored as CouchDB JSON-files with metadata fields that are not *exactly* the same as the XML elements. 
Compare `XmlConstants.rb` with `JsonConstants.rb`. An attachment called `data.xml` contains the document content, 
unsurprisingly in XML format. Document IDs are of the form `{BWBID}:{EXPRESSION DATE}`, where the expression date is 
specified by the field `datumLaatsteWijzing` (date last modified).

Note that a field called "xml" has been added to the documents, which should always be `null`. This is a remnant of 
early iterations of the database in which document content was inlined along with the metadata. The reasoning was 
that bulk requests are easier this way. However, metadata does not get compressed, as attachments do. Also inlining XML 
made it harder to query documents just for their metadata, needing secondary queries.
