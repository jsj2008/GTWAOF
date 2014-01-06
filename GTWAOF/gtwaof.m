//
//  gtwaof.m
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
#import "GTWAOFMemoryMappedFile.h"

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

void usage ( int argc, const char* argv[]) {
    const char* cmd = argv[0];
    fprintf(stdout, "Usage:\n");
    fprintf(stdout, "    %s [OPTIONS] import FILE.ttl\n", cmd);
    fprintf(stdout, "    %s [OPTIONS] delete FILE.ttl\n", cmd);
    fprintf(stdout, "    %s [OPTIONS] export [S] [P] [O] [G]\n", cmd);
    fprintf(stdout, "\n");
    fprintf(stdout, "Options:\n");
    fprintf(stdout, "    -v     Produce verbose output.\n");
    fprintf(stdout, "    -B     Causes the export operation to work on the previous quad-store version state.\n");
    fprintf(stdout, "           This option may be used more than once to export arbitrary quad-store versions.\n");
    fprintf(stdout, "    -b BASE_URI\n");
    fprintf(stdout, "           Sets the base URI used during an import.\n");
    fprintf(stdout, "    -g GRAPH_URI\n");
    fprintf(stdout, "           Sets the graph URI used during an import.\n");
    fprintf(stdout, "\n");
}

int main(int argc, const char * argv[]) {
    if (argc < 2) {
        usage(argc, argv);
        return 0;
    }

    int argi                = 1;
    
    BOOL verbose            = NO;
    NSInteger back          = 0;
    NSInteger pageID        = -1;
    const char* filename    = "test.db";
    const char* basestr     = "http://base.example.org/";
    const char* graphstr    = NULL;
    
    while (argc > argi && argv[argi][0] == '-') {
        if (!strcmp(argv[argi], "-s")) {
            argi++;
            filename    = argv[argi++];
        } else if (!strcmp(argv[argi], "-p")) {
            argi++;
            pageID    = atoll(argv[argi++]);
        } else if (!strcmp(argv[argi], "-b")) {
            argi++;
            basestr = argv[argi++];
        } else if (!strcmp(argv[argi], "-g")) {
            argi++;
            graphstr = argv[argi++];
        } else if (!strcmp(argv[argi], "-B")) {
            argi++;
            back++;
        } else if (!strcmp(argv[argi], "-v")) {
            argi++;
            verbose = YES;
        } else if (!strcmp(argv[argi], "--help")) {
            usage(argc, argv);
            return 0;
        }
    }

    NSString* base      = [NSString stringWithFormat:@"%s", basestr];
    NSString* defaultGraph  = base;
    if (graphstr) {
        defaultGraph    = [NSString stringWithFormat:@"%s", graphstr];
    }
    
    double start    = current_time();
    srand([[NSDate date] timeIntervalSince1970]);
    const char* op  = argv[argi++];
    NSString* ops   = [NSString stringWithFormat:@"%s", op];
    if ([ops rangeOfString:@"(export)" options:NSRegularExpressionSearch].location == 0) {
        // read-only AOF branch
        id<GTWAOF> aof   = [[GTWAOFMemoryMappedFile alloc] initWithFilename:@(filename)];
        if (!strcmp(op, "export")) {
            //        NSLog(@"Exporting from QuadStore #%lld", (long long)pageID);
            GTWAOFQuadStore* store  = (pageID < 0) ? [[GTWAOFQuadStore alloc] initWithAOF:aof] : [[GTWAOFQuadStore alloc] initWithPageID:pageID fromAOF:aof];
//            NSLog(@"Current version: %lld", (long long)store.pageID);
            if (back) {
                while (back > 0) {
                    if (verbose) {
                        NSLog(@"Going back to a previous version");
                    }
                    back--;
                    store   = [store previousState];
                    if (!store) {
                        NSLog(@"Attempt to export from state of QuadStore prior to its creation");
                        return 1;
                    }
//                    NSLog(@"Current version: %lld", (long long)store.pageID);
                }
            }
            if (!store) {
                NSLog(@"Failed to create quad store object");
                return 1;
            }
            SPKTurtleParser* parser  = [[SPKTurtleParser alloc] init];
            id<GTWTerm> s, p, o, g;
            if (argc > argi) {
                const char* ss  = argv[argi++];
                if (strlen(ss)) {
                    s   = termFromData(parser, [NSData dataWithBytes:ss length:strlen(ss)]);
                }
            }
            if (argc > argi) {
                const char* ss  = argv[argi++];
                if (strlen(ss)) {
                    p   = termFromData(parser, [NSData dataWithBytes:ss length:strlen(ss)]);
                }
            }
            if (argc > argi) {
                const char* ss  = argv[argi++];
                if (strlen(ss)) {
                    o   = termFromData(parser, [NSData dataWithBytes:ss length:strlen(ss)]);
                }
            }
            if (argc > argi) {
                const char* ss  = argv[argi++];
                if (strlen(ss)) {
                    g   = termFromData(parser, [NSData dataWithBytes:ss length:strlen(ss)]);
                }
            }
            
            NSError* error;
            double start_export = current_time();
            if (verbose) {
                NSDate* date    = [store lastModifiedDateForQuadsMatchingSubject:s predicate:p object:o graph:g error:&error];
                fprintf(stderr, "# Last-Modified: %s\n\n", [[date descriptionWithCalendarFormat:@"%Y-%m-%dT%H:%M:%S%z" timeZone:[NSTimeZone localTimeZone] locale:[NSLocale currentLocale]] UTF8String]);
            }
            [store enumerateQuadsMatchingSubject:s predicate:p object:o graph:g usingBlock:^(id<GTWQuad> q) {
                fprintf(stdout, "%s\n", [[q description] UTF8String]);
            } error:&error];
            if (verbose) {
                fprintf(stderr, "export time: %lf\n", elapsed_time(start_export));
            }
        } else {
            NSLog(@"Unrecognized operation '%s'", op);
            return 1;
        }
    } else {
        // read-write AOF branch
        id<GTWAOF,GTWMutableAOF> aof   = [[GTWAOFDirectFile alloc] initWithFilename:@(filename)];
        if (!strcmp(op, "import")) {
            GTWMutableAOFQuadStore* store  = [[GTWMutableAOFQuadStore alloc] initWithAOF:aof];
            store.verbose       = verbose;
            __block NSError* error;
            NSString* filename  = [NSString stringWithFormat:@"%s", argv[argi++]];
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
                    if (verbose) {
                        if (count % 100 == 0) {
                            fprintf(stderr, "\r%llu quads", (unsigned long long) count);
                        }
                    }
                    GTWQuad* q  = [GTWQuad quadFromTriple:t withGraph:graph];
                    [store addQuad:q error:&error];
                    if (error) {
                        NSLog(@"%@", error);
                    }
                } error:&error];
                if (verbose) {
                    fprintf(stderr, "\n");
                }
                if (error) {
                    NSLog(@"%@", error);
                }
                [store endBulkLoad];
                double elapsed  = elapsed_time(start_import);
                if (verbose) {
                    fprintf(stderr, "import time: %lf\n", elapsed);
                    fprintf(stderr, "\r%llu quads imported (%.1f quads/second)\n", (unsigned long long) count, ((double)count/elapsed));
                }
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
            GTWIRI* graph       = [[GTWIRI alloc] initWithValue:defaultGraph];
            SPKTurtleParser* p  = [[SPKTurtleParser alloc] initWithLexer:l base: baseuri];
            if (p) {
    //            [store beginBulkLoad];
                __block NSUInteger count    = 0;
                [p enumerateTriplesWithBlock:^(id<GTWTriple> t) {
                    GTWQuad* q  = [GTWQuad quadFromTriple:t withGraph:graph];
                    [store removeQuad:q error:&error];
                    count++;
                    if (verbose) {
                        if (count % 25 == 0) {
                            fprintf(stderr, "\r%llu quads", (unsigned long long) count);
                        }
                    }
                } error:nil];
                if (verbose) {
                    fprintf(stderr, "\n");
                }
    //            [store endBulkLoad];
            } else {
                NSLog(@"Could not construct parser");
            }
        } else {
            NSLog(@"Unrecognized operation '%s'", op);
            return 1;
        }
    }
    
    if (verbose) {
        fprintf(stderr, "total time: %lf\n", elapsed_time(start));
    }
    
    return 0;
}

