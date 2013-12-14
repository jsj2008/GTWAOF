//
//  GTWAOFQuadStore.m
//  GTWAOF
//
//  Created by Gregory Williams on 12/9/13.
//  Copyright (c) 2013 Gregory Todd Williams. All rights reserved.
//

#import "GTWAOFQuadStore.h"
#import <SPARQLKit/SPKTurtleParser.h>
#import <GTWSWBase/GTWQuad.h>
#import <GTWSWBase/GTWVariable.h>
#import <SPARQLKit/SPKNTriplesSerializer.h>

@implementation GTWAOFQuadStore

- (GTWAOFQuadStore*) initWithFilename: (NSString*) filename {
    if (self = [self init]) {
        _aof   = [[GTWAOFDirectFile alloc] initWithFilename:filename];
        if (!_aof)
            return nil;
        _quads  = [[GTWAOFRawQuads alloc] initFindingQuadsInAOF:_aof];
        _dict   = [[GTWAOFRawDictionary alloc] initFindingDictionaryInAOF:_aof];
    }
    return self;
}

- (GTWAOFQuadStore*) initWithAOF: (id<GTWAOF>) aof {
    if (self = [self init]) {
        _aof   = aof;
        _quads  = [[GTWAOFRawQuads alloc] initFindingQuadsInAOF:_aof];
        _dict   = [[GTWAOFRawDictionary alloc] initFindingDictionaryInAOF:_aof];
    }
    return self;
}

- (NSArray*) getGraphsWithOutError:(NSError **)error {
    NSMutableSet* graphs    = [NSMutableSet set];
    BOOL ok                 = [self enumerateGraphsUsingBlock:^(id<GTWTerm> g) {
        [graphs addObject:g];
    } error:error];
    if (!ok)
        return nil;
    return [graphs allObjects];
}

- (BOOL) enumerateGraphsUsingBlock: (void (^)(id<GTWTerm> g)) block error:(NSError **)error {
    SPKTurtleParser* p      = [[SPKTurtleParser alloc] init];
    p.baseIRI               = [[GTWIRI alloc] initWithValue:@"http://base.example.org/"];
    __block BOOL ok         = YES;
    [_quads enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        NSData* data        = obj;
        NSData* gkey        = [data subdataWithRange:NSMakeRange(24, 8)];
        NSData* tdata       = [_dict objectForKey:gkey];
        NSString* string    = [[NSString alloc] initWithData:tdata encoding:NSUTF8StringEncoding];
        SPKSPARQLLexer* lexer   = [[SPKSPARQLLexer alloc] initWithString:string];
        SPKSPARQLToken* t       = [lexer getTokenWithError:nil];
        if (!t) {
            ok  = NO;
            *stop   = YES;
        }
        id<GTWTerm> term        = [p tokenAsTerm:t withErrors:nil];
        if (!term) {
            NSLog(@"Cannot create term from token %@", t);
            ok  = NO;
            *stop   = YES;
        }
        block(term);
    }];
    return ok;
}

- (NSArray*) getQuadsMatchingSubject: (id<GTWTerm>) s predicate: (id<GTWTerm>) p object: (id<GTWTerm>) o graph: (id<GTWTerm>) g error:(NSError **)error {
    NSMutableArray* quads   = [NSMutableArray array];
    BOOL ok = [self enumerateQuadsMatchingSubject:s predicate:p object:o graph:g usingBlock:^(id<GTWQuad> q) {
        [quads addObject:q];
    } error:error];
    if (!ok)
        return nil;
    return quads;
}

- (id<GTWTerm>) termFromData: (NSData*) key usingParser:(SPKTurtleParser*) p {
    NSData* tdata      = [_dict objectForKey:key];
    NSString* string   = [[NSString alloc] initWithData:tdata encoding:NSUTF8StringEncoding];
    SPKSPARQLLexer* lexer   = [[SPKSPARQLLexer alloc] initWithString:string];
    SPKSPARQLToken* t       = [lexer getTokenWithError:nil];
    if (!t) {
        return nil;
    }
    id<GTWTerm> term        = [p tokenAsTerm:t withErrors:nil];
    if (!term) {
        NSLog(@"Cannot create term from token %@", t);
        return nil;
    }
    return term;
}

- (BOOL) enumerateQuadsMatchingSubject: (id<GTWTerm>) s predicate: (id<GTWTerm>) p object: (id<GTWTerm>) o graph: (id<GTWTerm>) g usingBlock: (void (^)(id<GTWQuad> q)) block error:(NSError **)error {
    return [self enumerateQuadsWithBlock:^(id<GTWQuad> t){
        if (s && !([s isKindOfClass:[GTWVariable class]])) {
            if (![s isEqual:t.subject])
                return;
        }
        if (p && !([p isKindOfClass:[GTWVariable class]])) {
            if (![p isEqual:t.predicate])
                return;
        }
        if (o && !([o isKindOfClass:[GTWVariable class]])) {
            if (![o isEqual:t.object])
                return;
        }
        if (g && !([g isKindOfClass:[GTWVariable class]])) {
            if (![g isEqual:t.graph])
                return;
        }
        //        NSLog(@"enumerating matching quad: %@", q);
        block(t);
    } error: error];
}

- (BOOL) enumerateQuadsWithBlock: (void (^)(id<GTWQuad> q)) block error:(NSError **)error {
    SPKTurtleParser* parser = [[SPKTurtleParser alloc] init];
    parser.baseIRI               = [[GTWIRI alloc] initWithValue:@"http://base.example.org/"];
    __block BOOL ok         = YES;
    NSCache* cache          = [[NSCache alloc] init];
    [cache setCountLimit:64];
    [_quads enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        NSData* data        = obj;
        NSData* skey        = [data subdataWithRange:NSMakeRange(0, 8)];
        NSData* pkey        = [data subdataWithRange:NSMakeRange(8, 8)];
        NSData* okey        = [data subdataWithRange:NSMakeRange(16, 8)];
        NSData* gkey        = [data subdataWithRange:NSMakeRange(24, 8)];
        
        id<GTWTerm> s       = termFromData(cache, parser, [_dict anyKeyForObject:skey]);
        id<GTWTerm> p       = termFromData(cache, parser, [_dict anyKeyForObject:pkey]);
        id<GTWTerm> o       = termFromData(cache, parser, [_dict anyKeyForObject:okey]);
        id<GTWTerm> g       = termFromData(cache, parser, [_dict anyKeyForObject:gkey]);
        GTWQuad* q          = [[GTWQuad alloc] initWithSubject:s predicate:p object:o graph:g];
        block(q);
    }];
    return ok;
}

static id<GTWTerm> termFromData(NSCache* cache, SPKTurtleParser* p, NSData* data) {
    id<GTWTerm> term    = [cache objectForKey:data];
    if (term)
        return term;
    
    NSString* string        = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    SPKSPARQLLexer* lexer   = [[SPKSPARQLLexer alloc] initWithString:string];
    // The parser needs the lexer for cases where a term is more than one token (e.g. datatyped literals)
    p.lexer = lexer;
//    NSLog(@"constructing term from data: %@", data);
    SPKSPARQLToken* t       = [lexer getTokenWithError:nil];
    if (!t)
        return nil;
    term        = [p tokenAsTerm:t withErrors:nil];
    if (!term) {
        NSLog(@"Cannot create term from token %@", t);
        return nil;
    }
    
    [cache setObject:term forKey:data];
    return term;
}

static NSData* dataFromTerm(id<GTWTerm> t) {
    NSString* str               = [SPKNTriplesSerializer nTriplesEncodingOfTerm:t];
    NSData* data                = [str dataUsingEncoding:NSUTF8StringEncoding];
    return data;
}

static NSData* dataFromInteger(NSUInteger value) {
    long long n = (long long) value;
    long long bign  = NSSwapHostLongLongToBig(n);
    return [NSData dataWithBytes:&bign length:8];
}

static NSUInteger integerFromData(NSData* data) {
    long long bign;
    [data getBytes:&bign range:NSMakeRange(0, 8)];
    long long n = NSSwapBigLongLongToHost(bign);
    return (NSUInteger) n;
}

- (NSData*) dataFromQuad: (id<GTWQuad>) q {
    NSMutableData* quadData     = [NSMutableData data];
    for (id<GTWTerm> t in [q allValues]) {
        NSData* termData    = dataFromTerm(t);
        NSData* ident   = [_dict objectForKey:termData];
        if (!ident) {
//            NSLog(@"No ID found for term %@", t);
            return nil;
        }
        [quadData appendData:ident];
    }
    return quadData;
}

- (NSUInteger) nextID {
    __block NSUInteger curMaxID = 0;
    [_dict enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        NSUInteger ident  = integerFromData(obj);
        if (ident > curMaxID) {
            curMaxID    = ident;
        }
    }];
    NSUInteger nextID   = curMaxID+1;
    return nextID;
}

- (BOOL) addQuad: (id<GTWQuad>) q error:(NSError **)error {
    if (_bulkLoading) {
        [_bulkQuads addObject:q];
        if ([_bulkQuads count] >= 4080) {
//        if ([_bulkQuads count] >= 1) {  // TODO: this limits pages to 1 quad during bulk loading
            if (self.verbose)
                NSLog(@"Flushing %llu quads", (unsigned long long)[_bulkQuads count]);
            [self endBulkLoad];
            [self beginBulkLoad];
        }
        return YES;
    }
    __block NSUInteger nextID   = [self nextID];
    NSMutableDictionary* map    = [NSMutableDictionary dictionary];
    NSMutableData* quadData     = [NSMutableData data];
    for (id<GTWTerm> t in [q allValues]) {
        NSData* termData    = dataFromTerm(t);
        NSData* ident       = map[termData];
        if (!ident) {
            ident           = [_dict objectForKey:termData];
//            NSLog(@"term already has ID: %@", ident);
        }
        if (!ident) {
//            NSLog(@"term does not yet have an ID: %@", t);
            ident           = dataFromInteger(nextID++);
            map[termData]   = ident;
        }
        [quadData appendData:ident];
    }

    if ([map count]) {
        _dict   = [_dict dictionaryByAddingDictionary:map];
    }
    _quads  = [_quads quadsByAddingQuads:@[quadData]];
    return YES;
}

- (BOOL) addQuads: (NSArray*) quads error:(NSError **)error {
    __block NSUInteger nextID   = [self nextID];
    NSMutableDictionary* map    = [NSMutableDictionary dictionary];
    NSMutableArray* quadsData   = [NSMutableArray array];
    for (id<GTWQuad> q in quads) {
        NSMutableData* quadData = [NSMutableData data];
        for (id<GTWTerm> t in [q allValues]) {
            NSData* termData    = dataFromTerm(t);
            NSData* ident       = map[termData];
            if (!ident) {
                ident           = [_dict objectForKey:termData];
//                NSLog(@"term already has ID: %@", ident);
            }
            if (!ident) {
//                NSLog(@"term does not yet have an ID: %@", t);
                ident           = dataFromInteger(nextID++);
                map[termData]   = ident;
            }
            [quadData appendData:ident];
        }
        [quadsData addObject:quadData];
    }
//    NSLog(@"creating new quads head");
    _quads  = [_quads quadsByAddingQuads:quadsData];
    if ([map count])
        _dict   = [_dict dictionaryByAddingDictionary:map];
    return YES;
}

- (BOOL) removeQuad: (id<GTWQuad>) q error:(NSError **)error {
    if (_bulkLoading) {
        NSLog(@"Cannot remove quad while bulk loading is in progress");
        return NO;
    }
    NSData* removeQuadData  = [self dataFromQuad:q];
    if (!removeQuadData) {
        // The quad cannot exist in the data because we don't have a node ID for at least one of the terms
        NSLog(@"Quad does not exist in data (missing term ID mapping)");
        return YES;
    }
//    NSLog(@"removing quad with data   : %@", removeQuadData);
    GTWAOFRawQuads* quads   = _quads;
    __block NSInteger pageID    = -1;
    NSMutableArray* pages   = [NSMutableArray array];
    while (quads) {
        [GTWAOFRawQuads enumerateObjectsForPage:quads.pageID fromAOF:_aof usingBlock:^(NSData *key, NSRange range, NSUInteger idx, BOOL *stop) {
            NSData* quadData    = [key subdataWithRange:range];
//            NSLog(@"-> checking quad with data: %@", quadData);
            if ([quadData isEqual:removeQuadData]) {
                pageID  = quads.pageID;
                *stop   = YES;
            }
        } followTail:NO];
        if (pageID >= 0) {
            // Found the quad in this page
            break;
        } else {
            // Didn't find the quad; Look in the page tail
            [pages addObject:@(quads.pageID)];
            NSInteger prev  = quads.previousPageID;
            if (prev >= 0) {
                quads   = [[GTWAOFRawQuads alloc] initWithPageID:prev fromAOF:_aof];
            } else {
                break;
            }
        }
    }
    
    if (pageID >= 0) {
//        NSLog(@"quad to remove is in page %lld", (long long) pageID);
//        NSLog(@"-> page head list: %@", [pages componentsJoinedByString:@", "]);
        
        NSMutableArray* quadsData   = [NSMutableArray array];
        GTWAOFRawQuads* quadsPage   = [[GTWAOFRawQuads alloc] initWithPageID:pageID fromAOF:_aof];
        [GTWAOFRawQuads enumerateObjectsForPage:pageID fromAOF:_aof usingBlock:^(NSData *key, NSRange range, NSUInteger idx, BOOL *stop) {
            NSData* quadData    = [key subdataWithRange:range];
            if (![quadData isEqual:removeQuadData]) {
                [quadsData addObject:quadData];
            }
        } followTail:NO];
        
        NSInteger tailID                = quadsPage.previousPageID;
//        NSLog(@"rewriting with tail ID: %lld", (long long)tailID);
        GTWAOFRawQuads* rewrittenPage;
        if (tailID >= 0) {
            GTWAOFRawQuads* quadsPageTail   = [[GTWAOFRawQuads alloc] initWithPageID:quadsPage.previousPageID fromAOF:_aof];
            rewrittenPage   = [quadsPageTail quadsByAddingQuads:quadsData];
        } else {
            rewrittenPage   = [GTWAOFRawQuads quadsWithQuads:quadsData aof:_aof];
        }
        
        tailID    = rewrittenPage.pageID;
//        NSLog(@"-> new page ID: %lld", (long long)rewrittenPage.pageID);
        _quads  = rewrittenPage;
        
        NSEnumerator* e = [pages reverseObjectEnumerator];
        for (NSNumber* n in e) {
            pageID  = [n integerValue];
            NSMutableArray* quadsData   = [NSMutableArray array];
            [GTWAOFRawQuads enumerateObjectsForPage:pageID fromAOF:_aof usingBlock:^(NSData *key, NSRange range, NSUInteger idx, BOOL *stop) {
                NSData* quadData    = [key subdataWithRange:range];
                if (![quadData isEqual:removeQuadData]) {
                    [quadsData addObject:quadData];
                }
            } followTail:NO];
            
//            NSLog(@"rewriting with tail ID: %lld", (long long)tailID);
            GTWAOFRawQuads* rewrittenPage   = [_quads quadsByAddingQuads:quadsData];
//            NSLog(@"-> new page ID: %lld", (long long)rewrittenPage.pageID);
            _quads  = rewrittenPage;
            tailID    = rewrittenPage.pageID;
        }
    }
    
    return NO;
}

- (void) beginBulkLoad {
    if (_bulkLoading) {
        NSLog(@"beginBulkLoad called on store that is already bulk loading.");
        return;
    }
    _bulkLoading    = YES;
    if (!_bulkQuads) {
        _bulkQuads      = [NSMutableArray array];
    }
}

- (void) endBulkLoad {
    if (!_bulkLoading) {
        NSLog(@"endBulkLoad called on store that is not bulk loading.");
        return;
    }
    _bulkLoading    = NO;
    NSError* error;
    [self addQuads:_bulkQuads error:&error];
    if (error) {
        NSLog(@"%@", error);
    }
    [_bulkQuads removeAllObjects];
}

//@optional
//- (NSEnumerator*) quadEnumeratorMatchingSubject: (id<GTWTerm>) s predicate: (id<GTWTerm>) p object: (id<GTWTerm>) o graph: (id<GTWTerm>) g error:(NSError **)error;
//- (BOOL) addIndexType: (NSString*) type value: (NSArray*) positions synchronous: (BOOL) sync error: (NSError**) error;
//- (NSString*) etagForQuadsMatchingSubject: (id<GTWTerm>) s predicate: (id<GTWTerm>) p object: (id<GTWTerm>) o graph: (id<GTWTerm>) g error:(NSError **)error;
//- (NSUInteger) countGraphsWithOutError:(NSError **)error;
//- (NSUInteger) countQuadsMatchingSubject: (id<GTWTerm>) s predicate: (id<GTWTerm>) p object: (id<GTWTerm>) o graph: (id<GTWTerm>) g error:(NSError **)error;

- (NSDate*) lastModifiedDateForQuadsMatchingSubject: (id<GTWTerm>) s predicate: (id<GTWTerm>) p object: (id<GTWTerm>) o graph: (id<GTWTerm>) g error:(NSError **)error {
    // this is rather coarse-grained, but we don't expect to be using the raw-quads a lot
    return [_quads lastModified];
}

@end
