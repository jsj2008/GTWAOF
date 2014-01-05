GTWAOF
======

An append-only RDF quad-store implementation in Objective-C.
---------------

The code depends on the [SPARQLKit](https://github.com/kasei/SPARQLKit) and [GTWSWBase](https://github.com/kasei/GTWSWBase) frameworks.


### Command Line Use Examples

```
% gtwaof -s foaf.db import foaf.ttl
% ./build/Release/gtwaof -s test.db export '' '<http://www.w3.org/1999/02/22-rdf-syntax-ns#type>' '<http://xmlns.com/foaf/0.1/Person>'
Last-Modified: 2014-01-04T13:29:03-0800

_:b5 <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <http://xmlns.com/foaf/0.1/Person> <http://base.example.org/> .
_:b6 <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <http://xmlns.com/foaf/0.1/Person> <http://base.example.org/> .
_:b7 <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <http://xmlns.com/foaf/0.1/Person> <http://base.example.org/> .
_:b8 <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <http://xmlns.com/foaf/0.1/Person> <http://base.example.org/> .
_:b9 <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <http://xmlns.com/foaf/0.1/Person> <http://base.example.org/> .
<http://kasei.us/about/#greg> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <http://xmlns.com/foaf/0.1/Person> <http://base.example.org/> .
export time: 0.009460
```
