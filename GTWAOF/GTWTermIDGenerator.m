//
//  GTWTermIDGenerator.m
//  GTWAOF
//
//  Created by Gregory Williams on 12/28/13.
//  Copyright (c) 2013 Gregory Todd Williams. All rights reserved.
//

#import "GTWTermIDGenerator.h"
#import <GTWSWBase/GTWIRI.h>
#import <GTWSWBase/GTWLiteral.h>
#import <GTWSWBase/GTWBlank.h>
#include <arpa/inet.h>

#define MAX_ORDINAL_VALUE	0x00FFFFFFFFFFFFFFLL
#define MAX_INTEGER_VALUE	0x00FFFFFFFFFFFFFFLL
#define ORDINAL_OFFSET		0x100

typedef enum {
	NODE_TYPE_BLANK		= 0x2,
	NODE_TYPE_IRI		= 0x4,
	NODE_TYPE_SIMPLE	= 0x6,
	NODE_TYPE_LANG		= 0x8,
	NODE_TYPE_DATATYPE	= 0xA,
	NODE_TYPE_VARIABLE	= 0xC
} node_type_t;

typedef enum {
	NODE_SUBTYPE_NONE		= 0x0,
	NODE_SUBTYPE_FIXED		= 0x1,
	NODE_SUBTYPE_DATE		= 0x2,
	NODE_SUBTYPE_DATETIME	= 0x3,
	NODE_SUBTYPE_DECIMAL	= 0x4,
	NODE_SUBTYPE_INTEGER	= 0x5,
	NODE_SUBTYPE_LITERAL	= 0x6,
    NODE_SUBTYPE_FLOAT      = 0x7,
} node_subtype_t;

static uint64_t NODE_ID_RDF_LIST			= 0x5100000000000002LL;
static uint64_t NODE_ID_RDF_RESOURCE		= 0x5100000000000003LL;
static uint64_t NODE_ID_RDF_FIRST			= 0x5100000000000004LL;
static uint64_t NODE_ID_RDF_REST			= 0x5100000000000005LL;
static uint64_t NODE_ID_RDF_TYPE			= 0x5100000000000006LL;
static uint64_t NODE_ID_RDFS_COMMENT		= 0x5100000000000007LL;
static uint64_t NODE_ID_RDFS_LABEL			= 0x5100000000000008LL;
static uint64_t NODE_ID_RDFS_SEEALSO		= 0x5100000000000009LL;
static uint64_t NODE_ID_RDFS_ISDEFINEDBY	= 0x510000000000000ALL;

static const char* RDF_LIST					= "http://www.w3.org/1999/02/22-rdf-syntax-ns#List";
static const char* RDF_RESOURCE				= "http://www.w3.org/1999/02/22-rdf-syntax-ns#Resource";
static const char* RDF_FIRST				= "http://www.w3.org/1999/02/22-rdf-syntax-ns#first";
static const char* RDF_REST					= "http://www.w3.org/1999/02/22-rdf-syntax-ns#rest";
static const char* RDF_TYPE					= "http://www.w3.org/1999/02/22-rdf-syntax-ns#type";
static const char* RDFS_COMMENT				= "http://www.w3.org/2000/01/rdf-schema#comment";
static const char* RDFS_LABEL				= "http://www.w3.org/2000/01/rdf-schema#label";
static const char* RDFS_SEEALSO				= "http://www.w3.org/2000/01/rdf-schema#seeAlso";
static const char* RDFS_ISDEFINEDBY			= "http://www.w3.org/2000/01/rdf-schema#isDefinedBy";

static int language_count	= 136;
static char* languages[]	= {
	NULL,
	"AA",
	"AB",
	"AF",
	"AM",
	"AR",
	"AS",
	"AY",
	"AZ",
	"BA",
	"BE",
	"BG",
	"BH",
	"BI",
	"BN",
	"BO",
	"BR",
	"CA",
	"CO",
	"CS",
	"CY",
	"DA",
	"DE",
	"DZ",
	"EL",
	"EN",	// 0x19
	"EO",
	"ES",
	"ET",
	"EU",
	"FA",
	"FI",
	"FJ",
	"FO",
	"FR",
	"FY",
	"GA",
	"GD",
	"GL",
	"GN",
	"GU",
	"HA",
	"HI",
	"HR",
	"HU",
	"HY",
	"IA",
	"IE",
	"IK",
	"IN",
	"IS",
	"IT",
	"IW",
	"JA",
	"JI",
	"JW",
	"KA",
	"KK",
	"KL",
	"KM",
	"KN",
	"KO",
	"KS",
	"KU",
	"KY",
	"LA",
	"LN",
	"LO",
	"LT",
	"LV",
	"MG",
	"MI",
	"MK",
	"ML",
	"MN",
	"MO",
	"MR",
	"MS",
	"MT",
	"MY",
	"NA",
	"NE",
	"NL",
	"NO",
	"OC",
	"OM",
	"OR",
	"PA",
	"PL",
	"PS",
	"PT",
	"QU",
	"RM",
	"RN",
	"RO",
	"RU",
	"RW",
	"SA",
	"SD",
	"SG",
	"SH",
	"SI",
	"SK",
	"SL",
	"SM",
	"SN",
	"SO",
	"SQ",
	"SR",
	"SS",
	"ST",
	"SU",
	"SV",
	"SW",
	"TA",
	"TE",
	"TG",
	"TH",
	"TI",
	"TK",
	"TL",
	"TN",
	"TO",
	"TR",
	"TS",
	"TT",
	"TW",
	"UK",
	"UR",
	"UZ",
	"VI",
	"VO",
	"WO",
	"XH",
	"YO",
	"ZH",
	"ZU",
};

static int language_code ( const char* lang ) {
	int i;
	static char uclang[3]	= { '\0', '\0', '\0' };
	if (strlen(lang) == 2) {
		uclang[0]	= toupper(lang[0]);
		uclang[1]	= toupper(lang[1]);
		for (i = 1; i <= language_count; i++) {
			if (strcmp(uclang, languages[i]) == 0)
				return i;
		}
	}
	return 0;
}

static node_type_t node_type ( NSData* data ) {
	unsigned char c	= ((const char*)data.bytes)[0];
	c	&= 0xe0;
	c	>>= 4;
	return (node_type_t) c;
}

static node_subtype_t node_subtype ( NSData* data ) {
	unsigned char c	= ((const char*)data.bytes)[0];
	c &= 0x0F;
	return (node_subtype_t) c;
}


@implementation GTWTermIDGenerator

- (GTWTermIDGenerator*) initWithNextAvailableCounter:(NSInteger)nextID {
    if (self = [self init]) {
        _nextID  = nextID;
    }
    return self;
}

- (GTWTermIDGenerator*) init {
    if (self = [super init]) {
        _nextID  = 1;
    }
    return self;
}

- (NSData*) identifierForTerm:(id<GTWTerm>)term assign:(BOOL)assign {
    NSData* ident   = nil;
    GTWTermType type        = [term termType];
    node_type_t nodetype;
    switch (type) {
        case GTWTermIRI:
            nodetype    = NODE_TYPE_IRI;
            ident		= [self pack_resource:[term value]];
            break;
        case GTWTermBlank:
            nodetype    = NODE_TYPE_BLANK;
            ident		= [self pack_blank:[term value]];
            break;
        case GTWTermLiteral:
            if (term.language) {
                nodetype    = NODE_TYPE_LANG;
                ident       =  [self pack_lang_literal:[term value] language:term.language];
            } else if (term.datatype) {
                nodetype    = NODE_TYPE_DATATYPE;
                NSString* datatype  = term.datatype;
                if ([datatype isEqualToString:@"http://www.w3.org/2001/XMLSchema#boolean"]) {
                    ident	= [self pack_boolean:[term value]];
                } else if ([datatype isEqualToString:@"http://www.w3.org/2001/XMLSchema#integer"]) {
                    ident	=  [self pack_integer:[term value]];
                } else if ([datatype isEqualToString:@"http://www.w3.org/2001/XMLSchema#decimal"]) {
                    ident	=  [self pack_decimal:[term value]];
                } else if ([datatype isEqualToString:@"http://www.w3.org/2001/XMLSchema#float"]) {
                    ident	=  [self pack_float:[term value]];
                } else if ([datatype isEqualToString:@"http://www.w3.org/2001/XMLSchema#string"]) {
                    ident	=  [self pack_string:[term value]];
                } else if ([datatype isEqualToString:@"http://www.w3.org/2001/XMLSchema#date"]) {
                    ident	=  [self pack_date:[term value]];
                } else if ([datatype isEqualToString:@"http://www.w3.org/2001/XMLSchema#dateTime"]) {
                    ident	=  [self pack_dateTime:[term value]];
                }
            } else {
                nodetype    = NODE_TYPE_SIMPLE;
                ident		= [self pack_simple:[term value]];
            }
            break;
        default:
            NSLog(@"*** unknown node type %d in identifierForTerm:\n", (int)type);
            return nil;
    }
    
    if (assign && !ident) {
        ident   = [self newNodeIDOfType:nodetype];
    }
    
    if (ident && [ident length] != 8) {
        NSLog(@"Unexpected node ID: %@", ident);
        return nil;
    }
    
    return ident;
}

- (id<GTWTerm>) termForIdentifier:(NSData*)ident {
    if (![self identifierHasInlinedTerm:ident]) {
//        NSLog(@"ID %@ is not inlined", ident);
        return nil;
    }
    node_type_t type        = node_type(ident);
    node_subtype_t subtype	= node_subtype(ident);
    if (type == NODE_TYPE_BLANK) {
        return [self unpack_blank:ident];
    } else if (type == NODE_TYPE_IRI) {
        if (subtype == NODE_SUBTYPE_FIXED) {
            return [self unpack_resource:ident];
        } else if ([self identifierHasInlinedTerm:ident]) {
            NSLog(@"*** couldn't determine inlined iri value for id %@ in packed_node_id_to_term\n", ident);
            return nil;
        }
    } else if (type == NODE_TYPE_SIMPLE) {
        return [self unpack_simple:ident];
    } else if (type == NODE_TYPE_LANG) {
        return [self unpack_lang:ident];
    } else if (type == NODE_TYPE_DATATYPE) {
        if (subtype == NODE_SUBTYPE_DECIMAL) {
            return [self unpack_decimal:ident];
        } else if (subtype == NODE_SUBTYPE_FLOAT) {
            return [self unpack_float:ident];
        } else if (subtype == NODE_SUBTYPE_INTEGER) {
            return [self unpack_integer:ident];
        } else if (subtype == NODE_SUBTYPE_LITERAL) {
            // xsd:string
            return [self unpack_string:ident];
//        } else if (subtype == NODE_SUBTYPE_DATE) {
//            uint16_t year	= inlined_datetime_year( id );
//            uint16_t month	= inlined_datetime_month( id );
//            uint16_t day	= inlined_datetime_day( id );
//            char* value		= malloc(11);
//            snprintf( value, 11, "%04"PRIu16"-%02"PRIu16"-%02"PRIu16"", year, month, day );
//            gtw_term* term	= gtw_new_term(type, value, NULL, "http://www.w3.org/2001/XMLSchema#date");
//            free(value);
//            return term;
//        } else if (subtype == NODE_SUBTYPE_DATETIME) {
//            uint16_t year	= inlined_datetime_year( id );
//            uint16_t month	= inlined_datetime_month( id );
//            uint16_t day	= inlined_datetime_day( id );
//            uint16_t hours	= inlined_datetime_hours( id );
//            uint16_t min	= inlined_datetime_minutes( id );
//            uint16_t ms		= inlined_datetime_milliseconds( id );
//            int8_t tz		= inlined_datetime_timezone( id );
//            float sec		= (ms / 1000.0);
//            char* timezone	= calloc(1,8);
//            if (tz == '\377') {
//                sprintf(timezone, "Z");
//            } else if (tz == '\376') {
//                timezone[0]	= '\0';
//            } else {
//                int tzmin	= abs((tz % 4) * 15);
//                int tzhour	= abs(tz / 4);
//                sprintf(timezone, "%c%02d:%02d", (tz < 0 ? '-' : '+'), tzhour, tzmin);
//            }
//            char* value		= malloc(64);
//            snprintf( value, 64, "%04"PRIu16"-%02"PRIu16"-%02"PRIu16"T%02"PRIu16":%02"PRIu16":%s%f%s", year, month, day, hours, min, ((sec < 10.0) ? "0" : ""), sec, timezone );
//            gtw_term* term	= gtw_new_term(type, value, NULL, "http://www.w3.org/2001/XMLSchema#date");
//            free(value);
//            return term;
        } else if (subtype == NODE_SUBTYPE_FIXED) {
            // boolean
            return [self unpack_boolean:ident];
        } else {
            fprintf( stderr, "*** (datatype literal)\n" );
        }
//    } else if (id.value == htonll(NODE_ID_DEFAULT_GRAPH)) {
//        return NULL;
    } else {
        NSLog(@"*** unknown node type in packed_node_id_to_term: %@\n", ident);
    }
    return nil;
}

#pragma mark -

- (GTWIRI*) unpack_resource:(NSData*)ident {
    uint64_t idvalue;
    [ident getBytes:&idvalue length:8];
    char* ip    = (char*)&idvalue;
    uint64_t value  = NSSwapBigLongLongToHost(idvalue);

    const char* string  = NULL;
	if (value == NODE_ID_RDF_LIST) {
        string  = RDF_LIST;
	} else if (value == NODE_ID_RDF_RESOURCE) {
        string  = RDF_RESOURCE;
	} else if (value == NODE_ID_RDF_FIRST) {
        string  = RDF_FIRST;
	} else if (value == NODE_ID_RDF_REST) {
        string  = RDF_REST;
	} else if (value == NODE_ID_RDF_TYPE) {
        string  = RDF_TYPE;
	} else if (value == NODE_ID_RDFS_COMMENT) {
        string  = RDFS_COMMENT;
	} else if (value == NODE_ID_RDFS_LABEL) {
        string  = RDFS_LABEL;
	} else if (value == NODE_ID_RDFS_SEEALSO) {
        string  = RDFS_SEEALSO;
	} else if (value == NODE_ID_RDFS_ISDEFINEDBY) {
        string  = RDFS_ISDEFINEDBY;
	} else {
        ip[0]   = 0;
        uint64_t ord	= NSSwapBigLongLongToHost(idvalue);
		if (ord >= ORDINAL_OFFSET) {
            GTWIRI* i   = [[GTWIRI alloc] initWithValue:[NSString stringWithFormat:@"http://www.w3.org/1999/02/22-rdf-syntax-ns#_%"PRIu64"", ord-ORDINAL_OFFSET]];
        //    NSLog(@"unpacked ordinal IRI: %@", i);
            return i;
		} else {
			return NULL;
		}
	}
    
    if (string) {
        GTWIRI* i   = [[GTWIRI alloc] initWithValue:[NSString stringWithFormat:@"%s", string]];
    //    NSLog(@"unpacked IRI: %@", i);
        return i;
    } else {
        return nil;
    }
}

- (GTWBlank*) unpack_blank:(NSData*)ident {
    uint64_t idvalue;
    [ident getBytes:&idvalue length:8];
    char* ip    = (char*)&idvalue;
	ip[0]	= '\0';
	uint64_t v	= NSSwapBigLongLongToHost(idvalue);
    return [[GTWBlank alloc] initWithValue:[NSString stringWithFormat:@"gtw_%"PRIu64"", v]];
}

- (GTWLiteral*) unpack_simple:(NSData*)ident {
    NSData* data    = [ident subdataWithRange:NSMakeRange(1, 7)];
    GTWLiteral* l   = [[GTWLiteral alloc] initWithValue:[NSString stringWithCString:data.bytes encoding:NSUTF8StringEncoding]];
//    NSLog(@"unpacked simple literal: %@ (from data %@)", l, data);
    return l;
}

- (GTWLiteral*) unpack_string:(NSData*)ident {
    NSData* data    = [ident subdataWithRange:NSMakeRange(1, 7)];
    GTWLiteral* l   = [[GTWLiteral alloc] initWithValue:[NSString stringWithCString:data.bytes encoding:NSUTF8StringEncoding] datatype:@"http://www.w3.org/2001/XMLSchema#string"];
//    NSLog(@"unpacked xsd:string literal: %@ (from data %@)", l, data);
    return l;
}

- (GTWLiteral*) unpack_lang:(NSData*)ident {
	unsigned char code	= ((const char*)ident.bytes)[1];
	const char* lang    = languages[code];
    NSData* data    = [ident subdataWithRange:NSMakeRange(2, 6)];
    GTWLiteral* l   = [[GTWLiteral alloc] initWithValue:[NSString stringWithCString:data.bytes encoding:NSUTF8StringEncoding] language:[NSString stringWithFormat:@"%s", lang]];
//    NSLog(@"unpacked lang literal: %@", l);
    return l;
}

- (GTWLiteral*) unpack_decimal:(NSData*)ident {
    uint64_t idvalue;
    [ident getBytes:&idvalue length:8];
    char* ip    = (char*)&idvalue;
    char scale      = ip[1];
	ip[0]			= 0x0;
	ip[1]			= 0x0;
	if (ip[2] & 0x80) {
		ip[0]	= (char) 0xFF;
		ip[1]	= (char) 0xFF;
	}
	int64_t value	= NSSwapBigLongLongToHost(idvalue);
    
    GTWLiteral* l   = [[GTWLiteral alloc] initWithValue:[NSString stringWithFormat:@"%"PRId64"E%d", value, (int)scale] datatype:@"http://www.w3.org/2001/XMLSchema#decimal"];
//    NSLog(@"unpacked decimal literal: %@", l);
    return l;
}

- (GTWLiteral*) unpack_float:(NSData*)ident {
    NSData* data    = [ident subdataWithRange:NSMakeRange(1, 7)];
    GTWLiteral* l   = [[GTWLiteral alloc] initWithValue:[NSString stringWithCString:data.bytes encoding:NSUTF8StringEncoding] datatype:@"http://www.w3.org/2001/XMLSchema#float"];
    //    NSLog(@"unpacked simple literal: %@ (from data %@)", l, data);
    return l;
}

- (GTWLiteral*) unpack_integer:(NSData*)ident {
    uint64_t idvalue;
    [ident getBytes:&idvalue length:8];
    char* ip    = (char*)&idvalue;

	ip[0]		= 0x0;
	uint64_t value	= NSSwapBigLongLongToHost(idvalue);

    GTWLiteral* l   = [[GTWLiteral alloc] initWithValue:[NSString stringWithFormat:@"%"PRId64"", value] datatype:@"http://www.w3.org/2001/XMLSchema#integer"];
//    NSLog(@"unpacked integer literal: %@", l);
    return l;
}

- (GTWLiteral*) unpack_boolean:(NSData*)ident {
    char b;
    [ident getBytes:&b length:1];
    GTWLiteral* l;
    if (b) {
        l   = [GTWLiteral trueLiteral];
    } else {
        l   = [GTWLiteral falseLiteral];
    }
//    NSLog(@"unpacked boolean literal: %@", l);
    return l;
}

#pragma mark -

- (NSData*) pack_resource:(NSString*) value {
    if ([value hasPrefix:@"http://www.w3.org/1999/02/22-rdf-syntax-ns#"]) {
        NSString* local = [value substringFromIndex:43];
		// RDF: Terms
        uint64_t identValue  = 0;
        if ([local isEqualToString:@"type"]) {
            identValue  = NSSwapHostLongLongToBig(NODE_ID_RDF_TYPE);
		} else if ([local isEqualToString:@"first"]) {
            identValue  = NSSwapHostLongLongToBig(NODE_ID_RDF_FIRST);
		} else if ([local isEqualToString:@"rest"]) {
            identValue  = NSSwapHostLongLongToBig(NODE_ID_RDF_REST);
		} else if ([local isEqualToString:@"List"]) {
            identValue  = NSSwapHostLongLongToBig(NODE_ID_RDF_LIST);
		} else if ([local isEqualToString:@"Resource"]) {
            identValue  = NSSwapHostLongLongToBig(NODE_ID_RDF_RESOURCE);
		}
        
        if (identValue > 0) {
            NSData* data    = [NSData dataWithBytes:&identValue length:8];
            return data;
        }
		
        if ([value hasPrefix:@"http://www.w3.org/1999/02/22-rdf-syntax-ns#_"]) {
            NSString* number    = [value substringFromIndex:44];
            long ord            = atol([number UTF8String]);
			return [self pack_ordinal: (uint64_t)ord];
		}
	} else if ([value hasPrefix:@"http://www.w3.org/2000/01/rdf-schema#"]) {
        NSString* local = [value substringFromIndex:37];
		// RDFS: Terms
        uint64_t identValue  = 0;
        if ([local isEqualToString:@"label"]) {
			identValue	= NSSwapHostLongLongToBig(NODE_ID_RDFS_LABEL);
		} else if ([local isEqualToString:@"comment"]) {
			identValue	= NSSwapHostLongLongToBig(NODE_ID_RDFS_COMMENT);
		} else if ([local isEqualToString:@"seeAlso"]) {
			identValue	= NSSwapHostLongLongToBig(NODE_ID_RDFS_SEEALSO);
		} else if ([local isEqualToString:@"isDefinedBy"]) {
			identValue	= NSSwapHostLongLongToBig(NODE_ID_RDFS_ISDEFINEDBY);
		}

        if (identValue > 0) {
            NSData* data    = [NSData dataWithBytes:&identValue length:8];
            return data;
        }
    }
	return nil;
}

- (NSData*) pack_blank:(NSString*) value {
    NSRange range = [value rangeOfString:@"^\\d+$" options:NSRegularExpressionSearch];
    if (range.location == 0 && range.length == value.length) {
        long long v = atoll([value UTF8String]);
		uint64_t bint	= (uint64_t) v;
        return [self newInlineNodeIDOfType:NODE_TYPE_BLANK subType:NODE_SUBTYPE_INTEGER value:&bint arg1:NULL arg2:NULL];
	}
	return nil;
}

- (NSData*) pack_lang_literal:(NSString*)value language:(NSString*)lang {
	int l	= 0;
	if ((l = language_code([lang UTF8String])) > 0 && [value length] <= 6) {
        NSData* ident   = [self newInlineNodeIDOfType:NODE_TYPE_LANG subType:NODE_SUBTYPE_LITERAL value:[value UTF8String] arg1:&l arg2:NULL];
		NSLog(@"Packed language literal: (%@) \"%@\" -> %@\n", lang, value, ident );
		return ident;
	}
	return nil;
}

- (NSData*) pack_boolean:(NSString*) value {
    if ([value isEqualToString:@"true"] || [value isEqualToString:@"1"]) {
		int v	= 1;
        NSData* ident   = [self newInlineNodeIDOfType:NODE_TYPE_DATATYPE subType:NODE_SUBTYPE_FIXED value:&v arg1:NULL arg2:NULL];
        NSLog(@"Packed boolean: %@ -> %@\n", value, ident );
		return ident;
	} else if ([value isEqualToString:@"false"] || [value isEqualToString:@"0"]) {
		int v	= 0;
        NSData* ident   = [self newInlineNodeIDOfType:NODE_TYPE_DATATYPE subType:NODE_SUBTYPE_FIXED value:&v arg1:NULL arg2:NULL];
        NSLog(@"Packed boolean: %@ -> %@\n", value, ident );
		return ident;
	}
	return nil;
}

- (NSData*) pack_integer:(NSString*) value {
	uint64_t i	= (uint64_t) atoll([value UTF8String]);
	if (i <= MAX_INTEGER_VALUE) {
        NSData* ident   = [self newInlineNodeIDOfType:NODE_TYPE_DATATYPE subType:NODE_SUBTYPE_INTEGER value:&i arg1:NULL arg2:NULL];
        NSLog(@"Packed integer: %@ -> %@\n", value, ident );
		return ident;
	}
	return nil;
}

- (NSData*) pack_decimal:(NSString*) value {
    NSRange range   = [value rangeOfString:@"^[-+]?(\\d+)[.](\\d+)$" options:NSRegularExpressionSearch];
    if (range.location == 0 && range.length == value.length) {
		// match
		char* newvalue	= malloc([value lengthOfBytesUsingEncoding:NSUTF8StringEncoding]);
		char* p			= newvalue;
		const char* q	= [value UTF8String];
		while (*q != '.')
			*(p++)	= *(q++);
		q++;
		const char* frac	= q;
		if (strlen(frac) >= 128) {
			fprintf(stderr, "*** decimal scale too large\n");
			free(newvalue);
			return nil;
		}
		char scale	= 0-strlen(frac);
		while (*q != '\0')
			*(p++)	= *(q++);
		*p	= '\0';
		int64_t v	= (int64_t) atoll(newvalue);
		if (v > 0x007fffffffffff || v < -0x007fffffffffff) {
#ifdef DEBUG
			fprintf(stderr, "*** decimal value too large %016"PRId64"\n",v);
#endif
			free(newvalue);
			return nil;
		}
		
        NSData* ident   = [self newInlineNodeIDOfType:NODE_TYPE_DATATYPE subType:NODE_SUBTYPE_DECIMAL value:&v arg1:&scale arg2:NULL];
        NSLog(@"Packed decimal: %lldE%d -> %@\n", v, (char)scale, ident );
		free(newvalue);
		return ident;
	}
    return nil;
}

- (NSData*) pack_float:(NSString*) value {
	if ([value lengthOfBytesUsingEncoding:NSUTF8StringEncoding] < 8) {
        NSData* ident   = [self newInlineNodeIDOfType:NODE_TYPE_DATATYPE subType:NODE_SUBTYPE_FLOAT value:[value UTF8String] arg1:NULL arg2:NULL];
        NSLog(@"Packed xsd:float: %@ -> %@\n", value, ident );
		return ident;
	}
    return nil;
}

- (NSData*) pack_string:(NSString*) value {
	if ([value lengthOfBytesUsingEncoding:NSUTF8StringEncoding] < 8) {
        NSData* ident   = [self newInlineNodeIDOfType:NODE_TYPE_DATATYPE subType:NODE_SUBTYPE_LITERAL value:[value UTF8String] arg1:NULL arg2:NULL];
        NSLog(@"Packed xsd:string: %@ -> %@\n", value, ident );
		return ident;
	}
    return nil;
}

- (NSData*) pack_date:(NSString*) value {
    // TODO: implement
    return nil;
}

- (NSData*) pack_dateTime:(NSString*) value {
    // TODO: implement
    return nil;
}

- (NSData*) pack_simple:(NSString*) value {
	if ([value lengthOfBytesUsingEncoding:NSUTF8StringEncoding] < 8) {
        NSData* ident   = [self newInlineNodeIDOfType:NODE_TYPE_SIMPLE subType:NODE_SUBTYPE_LITERAL value:[value UTF8String] arg1:NULL arg2:NULL];
        NSLog(@"Packed simple literal: %@ -> %@\n", value, ident );
		return ident;
	}
    return nil;
}

- (NSData*) pack_ordinal:(uint64_t)value {
	if (value <= MAX_ORDINAL_VALUE) {
        return [self newInlineNodeIDOfType:NODE_TYPE_IRI subType:NODE_SUBTYPE_FIXED value:&value arg1:NULL arg2:NULL];
	}
	return nil;
}

#pragma mark -

- (BOOL) identifierHasInlinedTerm:(NSData*)ident {
    uint64_t idvalue  = 0;
    [ident getBytes:&idvalue length:8];
    char* ip    = (char*)&idvalue;
    return (ip[0] & 0x0f) ? YES : NO;
}

- (NSData*) newNodeIDOfType:(node_type_t)type {
    uint64_t n      = (uint64_t) _nextID++;
    uint64_t idvalue    = NSSwapHostLongLongToBig(n);
    char* ip        = (char*)&idvalue;

    char byte0  = type;
	byte0		<<= 4;
    ip[0]       = byte0;
    
    NSData* ident    = [NSData dataWithBytes:&idvalue length:8];
//    NSLog(@"new non-inlined node: %@", ident);
    return ident;
}

- (NSData*) newInlineNodeIDOfType:(node_type_t)type subType:(node_subtype_t)subtype value:(const void*)value arg1:(const void*)arg1 arg2:(const void*)arg2 {
    uint64_t idvalue  = 0;
    char* ip    = (char*)&idvalue;
    char byte0  = type;
//	byte0		|= 0x00;
	byte0		<<= 4;
	byte0		|= subtype;
    ip[0]       = byte0;
    
	if (type == NODE_TYPE_BLANK) {
		if (subtype == NODE_SUBTYPE_INTEGER) {
			const uint64_t* p	= (const uint64_t*) value;
			uint64_t v	= (uint64_t)NSSwapHostLongLongToBig(*p);
            
			idvalue	|= v;
		} else {
			return nil;
		}
	} else if (type == NODE_TYPE_IRI) {
		uint64_t iri_value	= 0x0LL;
		if (subtype == NODE_SUBTYPE_FIXED) {
			const uint64_t ord	= *( (const uint64_t*) value );
			iri_value	= (uint64_t) ord + ORDINAL_OFFSET;
		} else if (strncmp(value, "http://www.w3.org/1999/02/22-rdf-syntax-ns#", 43) == 0) {
			// RDF: Terms
			if (strcmp(value, RDF_LIST) == 0) {
				iri_value	= 0x02LL;
			} else if (strcmp(value, RDF_RESOURCE) == 0) {
				iri_value	= 0x03LL;
			} else if (strcmp(value, RDF_FIRST) == 0) {
				iri_value	= 0x04LL;
			} else if (strcmp(value, RDF_REST) == 0) {
				iri_value	= 0x05LL;
			} else if (strcmp(value, RDF_TYPE) == 0) {
				iri_value	= 0x06LL;
			}
		} else if (strncmp(value, "http://www.w3.org/2000/01/rdf-schema#", 37) == 0) {
			// RDFS: Terms
			if (strcmp(value, RDFS_LABEL) == 0) {
				iri_value	= 0x08LL;
			} else if (strcmp(value, RDFS_COMMENT) == 0) {
				iri_value	= 0x07LL;
			} else if (strcmp(value, RDFS_SEEALSO) == 0) {
				iri_value	= 0x098LL;
			} else if (strcmp(value, RDFS_ISDEFINEDBY) == 0) {
				iri_value	= 0x0ALL;
			}
		}
		idvalue	|= NSSwapHostLongLongToBig(iri_value);
	} else if (type == NODE_TYPE_SIMPLE) {
		strncpy((char*) &(ip[1]), value, 7);
	} else if (type == NODE_TYPE_LANG) {
		ip[1]	= (char) *((const int*) arg1);
		strncpy((char*) &(ip[2]), value, 6);
	} else if (type == NODE_TYPE_DATATYPE) {
		if (subtype == NODE_SUBTYPE_INTEGER) {
			const uint64_t* p	= (const uint64_t*) value;
			uint64_t v	= NSSwapHostLongLongToBig(*p);
			idvalue	|= v;
		} else if (subtype == NODE_SUBTYPE_FLOAT) {
            strncpy((char*) &(ip[1]), value, 7);
		} else if (subtype == NODE_SUBTYPE_DECIMAL) {
			int64_t v	= *((const int64_t*) value);
			char scale	= *((const char*) arg1);
			int64_t nv	= NSSwapHostLongLongToBig(v);
			uint64_t tmp    = 0;
            char* tmpp      = (char*)&tmp;
			tmp         = 0x0 | nv;
			tmpp[0]     = 0x0;
			tmpp[1]     = 0x0;
			ip[1]		= scale;
			idvalue	|= tmp;
		} else if (subtype == NODE_SUBTYPE_FIXED) {
			// booleans
			int v	= *((const int*) value);
			unsigned char b	= (v == 0) ? '\0' : '\1';
			ip[7]	= (char) b;
		} else if (subtype == NODE_SUBTYPE_LITERAL) {
			// xsd:string
			strncpy((char*) &(ip[1]), value, 7);
		} else {
			fprintf( stderr, "unknown datatype subtype %d\n", subtype );
			return nil;
		}
	} else if (type == NODE_TYPE_LANG) {
		
	}
	return [NSData dataWithBytes:&idvalue length:8];
}



@end
