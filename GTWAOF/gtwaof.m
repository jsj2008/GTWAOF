//
//  main.c
//  gtwaof
//
//  Created by Gregory Williams on 12/8/13.
//  Copyright (c) 2013 Gregory Todd Williams. All rights reserved.
//

#include <string.h>
#import <Foundation/Foundation.h>
#import "GTWAOF.h"
#import "GTWAOFDirectFile.h"
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

GTWAOFPage* newPageWithChar( GTWAOFUpdateContext *ctx, char c ) {
    NSUInteger pageSize = [ctx.aof pageSize];
    char* buf  = malloc(pageSize);
    memset(buf, c, pageSize);
    NSData* data   = [NSData dataWithBytesNoCopy:buf length:pageSize];
    return [ctx createPageWithData:data];
}

void stress (id<GTWAOF> aof) {
    NSUInteger count    = 100000;
    dispatch_queue_t queue     = dispatch_queue_create("us.kasei.sparql.aof.stress", DISPATCH_QUEUE_CONCURRENT);
    for (NSUInteger i = 0; i < count; i++) {
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
    SPKSPARQLToken* t       = [lexer getTokenWithError:nil];
    if (!t)
        return nil;
    id<GTWTerm> term        = [p tokenAsTerm:t withErrors:nil];
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

NSUInteger integerFromData(NSData* data) {
    long long bign;
    [data getBytes:&bign range:NSMakeRange(0, 8)];
    long long n = NSSwapBigLongLongToHost(bign);
    return (NSUInteger) n;
}

void printPageSummary ( id<GTWAOF> aof, GTWAOFPage* p ) {
    NSData* data    = p.data;
    char cookie[5] = { 0,0,0,0,0 };
    [data getBytes:cookie length:4];
    NSDictionary* names = @{@"RDCT": @"Raw Dictionary", @"RQDS": @"Raw Quads"};
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
    
    if ([c isEqualToString:@"RDCT"]) {
//        GTWAOFRawDictionary* obj    = [[GTWAOFRawDictionary alloc] initWithPage:p fromAOF:aof];
        
    } else if ([c isEqualToString:@"RQDS"]) {
        GTWAOFRawQuads* obj         = [[GTWAOFRawQuads alloc] initWithPage:p fromAOF:aof];
        NSUInteger count            = [obj count];
        fprintf(stdout, "    Quads         : %lld\n", (long long)count);
    }
}

int main(int argc, const char * argv[]) {
    if (argc < 2) {
        fprintf(stdout, "Usage:\n");
        fprintf(stdout, "    %s add\n", argv[0]);
        fprintf(stdout, "    %s list\n", argv[0]);
        fprintf(stdout, "    %s dict\n", argv[0]);
        fprintf(stdout, "    %s adddict key=val ...\n", argv[0]);
        fprintf(stdout, "    %s mkdict key=val ...\n", argv[0]);
        fprintf(stdout, "    %s value key ...\n", argv[0]);
        fprintf(stdout, "    %s quads\n", argv[0]);
        fprintf(stdout, "    %s addquads s:p:o:g ...\n", argv[0]);
        fprintf(stdout, "    %s mkquads s:p:o:g ...\n", argv[0]);
        fprintf(stdout, "    %s import FILE.ttl\n", argv[0]);
        fprintf(stdout, "    %s delete FILE.ttl\n", argv[0]);
        fprintf(stdout, "    %s bulkimport FILE.ttl\n", argv[0]);
        fprintf(stdout, "    %s export\n", argv[0]);
        fprintf(stdout, "    %s pages\n", argv[0]);
        return 0;
    }
    
    srand([[NSDate date] timeIntervalSince1970]);
    GTWAOFDirectFile* aof   = [[GTWAOFDirectFile alloc] initWithFilename:@"test.db"];
    NSLog(@"aof file: %@", aof);
    
    const char* op  = argv[1];
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
            NSLog(@"-> %@", p);
        }
    } else if (!strcmp(op, "dict")) {
        GTWAOFRawDictionary* d  = [[GTWAOFRawDictionary alloc] initFindingDictionaryInAOF:aof];
        [d enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
            NSString* k = [[NSString alloc] initWithData:key encoding:NSUTF8StringEncoding];
            NSString* v = [[NSString alloc] initWithData:obj encoding:NSUTF8StringEncoding];
            NSString* d = [NSString stringWithFormat:@"%@ -> %@", k, v];
            fprintf(stdout, "%s\n", [d UTF8String]);
        }];
    } else if (!strcmp(op, "adddict")) {
        GTWAOFRawDictionary* d  = [[GTWAOFRawDictionary alloc] initFindingDictionaryInAOF:aof];
        NSMutableDictionary* dict   = [NSMutableDictionary dictionary];
        for (int i = 2; i < argc; i++) {
            NSString* s     = [NSString stringWithFormat:@"%s", argv[i]];
            NSArray* pair   = [s componentsSeparatedByString:@"="];
            NSString* k     = pair[0];
            NSString* v     = pair[1];
            NSData* key     = [k dataUsingEncoding:NSUTF8StringEncoding];
            NSData* val     = [v dataUsingEncoding:NSUTF8StringEncoding];
            dict[key]       = val;
        }
        
        NSLog(@"appending dictionary: %@", dict);
        [d dictionaryByAddingDictionary:dict];
    } else if (!strcmp(op, "mkdict")) {
        NSMutableDictionary* dict   = [NSMutableDictionary dictionary];
        for (int i = 2; i < argc; i++) {
            NSString* s     = [NSString stringWithFormat:@"%s", argv[i]];
            NSArray* pair   = [s componentsSeparatedByString:@"="];
            NSString* key   = pair[0];
            NSString* val   = pair[1];
            dict[key]       = val;
        }
        
        NSLog(@"creating dictionary: %@", dict);
        [GTWAOFRawDictionary dictionaryWithDictionary:dict aof:aof];
    } else if (!strcmp(op, "value")) {
        NSString* s     = [NSString stringWithFormat:@"%s", argv[2]];
        NSData* key     = [s dataUsingEncoding:NSUTF8StringEncoding];
        GTWAOFRawDictionary* d  = [[GTWAOFRawDictionary alloc] initFindingDictionaryInAOF:aof];
        NSData* value   = [d objectForKey:key];
        if (value) {
            NSString* v     = [[NSString alloc] initWithData:value encoding:NSUTF8StringEncoding];
            fprintf(stdout, "%s\n", [v UTF8String]);
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
        GTWAOFRawQuads* q  = [[GTWAOFRawQuads alloc] initFindingQuadsInAOF:aof];
        NSMutableArray* quads   = [NSMutableArray array];
        for (int i = 2; i < argc; i++) {
            NSString* s     = [NSString stringWithFormat:@"%s", argv[i]];
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
        [q quadsByAddingQuads:quads];
    } else if (!strcmp(op, "mkquads")) {
        NSMutableArray* quads   = [NSMutableArray array];
        for (int i = 2; i < argc; i++) {
            NSString* s     = [NSString stringWithFormat:@"%s", argv[i]];
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
        [GTWAOFRawQuads quadsWithQuads:quads aof:aof];
    } else if (!strcmp(op, "export")) {
        GTWAOFQuadStore* store  = [[GTWAOFQuadStore alloc] initWithAOF:aof];
        NSError* error;
        [store enumerateQuadsMatchingSubject:nil predicate:nil object:nil graph:nil usingBlock:^(id<GTWQuad> q) {
            fprintf(stdout, "%s\n", [[q description] UTF8String]);
        } error:&error];
    } else if (!strcmp(op, "import")) {
        GTWAOFQuadStore* store  = [[GTWAOFQuadStore alloc] initWithAOF:aof];
        __block NSError* error;
        NSString* filename  = [NSString stringWithFormat:@"%s", argv[2]];
        const char* basestr = (argc > 3) ? argv[3] : "http://base.example.org/";
        NSString* base      = [NSString stringWithFormat:@"%s", basestr];
        NSFileHandle* fh    = [NSFileHandle fileHandleForReadingAtPath:filename];
        SPKSPARQLLexer* l   = [[SPKSPARQLLexer alloc] initWithFileHandle:fh];
        GTWIRI* baseuri     = [[GTWIRI alloc] initWithValue:base];
        GTWIRI* graph       = [[GTWIRI alloc] initWithValue:base];
        SPKTurtleParser* p  = [[SPKTurtleParser alloc] initWithLexer:l base: baseuri];
        if (p) {
            [store beginBulkLoad];
            __block NSUInteger count    = 0;
            NSProgress* prog    = [NSProgress progressWithTotalUnitCount:INT64_MAX];
            [p enumerateTriplesWithBlock:^(id<GTWTriple> t) {
                GTWQuad* q  = [GTWQuad quadFromTriple:t withGraph:graph];
                [store addQuad:q error:&error];
                count++;
                [prog setCompletedUnitCount:count];
                if (count % 25 == 0) {
                    fprintf(stderr, "\r%llu quads (%s)", (unsigned long long) count, [[prog description] UTF8String]);
                }
            } error:nil];
            fprintf(stderr, "\n");
            [store endBulkLoad];
        } else {
            NSLog(@"Could not construct parser");
        }
    } else if (!strcmp(op, "delete")) {
        GTWAOFQuadStore* store  = [[GTWAOFQuadStore alloc] initWithAOF:aof];
        __block NSError* error;
        NSString* filename  = [NSString stringWithFormat:@"%s", argv[2]];
        const char* basestr = (argc > 3) ? argv[3] : "http://base.example.org/";
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
        NSString* filename  = [NSString stringWithFormat:@"%s", argv[2]];
        const char* basestr = (argc > 3) ? argv[3] : "http://base.example.org/";
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
            [GTWAOFRawQuads quadsWithQuads:quads aof:aof];
            [GTWAOFRawDictionary dictionaryWithDictionary:map aof:aof];
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
    } else if (!strcmp(op, "stress")) {
        stress(aof);
    }
    return 0;
}

