//
//  GTWTermIDGenerator.h
//  GTWAOF
//
//  Created by Gregory Williams on 12/28/13.
//  Copyright (c) 2013 Gregory Todd Williams. All rights reserved.
//
//  Based on the NodeID bit-packing design of Apache Jena TDB <http://svn.apache.org/repos/asf/jena/trunk/jena-tdb/src/main/java/com/hp/hpl/jena/tdb/store/NodeId.java>

#import <Foundation/Foundation.h>
#import <GTWSWBase/GTWSWBase.h>

@interface GTWTermIDGenerator : NSObject {
    NSInteger _nextID;
}

@property (readwrite) NSInteger nextID;

- (GTWTermIDGenerator*) initWithNextAvailableCounter:(NSInteger)nextID;
- (NSData*) identifierForTerm:(id<GTWTerm>)term assign:(BOOL)assign;
- (id<GTWTerm>) termForIdentifier:(NSData*)ident;

@end

/*
 SPARQL Sort Order:
 blank
 iri
 literal (sub-types don't have a defined order in SPARQL)
 simple
 language tagged
 datatyped
 
 Assigning node IDs that will partition node values by their SPARQL sort order
 will allow an adaptive sort algorithm (like smoothsort) to take advantage of the
 partially ordered results that are returned from an underlying triplestore
 that sorts by node ID.
 
 Local Node ID:
 Offset	Length	Description
 0		3		Node Type. { 0: reserved 1: blank, 2: iri, 3: simple, 4: lang, 5: datatype, 6: variable, 7: reserved }
 3		1		(EF) =0; External flag set if node ID is not defined in the local triplestore (e.g. retrieved from a remote endpoint as part of a federated query)
 4		4		Node Subtype. >0 means inlined values. { 0: (non-inlined), 1: (fixed set), 2: xsd:date, 3: xsd:dateTime, 4: xsd:decimal, 5: xsd:integer, 6: literal, 7: reserved }
 8		56		Node Value
 
 Remote Node ID:
 Offset	Length	Description
 0		3		Node Type. { 1: blank, 2: iri, 3: simple, 4: lang, 5: datatype }
 3		1		(EF) =1; External flag set if node ID is not defined in the local triplestore (e.g. retrieved from a remote endpoint as part of a federated query)
 4		12		Endpoint ID; =0 if the value was locally defined but not in the triplestore (e.g. via a function like CONCAT())
 16		48		Node Value
 
 Inlined values:
 literal: depends on node type (set in 3 high bits)
 simple: chars in high bytes, NULL padded if necessary in the low bytes
 lang: high byte indicates language (based on lookup table). chars in high bytes of lower 48 bites, NULL padded if necessary in the low bytes
 datatype: xsd:string: chars in high bytes, NULL padded if necessary in the low bytes
 
 xsd:integer: 56-bit signed integer
 fixed set:
 0x00	= xsd:boolean false
 0x01	= xsd:boolean true
 0x02	= rdf:List
 0x03	= rdf:Resource
 0x04	= rdf:first
 0x05	= rdf:rest
 0x06	= rdf:type
 0x07	= rdfs:comment
 0x08	= rdfs:label
 0x09	= rdfs:seeAlso
 0x0A	= rdfs:isDefinedBy
 0x100	= rdf:_0 ... rdf:_128
 xsd:decimal: (identical layout to TDB within the lower 56 bits)
 // 8 bits of scale, signed 48 bits of value.
 xsd:dateTime: (identical layout to TDB within the lower 56 bits)
 // Bits 49-55 (7 bits)  : timezone -- 15 min precision + special for Z
 // Bits 27-48 (22 bits) : date, year is 13 bits = 8000 years  (0 to 7999)
 // Bits 0-26  (27 bits) : time, to milliseconds
 // Layout:
 // Hi: TZ YYYY MM DD HH MM SS.sss Lo:
 // YYYY:MM:DD => 13 bits year, 4 bits month, 5 bits day => 22 bits
 // HH:MM:SS.ssss => 5 bits H, 6 bits M, 16 bits S ==> 27 bits
 // TZ Z=0x7F, none=0x7E
 
 timezone byte layout (bytes 1-7):
 byte:  1         2         3         4         5         6         7
 field: ZZZZ ZZZY YYYY YYYY YYYY MMMM DDDD Dhhh hhmm mmmm ssss ssss ssss ssss
 
 
 SARG Thoughts:
 SARG types = node id range restrictions
 
 isBlank, isURI, isIRI, isLiteral can all become range restrictions on the node
 ids since node type is in the highest bits of node ids.
 
 isNumeric implies isLiteral (more specifically, type = NODE_TYPE_DATATYPE) and
 can partially use a range restriction for inlined integers and decimals (high
 byte of node id = [0xB4, 0xB5]). For non-inlined values, range restriction will
 narrow search scope by restricting to type = NODE_TYPE_DATATYPE and EF = 0
 (specifically, the high 4 bits of node id = 0xA).
 
 Node position in a triple can provide range restrictions:
 Subject: high 4 bits of node id <= 0x5
 Predicate: high 4 bits of node id = [0x4, 0x5]
 (Should use as a graph name imply an IRI? If so:)
 Graph: high 4 bits of node id = [0x4, 0x5]
 */

