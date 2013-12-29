//
//  main.c
//  gtwaof
//
//  Created by Gregory Williams on 12/8/13.
//  Copyright (c) 2013 Gregory Todd Williams. All rights reserved.
//

#include <sys/time.h>
#include <string.h>
#import <Foundation/Foundation.h>
#import "GTWAOF.h"
#import "GTWAOFDirectFile.h"
#import "GTWAOFMemory.h"
#import "GTWAOFUpdateContext.h"
#import "GTWAOFRawDictionary.h"
#import "GTWAOFRawQuads.h"
#import <SPARQLKit/SPARQLKit.h>
#import <SPARQLKit/SPKSPARQLLexer.h>
#import <SPARQLKit/SPKTurtleParser.h>
#import <GTWSWBase/GTWSWBase.h>
#import <GTWSWBase/GTWQuad.h>
#import <SPARQLKit/SPKNTriplesSerializer.h>
#import "GTWAOFQuadStore.h"
#import "GTWAOFPage+GTWAOFLinkedPage.h"
#import "GTWAOFRawValue.h"
#import "GTWAOFBTreeNode.h"
#import "GTWAOFBTree.h"
#import "NSIndexSet+GTWIndexRange.h"

#define BTREE_INTERNAL_NODE_COOKIE "BPTI"
#define BTREE_LEAF_NODE_COOKIE "BPTL"
#define QUAD_STORE_COOKIE "QDST"

static const NSInteger keySize  = 32;
static const NSInteger valSize  = 8;

double current_time ( void ) {
	struct timeval t;
	gettimeofday (&t, NULL);
	double start	= t.tv_sec + (t.tv_usec / 1000000.0);
	return start;
}

double elapsed_time ( double start ) {
	struct timeval t;
	gettimeofday (&t, NULL);
	double time	= t.tv_sec + (t.tv_usec / 1000000.0);
	double elapsed	= time - start;
	return elapsed;
}

GTWAOFPage* newPageWithChar( GTWAOFUpdateContext *ctx, char c ) {
    NSUInteger pageSize = [ctx pageSize];
    char* buf  = malloc(pageSize);
    memset(buf, c, pageSize);
    NSData* data   = [NSData dataWithBytesNoCopy:buf length:pageSize];
    return [ctx createPageWithData:data];
}

void stress (id<GTWAOF> aof) {
    NSUInteger count    = 100000;
    dispatch_queue_t queue     = dispatch_queue_create("us.kasei.sparql.aof.stress", DISPATCH_QUEUE_CONCURRENT);
    for (NSInteger i = 0; i < count; i++) {
        int r  = rand();
        int count  = 1 + (r % 9);
        char c = '0' + count;
//        NSLog(@"creating %d page(s) with data '%c'", count, c);
        dispatch_async(queue, ^{
            [aof updateWithBlock:^BOOL(GTWAOFUpdateContext *ctx) {
                for (int i = 0; i < count; i++) {
                    newPageWithChar(ctx, c);
                }
                return YES;
            }];
        });
    }
    dispatch_barrier_sync(queue, ^{});
}

id<GTWTerm> termFromData(SPKTurtleParser* p, NSData* data) {
    NSString* string        = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    SPKSPARQLLexer* lexer   = [[SPKSPARQLLexer alloc] initWithString:string];
    p.lexer                 = lexer;
    NSError* error;
    SPKSPARQLToken* t       = [lexer getTokenWithError:&error];
    if (error) {
        NSLog(@"Failed to get token: %@", error);
        return nil;
    }
    NSMutableArray* errors  = [NSMutableArray array];
    if (!t) {
        NSLog(@"No token found");
        return nil;
    }
    id<GTWTerm> term        = [p tokenAsTerm:t withErrors:errors];
    if ([errors count]) {
        error  = errors[0];
        NSLog(@"Cannot create term from token %@: %@", t, error);
        return nil;
    }
    if (!term) {
        NSLog(@"Cannot create term from token %@", t);
        return nil;
    }
    return term;
}

NSData* dataFromTerm(id<GTWTerm> t) {
    NSString* str               = [SPKNTriplesSerializer nTriplesEncodingOfTerm:t];
    NSData* data                = [str dataUsingEncoding:NSUTF8StringEncoding];
    return data;
}

NSData* dataFromInteger(NSUInteger value) {
    long long n = (long long) value;
    long long bign  = NSSwapHostLongLongToBig(n);
    return [NSData dataWithBytes:&bign length:8];
}

NSData* dataFromIntegers(NSUInteger a, NSUInteger b, NSUInteger c, NSUInteger d) {
    NSMutableData* data = [NSMutableData dataWithLength:32];
    int64_t biga  = NSSwapHostLongLongToBig((unsigned long long) a);
    int64_t bigb  = NSSwapHostLongLongToBig((unsigned long long) b);
    int64_t bigc  = NSSwapHostLongLongToBig((unsigned long long) c);
    int64_t bigd  = NSSwapHostLongLongToBig((unsigned long long) d);
    [data replaceBytesInRange:NSMakeRange(0, 8) withBytes:&biga];
    [data replaceBytesInRange:NSMakeRange(8, 8) withBytes:&bigb];
    [data replaceBytesInRange:NSMakeRange(16, 8) withBytes:&bigc];
    [data replaceBytesInRange:NSMakeRange(24, 8) withBytes:&bigd];
    return data;
}

NSUInteger integerFromData(NSData* data) {
    long long bign;
    [data getBytes:&bign range:NSMakeRange(0, 8)];
    long long n = NSSwapBigLongLongToHost(bign);
    return (NSUInteger) n;
}

static NSData* hexToBytes (NSString* string) {
    NSMutableData* data = [NSMutableData data];
    int idx;
    for (idx = 0; idx+2 <= string.length; idx+=2) {
        NSString* hexStr = [string substringWithRange:NSMakeRange(idx, 2)];
        NSScanner* scanner = [NSScanner scannerWithString:hexStr];
        unsigned int intValue;
        [scanner scanHexInt:&intValue];
        [data appendBytes:&intValue length:1];
    }
    return data;
}

void print_digraph_for_btree_node ( id<GTWAOF> aof, FILE* f, GTWAOFBTreeNode* n ) {
    NSString* nodeName  = [NSString stringWithFormat:@"n%llu", (unsigned long long)n.pageID];
    const char* name    = [nodeName UTF8String];
    if ([n isRoot]) {
        fprintf(f, "\t%s [label=\"%s\"; style=\"bold\"; color=\"red\"; shape=\"square\"]\n", name, name);
    } else {
        fprintf(f, "\t%s [label=\"%s\"; color=\"blue\"]\n", name, name);
    }
    if (n.type == GTWAOFBTreeInternalNodeType) {
        NSArray* pageIDs    = [n childrenPageIDs];
        for (NSNumber* number in pageIDs) {
            GTWAOFBTreeNode* child  = [GTWAOFBTreeNode nodeWithPageID:[number integerValue] parent:n fromAOF:aof];
            NSString* childNodeName  = [NSString stringWithFormat:@"n%llu", (unsigned long long)child.pageID];
            fprintf(f, "\t%s -> %s ;\n", [nodeName UTF8String], [childNodeName UTF8String]);
        }
    }
}

void printPageSummary ( id<GTWAOF> aof, GTWAOFPage* p ) {
    NSData* data    = p.data;
    char cookie[5] = { 0,0,0,0,0 };
    [data getBytes:cookie length:4];
    NSDictionary* names = @{
                            @"RDCT": @"Raw Dictionary",
                            @"RQDS": @"Raw Quads",
                            @"RVAL": @"Raw Value",
                            @"BPTI": @"B+ Tree Internal Node",
                            @"BPTL": @"B+ Tree Leaf Node",
                            @"QDST": @"Quad Store"
                            };
    NSString* c = [NSString stringWithFormat:@"%s", cookie];
    fprintf(stdout, "Page %-6lu\n", p.pageID);
    NSDate* modified    = [p lastModified];
    NSInteger prev      = [p previousPageID];
    fprintf(stdout, "    Type          : %s (%s)\n", [[names[c] description] UTF8String], cookie);
    fprintf(stdout, "    Time-Stamp    : %s\n", [[modified description] UTF8String]);
    if (prev < 0) {
        fprintf(stdout, "    Previous-Page : None\n");
    } else {
        fprintf(stdout, "    Previous-Page : %lld\n", (long long)prev);
    }
    
    if ([c isEqualToString:@"QDST"]) {
        GTWAOFQuadStore* obj    = [[GTWAOFQuadStore alloc] initWithPage:p fromAOF:aof];
        fprintf(stdout, "    Term -> ID    : %lld\n", (long long)obj.btreeTerm2ID.pageID);
        fprintf(stdout, "    ID -> Term    : %lld\n", (long long)obj.btreeID2Term.pageID);
        NSDictionary* indexes   = [obj indexes];
        for (NSString* order in indexes) {
            GTWAOFBTree* index    = indexes[order];
            fprintf(stdout, "    %s Index    : %lld\n", [order UTF8String], (long long)index.pageID);
        }
    } else if ([c isEqualToString:@"RDCT"]) {
        GTWAOFRawDictionary* obj    = [[GTWAOFRawDictionary alloc] initWithPage:p fromAOF:aof];
        NSUInteger count            = [obj count];
        fprintf(stdout, "    Entries       : %lld\n", (long long)count);
    } else if ([c isEqualToString:@"RVAL"]) {
        GTWAOFRawValue* obj         = [[GTWAOFRawValue alloc] initWithPage:p fromAOF:aof];
        fprintf(stdout, "    Length        : %lld (%lld in page)\n", (long long)[obj length], (long long)[obj pageLength]);
    } else if ([c isEqualToString:@"RQDS"]) {
        GTWAOFRawQuads* obj         = [[GTWAOFRawQuads alloc] initWithPage:p fromAOF:aof];
        NSUInteger count            = [obj count];
        fprintf(stdout, "    Quads         : %lld\n", (long long)count);
    } else if ([c rangeOfString:@"BPT[IL]" options:NSRegularExpressionSearch].location == 0) {
        GTWAOFBTreeNode* obj        = [[GTWAOFBTreeNode alloc] initWithPage:p parent:nil fromAOF:aof];
        NSUInteger count            = [obj count];
        fprintf(stdout, "    Flags         : %s\n", (obj.isRoot) ? "None" : "Root");
        fprintf(stdout, "    Keys          : %lld\n", (long long)count);
        fprintf(stdout, "    Pair sizes    : { %lld, %lld }\n", (long long)obj.keySize, (long long)obj.valSize);
        if (obj.isRoot) {
            NSInteger maxInternal   = obj.maxInternalPageKeys;
            NSInteger maxLeaf       = obj.maxLeafPageKeys;
            fprintf(stdout, "    Int. Capacity : %lld\n", (long long)maxInternal);
            fprintf(stdout, "    Leaf Capacity : %lld\n", (long long)maxLeaf);
        }
        if ([c isEqualToString:@"BPTI"]) {
            NSArray* children   = [obj childrenPageIDs];
            NSMutableIndexSet* set  = [NSMutableIndexSet indexSet];
            for (NSNumber* n in children) {
                [set addIndex:[n integerValue]];
            }
            fprintf(stdout, "    Children      : %s\n", [[set gtw_indexRanges] UTF8String]);
        }
    }
}

int main(int argc, const char * argv[]) {
    if (argc < 2) {
        const char* cmd = argv[0];
        fprintf(stdout, "Usage:\n");
        fprintf(stdout, "    %s add\n", cmd);
        fprintf(stdout, "    %s list\n", cmd);
        fprintf(stdout, "    %s dict\n", cmd);
        fprintf(stdout, "    %s adddict key=val ...\n", cmd);
        fprintf(stdout, "    %s mkdict key=val ...\n", cmd);
        fprintf(stdout, "    %s mkvalue val\n", cmd);
        fprintf(stdout, "    %s value pageID\n", cmd);
        fprintf(stdout, "    %s term ID ...\n", cmd);
        fprintf(stdout, "    %s quads\n", cmd);
        fprintf(stdout, "    %s addquads s:p:o:g ...\n", cmd);
        fprintf(stdout, "    %s mkquads s:p:o:g ...\n", cmd);
        fprintf(stdout, "    %s import FILE.ttl\n", cmd);
        fprintf(stdout, "    %s delete FILE.ttl\n", cmd);
        fprintf(stdout, "    %s bulkimport FILE.ttl\n", cmd);
        fprintf(stdout, "    %s export\n", cmd);
        fprintf(stdout, "    %s pages\n", cmd);
        return 0;
    }

    int argi            = 1;
    
    BOOL verbose        = NO;
    NSInteger pageID    = -1;
    const char* filename    = "db/test.db";
    while (argc > argi && argv[argi][0] == '-') {
        if (!strcmp(argv[argi], "-s")) {
            argi++;
            filename    = argv[argi++];
        } else if (!strcmp(argv[argi], "-p")) {
            argi++;
            pageID    = atoll(argv[argi++]);
        } else if (!strcmp(argv[argi], "-v")) {
            argi++;
            verbose = YES;
        }
    }

    double start    = current_time();
    srand([[NSDate date] timeIntervalSince1970]);
    GTWAOFDirectFile* aof   = [[GTWAOFDirectFile alloc] initWithFilename:@(filename)];
    NSLog(@"aof file: %@", aof);
    
    const char* op  = argv[argi++];
    if (!strcmp(op, "add")) {
        [aof updateWithBlock:^BOOL(GTWAOFUpdateContext *ctx) {
//            int count  = 1 + (rand() % 4);
            int count  = 1;
            int r  = rand();
            char c = 'A' + (r % 26);

            NSLog(@"creating %d page(s) with data '%c'", count, c);
            for (int i = 0; i < count; i++) {
            newPageWithChar(ctx, c);
            }
            return YES;
        }];
    } else if (!strcmp(op, "list")) {
        NSInteger pid   = 0;
        NSInteger count = aof.pageCount;
        for (pid = 0; pid < count; pid++) {
            GTWAOFPage* p   = [aof readPage:pid];
            NSLog(@"page -> %@", p);
        }
    } else if (!strcmp(op, "dict")) {
        GTWAOFRawDictionary* d  = [[GTWAOFRawDictionary alloc] initFindingDictionaryInAOF:aof];
        [d enumerateKeysAndObjectsUsingBlock:^(NSData* key, NSData* obj, BOOL *stop) {
            NSString* k = [[NSString alloc] initWithData:key encoding:NSUTF8StringEncoding];
            NSString* value;
            if ([key length] == 8) {
                long long bign;
                [obj getBytes:&bign range:NSMakeRange(0, 8)];
                long long v = NSSwapBigLongLongToHost(bign);
                value       = [NSString stringWithFormat:@"%6lld", v];
            } else {
                value       = [obj description];
            }
            NSString* d = [NSString stringWithFormat:@"%@ -> %@", value, k];
            fprintf(stdout, "%s\n", [d UTF8String]);
        }];
    } else if (!strcmp(op, "adddict")) {
        GTWMutableAOFRawDictionary* d  = [[GTWMutableAOFRawDictionary alloc] initFindingDictionaryInAOF:aof];
        NSMutableDictionary* dict   = [NSMutableDictionary dictionary];
        for (; argi < argc; argi++) {
            NSString* s     = [NSString stringWithFormat:@"%s", argv[argi]];
            NSArray* pair   = [s componentsSeparatedByString:@"="];
            NSString* k     = pair[0];
            NSString* v     = pair[1];
            NSData* key     = [k dataUsingEncoding:NSUTF8StringEncoding];
            NSData* val     = [v dataUsingEncoding:NSUTF8StringEncoding];
            dict[key]       = val;
        }
        
        NSLog(@"appending dictionary: %@", dict);
        [d dictionaryByAddingDictionary:dict];
    } else if (!strcmp(op, "value")) {
        long long pageID    = atoll(argv[argi++]);
        GTWAOFRawValue* v   = [GTWAOFRawValue rawValueWithPageID:pageID fromAOF:aof];
        NSData* data        = [v data];
        NSString* s         = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        fprintf(stdout, "%s\n", [s UTF8String]);
    } else if (!strcmp(op, "mkvalue")) {
        NSString* s     = [NSString stringWithFormat:@"%s", argv[argi++]];
        NSData* data    = [s dataUsingEncoding:NSUTF8StringEncoding];
        [aof updateWithBlock:^BOOL(GTWAOFUpdateContext *ctx) {
            [GTWMutableAOFRawValue valueWithData:data updateContext:ctx];
            return YES;
        }];
    } else if (!strcmp(op, "mkdict")) {
        NSMutableDictionary* dict   = [NSMutableDictionary dictionary];
        for (; argi < argc; argi++) {
            NSString* s     = [NSString stringWithFormat:@"%s", argv[argi]];
            NSArray* pair   = [s componentsSeparatedByString:@"="];
            NSString* key   = pair[0];
            NSString* val   = pair[1];
            dict[key]       = val;
        }
        
        NSLog(@"creating dictionary: %@", dict);
        [aof updateWithBlock:^BOOL(GTWAOFUpdateContext *ctx) {
            [GTWMutableAOFRawDictionary mutableDictionaryWithDictionary:dict updateContext:ctx];
            return YES;
        }];
    } else if (!strcmp(op, "term")) {
        long long n     = atoll(argv[argi++]);
        long long bign  = NSSwapHostLongLongToBig(n);
        NSData* nodeID  = [NSData dataWithBytes:&bign length:8];
        SPKTurtleParser* parser  = [[SPKTurtleParser alloc] init];
        GTWAOFRawDictionary* d  = [[GTWAOFRawDictionary alloc] initFindingDictionaryInAOF:aof];
        NSLog(@"%@", d);
        NSData* value   = [d keyForObject:nodeID];
        if (value) {
            id<GTWTerm> t   = termFromData(parser, value);
            fprintf(stdout, "%s\n", [[t description] UTF8String]);
        }
    } else if (!strcmp(op, "quads")) {
        GTWAOFRawQuads* q  = [[GTWAOFRawQuads alloc] initFindingQuadsInAOF:aof];
        [q enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            NSData* data = obj;
            NSMutableArray* tuple   = [NSMutableArray array];
            int j;
            for (j = 0; j < 4; j++) {
                long long bign;
                [data getBytes:&bign range:NSMakeRange((8*j), 8)];
                long long n = NSSwapBigLongLongToHost(bign);
                NSString* s = [NSString stringWithFormat:@"%lld", n];
                [tuple addObject:s];
            }
            fprintf(stdout, "%s\n", [[tuple componentsJoinedByString:@":"] UTF8String]);
        }];
    } else if (!strcmp(op, "addquads")) {
        GTWMutableAOFRawQuads* q  = [[GTWMutableAOFRawQuads alloc] initFindingQuadsInAOF:aof];
        NSMutableArray* quads   = [NSMutableArray array];
        for (; argi < argc; argi++) {
            NSString* s     = [NSString stringWithFormat:@"%s", argv[argi]];
            NSArray* tuple  = [s componentsSeparatedByString:@":"];
            NSMutableData* data = [NSMutableData dataWithLength:32];
            for (int j = 0; j < 4; j++) {
                NSString* t = tuple[j];
                long long n = atoll([t UTF8String]);
                long long bign  = NSSwapHostLongLongToBig(n);
                [data replaceBytesInRange:NSMakeRange((8*j), 8) withBytes:&bign];
            }
            NSLog(@"quad data: %@", data);
            [quads addObject:data];
        }
        
        NSLog(@"appending quads: %@", quads);
        [aof updateWithBlock:^BOOL(GTWAOFUpdateContext *ctx) {
            [q mutableQuadsByAddingQuads:quads updateContext:ctx];
            return YES;
        }];
    } else if (!strcmp(op, "mkquads")) {
        NSMutableArray* quads   = [NSMutableArray array];
        for (; argi < argc; argi++) {
            NSString* s     = [NSString stringWithFormat:@"%s", argv[argi]];
            NSArray* tuple  = [s componentsSeparatedByString:@":"];
            NSMutableData* data = [NSMutableData dataWithLength:32];
            for (int j = 0; j < 4; j++) {
                NSString* t = tuple[j];
                long long n = atoll([t UTF8String]);
                NSLog(@"quad pos %d: %lld", j, n);
                long long bign  = NSSwapHostLongLongToBig(n);
                [data replaceBytesInRange:NSMakeRange((8*j), 8) withBytes:&bign];
                NSLog(@"-> data: %@", data);
            }
            NSLog(@"quad data: %@", data);
            [quads addObject:data];
        }
        
        NSLog(@"creating quads: %@", quads);
        [aof updateWithBlock:^BOOL(GTWAOFUpdateContext *ctx) {
            [GTWMutableAOFRawQuads mutableQuadsWithQuads:quads updateContext:ctx];
            return YES;
        }];
    } else if (!strcmp(op, "export")) {
//        NSLog(@"Exporting from QuadStore #%lld", (long long)pageID);
        GTWAOFQuadStore* store  = (pageID < 0) ? [[GTWAOFQuadStore alloc] initWithAOF:aof] : [[GTWAOFQuadStore alloc] initWithPageID:pageID fromAOF:aof];
        if (!store) {
            NSLog(@"Failed to create quad store object");
            return 1;
        }
        SPKTurtleParser* parser  = [[SPKTurtleParser alloc] init];
        id<GTWTerm> s, p, o, g;
        if (argc > argi) {
            const char* ss  = argv[argi++];
            s   = termFromData(parser, [NSData dataWithBytes:ss length:strlen(ss)]);
        }
        NSError* error;
        double start_export = current_time();
        NSDate* date    = [store lastModifiedDateForQuadsMatchingSubject:s predicate:p object:o graph:g error:&error];
        NSLog(@"Last-Modified: %@", [date descriptionWithCalendarFormat:@"%Y-%m-%dT%H:%M:%S%z" timeZone:[NSTimeZone localTimeZone] locale:[NSLocale currentLocale]]);
        [store enumerateQuadsMatchingSubject:s predicate:p object:o graph:g usingBlock:^(id<GTWQuad> q) {
            fprintf(stdout, "%s\n", [[q description] UTF8String]);
        } error:&error];
        fprintf(stderr, "export time: %lf\n", elapsed_time(start_export));
    } else if (!strcmp(op, "compact")) {
        NSString* newfilename   = @(argv[argi++]);
        GTWAOFDirectFile* newaof   = [[GTWAOFDirectFile alloc] initWithFilename:newfilename];
        GTWMutableAOFQuadStore* store  = [[GTWMutableAOFQuadStore alloc] initWithAOF:aof];
        [newaof updateWithBlock:^BOOL(GTWAOFUpdateContext *ctx) {
            [store rewriteWithUpdateContext:ctx];
            return YES;
        }];
    } else if (!strcmp(op, "test")) {
        id<GTWAOF> mem  = [[GTWAOFMemory alloc] init];
        GTWMutableAOFQuadStore* store  = [[GTWMutableAOFQuadStore alloc] initWithAOF:mem];
        
        // Import
        {
            store.verbose       = verbose;
            __block NSError* error;
            NSString* filename  = [NSString stringWithFormat:@"%s", argv[argi++]];
            const char* basestr = (argc > argi) ? argv[argi++] : "http://base.example.org/";
            NSString* base      = [NSString stringWithFormat:@"%s", basestr];
            NSFileHandle* fh    = [NSFileHandle fileHandleForReadingAtPath:filename];
            SPKSPARQLLexer* l   = [[SPKSPARQLLexer alloc] initWithFileHandle:fh];
            GTWIRI* baseuri     = [[GTWIRI alloc] initWithValue:base];
            GTWIRI* graph       = [[GTWIRI alloc] initWithValue:base];
            SPKTurtleParser* p  = [[SPKTurtleParser alloc] initWithLexer:l base: baseuri];
            if (p) {
                double start_import = current_time();
                [store beginBulkLoad];
                __block NSUInteger count    = 0;
                [p enumerateTriplesWithBlock:^(id<GTWTriple> t) {
                    count++;
                    if (count % 100 == 0) {
                        fprintf(stderr, "\r%llu quads", (unsigned long long) count);
                    }
                    GTWQuad* q  = [GTWQuad quadFromTriple:t withGraph:graph];
                    [store addQuad:q error:&error];
                    if (error) {
                        NSLog(@"%@", error);
                    }
                } error:&error];
                if (error) {
                    NSLog(@"%@", error);
                }
                [store endBulkLoad];
                fprintf(stderr, "import time: %lf\n", elapsed_time(start_import));
                fprintf(stderr, "\r%llu quads imported\n", (unsigned long long) count);
            } else {
                NSLog(@"Could not construct parser");
            }
        }
        
        // Export
        {
            SPKTurtleParser* parser  = [[SPKTurtleParser alloc] init];
            id<GTWTerm> s, p, o, g;
            if (argc > argi) {
                const char* ss  = argv[argi++];
                s   = termFromData(parser, [NSData dataWithBytes:ss length:strlen(ss)]);
            }
            NSError* error;
            double start_export = current_time();
            NSDate* date    = [store lastModifiedDateForQuadsMatchingSubject:s predicate:p object:o graph:g error:&error];
            NSLog(@"Last-Modified: %@", [date descriptionWithCalendarFormat:@"%Y-%m-%dT%H:%M:%S%z" timeZone:[NSTimeZone localTimeZone] locale:[NSLocale currentLocale]]);
            [store enumerateQuadsMatchingSubject:s predicate:p object:o graph:g usingBlock:^(id<GTWQuad> q) {
                fprintf(stdout, "%s\n", [[q description] UTF8String]);
            } error:&error];
            fprintf(stderr, "export time: %lf\n", elapsed_time(start_export));
        }
    } else if (!strcmp(op, "import")) {
        GTWMutableAOFQuadStore* store  = [[GTWMutableAOFQuadStore alloc] initWithAOF:aof];
        store.verbose       = verbose;
        __block NSError* error;
        NSString* filename  = [NSString stringWithFormat:@"%s", argv[argi++]];
        const char* basestr = (argc > argi) ? argv[argi++] : "http://base.example.org/";
        NSString* base      = [NSString stringWithFormat:@"%s", basestr];
        NSFileHandle* fh    = [NSFileHandle fileHandleForReadingAtPath:filename];
        SPKSPARQLLexer* l   = [[SPKSPARQLLexer alloc] initWithFileHandle:fh];
        GTWIRI* baseuri     = [[GTWIRI alloc] initWithValue:base];
        GTWIRI* graph       = [[GTWIRI alloc] initWithValue:base];
        SPKTurtleParser* p  = [[SPKTurtleParser alloc] initWithLexer:l base: baseuri];
        if (p) {
            double start_import = current_time();
            [store beginBulkLoad];
            __block NSUInteger count    = 0;
            [p enumerateTriplesWithBlock:^(id<GTWTriple> t) {
                count++;
                if (count % 100 == 0) {
                    fprintf(stderr, "\r%llu quads", (unsigned long long) count);
                }
                GTWQuad* q  = [GTWQuad quadFromTriple:t withGraph:graph];
                [store addQuad:q error:&error];
                if (error) {
                    NSLog(@"%@", error);
                }
            } error:&error];
            if (error) {
                NSLog(@"%@", error);
            }
            [store endBulkLoad];
            fprintf(stderr, "import time: %lf\n", elapsed_time(start_import));
            fprintf(stderr, "\r%llu quads imported\n", (unsigned long long) count);
        } else {
            NSLog(@"Could not construct parser");
        }
    } else if (!strcmp(op, "delete")) {
        GTWMutableAOFQuadStore* store  = [[GTWMutableAOFQuadStore alloc] initWithAOF:aof];
        __block NSError* error;
        NSString* filename  = [NSString stringWithFormat:@"%s", argv[argi++]];
        const char* basestr = (argc > argi) ? argv[argi++] : "http://base.example.org/";
        NSString* base      = [NSString stringWithFormat:@"%s", basestr];
        NSFileHandle* fh    = [NSFileHandle fileHandleForReadingAtPath:filename];
        SPKSPARQLLexer* l   = [[SPKSPARQLLexer alloc] initWithFileHandle:fh];
        GTWIRI* baseuri     = [[GTWIRI alloc] initWithValue:base];
        GTWIRI* graph       = [[GTWIRI alloc] initWithValue:base];
        SPKTurtleParser* p  = [[SPKTurtleParser alloc] initWithLexer:l base: baseuri];
        if (p) {
//            [store beginBulkLoad];
            __block NSUInteger count    = 0;
            [p enumerateTriplesWithBlock:^(id<GTWTriple> t) {
                GTWQuad* q  = [GTWQuad quadFromTriple:t withGraph:graph];
                [store removeQuad:q error:&error];
                count++;
                if (count % 25 == 0) {
                    fprintf(stderr, "\r%llu quads", (unsigned long long) count);
                }
            } error:nil];
            fprintf(stderr, "\n");
//            [store endBulkLoad];
        } else {
            NSLog(@"Could not construct parser");
        }
    } else if (!strcmp(op, "bulkimport")) {
        NSString* filename  = [NSString stringWithFormat:@"%s", argv[argi++]];
        const char* basestr = (argc > argi) ? argv[argi++] : "http://base.example.org/";
        NSString* base      = [NSString stringWithFormat:@"%s", basestr];
        NSFileHandle* fh    = [NSFileHandle fileHandleForReadingAtPath:filename];
        SPKSPARQLLexer* l   = [[SPKSPARQLLexer alloc] initWithFileHandle:fh];
        GTWIRI* baseuri     = [[GTWIRI alloc] initWithValue:base];
        GTWIRI* graph       = [[GTWIRI alloc] initWithValue:base];
        SPKTurtleParser* p  = [[SPKTurtleParser alloc] initWithLexer:l base: baseuri];
        if (p) {
            __block NSUInteger nextID           = 1;
            NSMutableDictionary* map    = [NSMutableDictionary dictionary];
            NSMutableArray* quads       = [NSMutableArray array];
            [p enumerateTriplesWithBlock:^(id<GTWTriple> t) {
                GTWQuad* q  = [GTWQuad quadFromTriple:t withGraph:graph];
                NSMutableData* quadData = [NSMutableData data];
                for (id<GTWTerm> t in [q allValues]) {
                    NSData* termData    = dataFromTerm(t);
                    NSData* ident   = map[termData];
                    if (!ident) {
                        ident           = dataFromInteger(nextID++);
                        map[termData]   = ident;
                    }
                    [quadData appendData:ident];
                }
                [quads addObject:quadData];
            } error:nil];
            [aof updateWithBlock:^BOOL(GTWAOFUpdateContext *ctx) {
                [GTWMutableAOFRawQuads mutableQuadsWithQuads:quads updateContext:ctx];
                [GTWMutableAOFRawDictionary mutableDictionaryWithDictionary:map updateContext:ctx];
                return YES;
            }];
        } else {
            NSLog(@"Could not construct parser");
        }
    } else if (!strcmp(op, "pages")) {
        NSInteger pageID;
        NSInteger pageCount = [aof pageCount];
        for (pageID = 0; pageID < pageCount; pageID++) {
            GTWAOFPage* p   = [aof readPage:pageID];
            printPageSummary(aof, p);
        }
    } else if (!strcmp(op, "btreecreate")) {
        NSInteger ksize = 1;
        NSInteger vsize = 1;
        if (argc > argi) {
            ksize   = (NSInteger)atoll(argv[argi++]);
        }
        if (argc > argi) {
            vsize   = (NSInteger)atoll(argv[argi++]);
        }
        [aof updateWithBlock:^BOOL(GTWAOFUpdateContext *ctx) {
            GTWAOFBTreeNode* root   = [[GTWMutableAOFBTreeNode alloc] initLeafWithParent:nil isRoot:YES keySize:ksize valueSize:vsize keys:@[] objects:@[] updateContext:ctx];
            NSLog(@"root node: %@", root);
            return YES;
        }];
    } else if (!strcmp(op, "btreeadd")) {
        NSInteger pageCount = [aof pageCount];
        NSInteger pageID    = pageCount-1;
        GTWMutableAOFBTree* t      = [[GTWMutableAOFBTree alloc] initWithRootPageID:pageID fromAOF:aof];
        NSData* key         = hexToBytes(@(argv[argi++]));
        NSData* val         = hexToBytes(@(argv[argi++]));
        NSLog(@"tree: %@", t);
        [aof updateWithBlock:^BOOL(GTWAOFUpdateContext *ctx) {
            [t insertValue:val forKey:key updateContext:ctx];
            NSLog(@"root node: %@", [t root]);
            return YES;
        }];
    } else if (!strcmp(op, "mkbtree")) {
        NSMutableArray* numbers = [NSMutableArray array];
        const int total_keys    = 500;
        const int page_size     = 100;
        for (int j = 0; j < total_keys; j++) {
            uint64_t value;
            uint32_t* pair  = (uint32_t*) &value;
            pair[0]     = rand();
            pair[1]     = rand();
            [numbers addObject:@(value)];
        }
        [numbers sortUsingSelector:@selector(compare:)];

        [aof updateWithBlock:^BOOL(GTWAOFUpdateContext *ctx) {
            NSMutableArray* pages   = [NSMutableArray array];
            NSUInteger leaf_page    = 0;
            while ([numbers count]) {
                NSRange range           = NSMakeRange(0, page_size);
                NSArray* pageNumbers    = [numbers subarrayWithRange:range];
                [numbers removeObjectsInRange:range];
                NSMutableArray* keys    = [NSMutableArray array];
                NSMutableArray* vals    = [NSMutableArray array];
                for (NSNumber* number in pageNumbers) {
                    NSUInteger value    = [number unsignedIntegerValue];
                    NSLog(@"adding value -> %lld", (long long)value);
                    NSData* keyData     = dataFromIntegers(1, 2, 3, value);
                    [keys addObject:keyData];
                    NSData* object   = [NSData dataWithBytes:"\x00\x00\x00\x00\x00\x00\x00\xFF" length:8];
                    [vals addObject:object];
                }
                GTWAOFBTreeNode* leaf  = [[GTWMutableAOFBTreeNode alloc] initLeafWithParent:nil isRoot:YES keySize:keySize valueSize:valSize keys:keys objects:vals updateContext:ctx];
                [pages addObject:leaf];
                NSLog(@"Created b-tree leaf: %@", leaf);
                leaf_page++;
            }
            
            NSMutableArray* rootKeys    = [NSMutableArray array];
            NSMutableArray* rootValues  = [NSMutableArray array];
            for (NSInteger i = 0; i < [pages count]; i++) {
                GTWAOFBTreeNode* child  = pages[i];
                NSInteger pageID    = child.pageID;
                NSData* key         = [child maxKey];
                if (i < ([pages count]-1)) {
                    [rootKeys addObject:key];
                }
                [rootValues addObject:@(pageID)];
            }
            
            GTWAOFBTreeNode* root   = [[GTWMutableAOFBTreeNode alloc] initInternalWithParent:nil isRoot:YES keySize:keySize valueSize:valSize keys:rootKeys pageIDs:rootValues updateContext:ctx];
            NSLog(@"root node: %@", root);
            return YES;
        }];
    } else if (!strcmp(op, "btreelca")) {
        NSInteger pageID    = (NSInteger)atoll(argv[argi++]);
        const char* prefixHex   = argv[argi++];
        NSData* prefix          = hexToBytes(@(prefixHex));
        GTWAOFBTree* t          = [[GTWAOFBTree alloc] initWithRootPageID:pageID fromAOF:aof];
        GTWAOFBTreeNode* lca    = [t lcaNodeForKeysWithPrefix:prefix];
        NSLog(@"LCA: %@", lca);
    } else if (!strcmp(op, "btreematch")) {
        NSInteger pageID        = (NSInteger)atoll(argv[argi++]);
        const char* prefixHex   = argv[argi++];
        NSData* prefix          = hexToBytes(@(prefixHex));
        GTWAOFBTree* t          = [[GTWAOFBTree alloc] initWithRootPageID:pageID fromAOF:aof];
        __block NSUInteger count    = 0;
        [t enumerateKeysAndObjectsMatchingPrefix:prefix usingBlock:^(NSData *key, NSData *obj, BOOL *stop) {
            NSLog(@"[%3lu]\t%@ -> %@", ++count, key, obj);
        }];
    } else if (!strcmp(op, "dictcompact")) {
        NSString* newfilename   = @(argv[argi++]);
        GTWAOFDirectFile* newaof   = [[GTWAOFDirectFile alloc] initWithFilename:newfilename];
        NSInteger pageCount = [aof pageCount];
        NSInteger pageID    = pageCount-1;
        if (argc > argi) {
            pageID    = (NSInteger)atoll(argv[argi++]);
        }
        GTWAOFRawDictionary* dict   = [GTWAOFRawDictionary rawDictionaryWithPageID:pageID fromAOF:aof];
        [newaof updateWithBlock:^BOOL(GTWAOFUpdateContext *ctx) {
            [dict rewriteWithUpdateContext:ctx];
            return YES;
        }];
    } else if (!strcmp(op, "btreecompact")) {
        NSString* newfilename   = @(argv[argi++]);
        GTWAOFDirectFile* newaof   = [[GTWAOFDirectFile alloc] initWithFilename:newfilename];
        NSInteger pageCount = [aof pageCount];
        NSInteger pageID    = pageCount-1;
        if (argc > argi) {
            pageID    = (NSInteger)atoll(argv[argi++]);
        }
        GTWAOFBTree* t  = [[GTWAOFBTree alloc] initWithRootPageID:pageID fromAOF:aof];
        [newaof updateWithBlock:^BOOL(GTWAOFUpdateContext *ctx) {
            [t rewriteWithUpdateContext:ctx];
            return YES;
        }];
    } else if (!strcmp(op, "btreedot")) {
        NSInteger pageID;
        NSInteger pageCount = [aof pageCount];
        fprintf(stdout, "digraph G {\n");
        for (pageID = pageCount-1; pageID >= 0; pageID--) {
            GTWAOFPage* p   = [aof readPage:pageID];
            NSData* data    = p.data;
            char cookie[5] = { 0,0,0,0,0 };
            [data getBytes:cookie length:4];
            NSData* typedata    = [NSData dataWithBytes:cookie length:4];
            NSString* type  = [[NSString alloc] initWithData:typedata encoding:4];
//            NSLog(@"-> %@", type);
            if ([type hasPrefix:@"BPT"]) {
                GTWAOFBTreeNode* n  = [GTWAOFBTreeNode nodeWithPageID:pageID parent:Nil fromAOF:aof];
                print_digraph_for_btree_node(aof, stdout, n);
            }
        }
        fprintf(stdout, "}\n");
    } else if (!strcmp(op, "btree")) {
        NSInteger pageCount = [aof pageCount];
        NSInteger pageID    = pageCount-1;
        if (argc > argi) {
            pageID    = (NSInteger)atoll(argv[argi++]);
        }
        GTWAOFBTree* t      = [[GTWAOFBTree alloc] initWithRootPageID:pageID fromAOF:aof];
        NSLog(@"btree: %@", t);
        __block NSUInteger count    = 0;
        [t enumerateKeysAndObjectsUsingBlock:^(NSData *key, NSData *obj, BOOL *stop) {
            printf("[%3lu]\t%s -> %s\n", ++count, [[key description] UTF8String], [[obj description] UTF8String]);
        }];
    } else if (!strcmp(op, "btverify")) {
        NSInteger pageID    = 0;
        if (argc > argi) {
            pageID    = (NSInteger)atoll(argv[argi++]);
        }
        GTWAOFBTreeNode* b  = [GTWAOFBTreeNode nodeWithPageID:pageID parent:nil fromAOF:aof];
        [b verify];
    } else if (!strcmp(op, "stress")) {
        stress(aof);
    }
    
    fprintf(stderr, "total time: %lf\n", elapsed_time(start));
    
    return 0;
}

