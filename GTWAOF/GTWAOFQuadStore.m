//
//  GTWAOFQuadStore.m
//  GTWAOF
//
//  Created by Gregory Williams on 12/9/13.
//  Copyright (c) 2013 Gregory Todd Williams. All rights reserved.
//

#import "GTWAOFQuadStore.h"
#import <GTWSWBase/GTWQuad.h>
#import <GTWSWBase/GTWVariable.h>
#import "GTWAOFUpdateContext.h"
#include <CommonCrypto/CommonDigest.h>
#import "NSData+GTWTerm.h"
#import <SPARQLKit/SPARQLKit.h>

#define BULK_LOADING_BATCH_SIZE 500

#define TS_OFFSET       8
#define PREV_OFFSET     16
#define RSVD_OFFSET     24
#define DATA_OFFSET     32

#define DEBUG           1

//static NSData* dataFromInteger(NSUInteger value) {
//    long long n = (long long) value;
//    long long bign  = NSSwapHostLongLongToBig(n);
//    return [NSData dataWithBytes:&bign length:8];
//}

//static NSUInteger integerFromData(NSData* data) {
//    long long bign;
//    [data getBytes:&bign range:NSMakeRange(0, 8)];
//    long long n = NSSwapBigLongLongToHost(bign);
//    return (NSUInteger) n;
//}

static const uint64_t NEXT_ID_TOKEN_VALUE  = 0xffffffffffffffff;


@implementation GTWAOFQuadStore

+ (NSString*) usage {
    return @"{ \"file\": <Path to AOF file> }";
}

+ (NSDictionary*) classesImplementingProtocols {
    NSSet* set  = [NSSet setWithObjects:@protocol(GTWQuadStore), nil];
    return @{ (id)[GTWAOFQuadStore class]: set };
}

+ (NSSet*) implementedProtocols {
    return [NSSet setWithObjects:@protocol(GTWQuadStore), nil];
}

- (instancetype) initWithDictionary: (NSDictionary*) dictionary {
    return [self initWithFilename:dictionary[@"file"]];
}

- (GTWAOFQuadStore*) initWithFilename: (NSString*) filename {
    if (self = [self init]) {
        self.aof   = [[GTWAOFDirectFile alloc] initWithFilename:filename flags:O_RDONLY|O_SHLOCK];
        if (!self.aof)
            return nil;
        
        NSInteger headerPageID  = [self lastQuadStoreHeaderPageID];
        if (headerPageID < 0) {
            NSLog(@"Failed to find a GTWAOFQuadStore page in AOF file %@", filename);
            return nil;
            //            return [GTWAOFRawQuads quadsWithQuads:@[] aof:aof];
        } else {
            _head   = [self.aof readPage:headerPageID];
            BOOL ok = [self _loadPointers];
            if (!ok)
                return nil;
        }
    }
    return self;
}

- (instancetype) initWithAOF: (id<GTWAOF,GTWMutableAOF>) aof {
    if (self = [self init]) {
        self.aof   = aof;

        NSInteger headerPageID  = [self lastQuadStoreHeaderPageID];
        if (headerPageID < 0) {
            NSLog(@"Failed to find a GTWAOFQuadStore page in AOF file %@", aof);
            return nil;
            //            return [GTWAOFRawQuads quadsWithQuads:@[] aof:aof];
        } else {
            _head   = [self.aof readPage:headerPageID];
            BOOL ok = [self _loadPointers];
            if (!ok)
                return nil;
        }
    }
    return self;
}

- (GTWAOFQuadStore*) initWithPageID:(NSInteger)pageID fromAOF:(id<GTWAOF,GTWMutableAOF>)aof {
    if (self = [self init]) {
        self.aof   = aof;
        _head   = [self.aof readPage:pageID];
        BOOL ok = [self _loadPointers];
        if (!ok)
            return nil;
    }
    return self;
}

- (GTWAOFQuadStore*) initWithPage:(GTWAOFPage*)page fromAOF:(id<GTWAOF,GTWMutableAOF>)aof {
    if (self = [self init]) {
        self.aof   = aof;
        _head   = page;
        BOOL ok = [self _loadPointers];
        if (!ok)
            return nil;
    }
    return self;
}

- (instancetype) init {
    if (self = [super init]) {
        _indexes            = [NSMutableDictionary dictionary];
        _termToRawDataCache = [[NSCache alloc] init];
        _termDataToIDCache  = [[NSCache alloc] init];
        _IDToTermCache      = [[NSMapTable alloc] init];
        _gen                = [[GTWTermIDGenerator alloc] initWithNextAvailableCounter:1];    // TODO: get the nextID from the quadstore and restore it here
        [_termToRawDataCache setCountLimit:128];
        [_termDataToIDCache setCountLimit:128];
    }
    return self;
}

- (NSData*) dataFromTerm: (id<GTWTerm>) t {
    NSData* data    = [_termToRawDataCache objectForKey:t];
    if (data)
        return data;
    data            = [NSData gtw_dataFromTerm:t];
//    NSLog(@"got data for term: %@ -> %@", t, data);
    [_termToRawDataCache setObject:data forKey:t];
    return data;
}

- (NSInteger) lastQuadStoreHeaderPageID {
    NSInteger pageID;
    NSInteger pageCount = [self.aof pageCount];
    NSInteger headerPageID  = -1;
    for (pageID = pageCount-1; pageID >= 0; pageID--) {
        //        NSLog(@"Checking page %lu for dictionary head", pageID);
        GTWAOFPage* p   = [self.aof readPage:pageID];
        NSData* data    = p.data;
        NSString* cookie  = [[NSString alloc] initWithData:[data subdataWithRange:NSMakeRange(0, 4)] encoding:NSUTF8StringEncoding];
        if ([cookie isEqual:@(QUAD_STORE_COOKIE)]) {
            headerPageID    = pageID;
            break;
        } else {
            //            NSLog(@"- cookie: %@", cookie);
        }
    }
    
    return headerPageID;
}

- (BOOL) _loadPointers {
    assert(self.aof);
    GTWAOFPage* p   = _head;
    NSData* data    = p.data;
    NSData* tdata   = [data subdataWithRange:NSMakeRange(0, 4)];
    if (memcmp(tdata.bytes, QUAD_STORE_COOKIE, 4)) {
        NSLog(@"*** Bad QuadStore cookie: %@", tdata);
        return NO;
    }
    
    int offset  = DATA_OFFSET;
    while ((offset+16) <= [self.aof pageSize]) {
        uint64_t big_offset = 0;
        NSData* type    = [data subdataWithRange:NSMakeRange(offset, 4)];
        if (!memcmp(type.bytes, "\0\0\0\0", 4)) {
            break;
        }
        NSData* name    = [data subdataWithRange:NSMakeRange(offset+4, 4)];
        [data getBytes:&big_offset range:NSMakeRange(offset+8, 8)];
        offset  += 16;
        
        NSString* typeName  = [[NSString alloc] initWithData:type encoding:NSUTF8StringEncoding];
        NSString* order     = [[NSString alloc] initWithData:name encoding:NSUTF8StringEncoding];
        uint64_t pageID     = NSSwapBigLongLongToHost(big_offset);
        if ([typeName isEqualToString:@"INDX"]) {
            if ([order isEqualToString:@"SPOG"]) {
//                NSLog(@"Found BTree index at page %llu", (unsigned long long)pageID);
                _indexes[@"SPOG"]  = [[GTWAOFBTree alloc] initWithRootPageID:pageID fromAOF:self.aof];
            } else {
                NSLog(@"Unexpected index order: %@", order);
                return NO;
            }
        } else if ([typeName isEqualToString:@"T2ID"]) {
            //            NSLog(@"Found BTree ID->Term tree at page %llu", (unsigned long long)pageID);
            _btreeTerm2ID   = [[GTWAOFBTree alloc] initWithRootPageID:pageID fromAOF:self.aof];
        } else if ([typeName isEqualToString:@"ID2T"]) {
            //            NSLog(@"Found BTree ID->Term tree at page %llu", (unsigned long long)pageID);
            _btreeID2Term   = [[GTWAOFBTree alloc] initWithRootPageID:pageID fromAOF:self.aof];
            NSData* token           = [NSData dataWithBytes:&NEXT_ID_TOKEN_VALUE length:8];
            NSData* value           = [_btreeID2Term objectForKey:token];
            uint64_t bignext;
            [value getBytes:&bignext length:8];
            NSInteger nextID    = (NSInteger)NSSwapBigLongLongToHost(bignext);
            _gen.nextID         = nextID;
        } else if ([typeName isEqualToString:@"DICT"]) {
//            NSLog(@"Found Raw Dictionary index at page %llu", (unsigned long long)pageID);
            _dict   = [GTWAOFRawDictionary rawDictionaryWithPageID:pageID fromAOF:self.aof];
        } else if ([typeName isEqualToString:@"QUAD"]) {
//            NSLog(@"Found Raw Quads index at page %llu", (unsigned long long)pageID);
            _quads   = [GTWAOFRawQuads rawQuadsWithPageID:pageID fromAOF:self.aof];
        } else {
            NSLog(@"Unexpected index pointer for page %llu: %@", (unsigned long long)pageID, typeName);
            return NO;
        }
    }
    return YES;
}

- (NSInteger) previousPageID {
    GTWAOFPage* p   = _head;
    NSData* data    = p.data;
    uint64_t big_prev = 0;
    [data getBytes:&big_prev range:NSMakeRange(PREV_OFFSET, 8)];
    unsigned long long prev = NSSwapBigLongLongToHost((unsigned long long) big_prev);
    return (NSInteger) prev;
}

- (GTWAOFRawQuads*) previousPage {
    if (self.previousPageID >= 0) {
        return [GTWAOFRawQuads rawQuadsWithPageID:self.previousPageID fromAOF:_aof];
    } else {
        return nil;
    }
}

- (GTWAOFPage*) head {
    return _head;
}

- (NSDate*) lastModified {
    GTWAOFPage* p   = _head;
    NSData* data    = p.data;
    uint64_t big_ts = 0;
    [data getBytes:&big_ts range:NSMakeRange(TS_OFFSET, 8)];
    unsigned long long ts = NSSwapBigLongLongToHost((unsigned long long) big_ts);
    return [NSDate dateWithTimeIntervalSince1970:(double)ts];
}

- (NSString*) pageType {
    return @(QUAD_STORE_COOKIE);
}

- (NSDictionary*) indexes {
    return [_indexes copy];
}

- (NSInteger) pageID {
    return _head.pageID;
}

- (NSArray*) getGraphsWithError:(NSError *__autoreleasing*)error {
    NSMutableSet* graphs    = [NSMutableSet set];
    BOOL ok                 = [self enumerateGraphsUsingBlock:^(id<GTWTerm> g) {
        [graphs addObject:g];
    } error:error];
    if (!ok)
        return nil;
    return [graphs allObjects];
}

- (BOOL) enumerateGraphsUsingBlock: (void (^)(id<GTWTerm> g)) block error:(NSError *__autoreleasing*)error {
    id<GTWTerm> (^dataToGraph)(NSData*) = ^id<GTWTerm>(NSData* data) {
        NSData* gkey        = [data subdataWithRange:NSMakeRange(24, 8)];
        id<GTWTerm> g       = [self _termFromIDData:gkey];
        if (!g) {
            NSLog(@"bad graph decoded from AOF quadstore");
            return nil;
        }
        return g;
    };
    
    NSMutableSet* graphs    = [NSMutableSet set];
    GTWAOFBTree* spog   = _indexes[@"SPOG"];
    [spog enumerateKeysAndObjectsUsingBlock:^(NSData *key, NSData *obj, BOOL *stop) {
        NSData* data        = key;
        id<GTWTerm> g       = dataToGraph(data);
        if (g) {
            [graphs addObject:g];
        } else {
            *stop   = YES;
        }
    }];
    if (NO) {
        // if the raw quads pages are used to store quads that aren't in the b+ tree, this block should be enabled
        [_quads enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            NSData* data        = obj;
            id<GTWTerm> g       = dataToGraph(data);
            if (g) {
                [graphs addObject:g];
            } else {
                *stop   = YES;
            }
        }];
    }
    for (id<GTWTerm> g in graphs) {
        block(g);
    }
    return YES;
}

- (NSArray*) getQuadsMatchingSubject: (id<GTWTerm>) s predicate: (id<GTWTerm>) p object: (id<GTWTerm>) o graph: (id<GTWTerm>) g error:(NSError *__autoreleasing*)error {
    NSMutableArray* quads   = [NSMutableArray array];
    BOOL ok = [self enumerateQuadsMatchingSubject:s predicate:p object:o graph:g usingBlock:^(id<GTWQuad> q) {
        [quads addObject:q];
    } error:error];
    if (!ok)
        return nil;
    return quads;
}

- (NSData*) spogPrefixMatchingSubject: (id<GTWTerm>) s predicate: (id<GTWTerm>) p object: (id<GTWTerm>) o graph: (id<GTWTerm>) g {
    NSMutableData* prefix   = [NSMutableData data];
    if (s && !([s isKindOfClass:[GTWVariable class]])) {
        [prefix appendData: [self _IDDataFromTerm:s]];
        if (p && !([p isKindOfClass:[GTWVariable class]])) {
            [prefix appendData: [self _IDDataFromTerm:p]];
            if (o && !([o isKindOfClass:[GTWVariable class]])) {
                [prefix appendData: [self _IDDataFromTerm:o]];
                if (g && !([g isKindOfClass:[GTWVariable class]])) {
                    [prefix appendData: [self _IDDataFromTerm:g]];
                }
            }
        }
    }
    return [prefix copy];
}

- (NSData*) _IDDataFromTermData:(NSData*)termData {
    NSData* ident   = [_termDataToIDCache objectForKey:termData];
    if (ident)
        return ident;
    
    NSData* hash    = [self hashData:termData];
    ident   = [_btreeTerm2ID objectForKey:hash];
    //    NSLog(@"got data for term: %@ -> %@", term, data);
    
    if (ident)
        [_termDataToIDCache setObject:ident forKey:termData];
    return ident;
}

- (NSData*) _IDDataFromTerm:(id<GTWTerm>)term {
    NSData* termData    = [self dataFromTerm:term];
    return [self _IDDataFromTermData:termData];
    NSData* hash    = [self hashData:termData];
    NSData* data    = [_btreeTerm2ID objectForKey:hash];
    NSLog(@"got data for term: %@ -> %@", term, data);
    return data;
//    NSData* d   = [_dict objectForKey:[self dataFromTerm:term]];
//    NSLog(@"-> %@", d);
//    return d;
}

- (id<GTWTerm>) _termFromIDData:(NSData*)idData {
    id<GTWTerm> term;
//    GTWTermIDGenerator* gen     = [[GTWTermIDGenerator alloc] init];
    term    = [_IDToTermCache objectForKey:idData];
    if (term) {
        return term;
    }
    
    term    = [_gen termForIdentifier:idData];
    if (term) {
        [_IDToTermCache setObject:term forKey:idData];
        return term;
    }
    
    NSData* pageData    = [_btreeID2Term objectForKey:idData];
//    NSLog(@"data for node %@ is on page %@", idData, pageData);

    uint64_t big_pid = 0;
    [pageData getBytes:&big_pid range:NSMakeRange(0, 8)];
    unsigned long long pid = NSSwapBigLongLongToHost((unsigned long long) big_pid);
    NSInteger pageID    = (NSInteger) pid;
    GTWAOFRawDictionary* d  = [GTWAOFRawDictionary rawDictionaryWithPageID:pageID fromAOF:self.aof];
    if (!d) {
        NSLog(@"Bad dictionary page %lld for term ID %@", (long long)pageID, idData);
        return nil;
    }
    NSData* data    = [d keyForObject:idData];
    if (!data) {
        NSLog(@"No data found in dictionary page for term ID %@", idData);
        return nil;
    }
    
    term            = [data gtw_term];
    if (!term)
        return nil;
    
    [_IDToTermCache setObject:term forKey:idData];
    return term;
}

- (BOOL) enumerateQuadsMatchingSubject: (id<GTWTerm>) s predicate: (id<GTWTerm>) p object: (id<GTWTerm>) o graph: (id<GTWTerm>) g usingBlock: (void (^)(id<GTWQuad> q)) block error:(NSError *__autoreleasing*)error {
    NSData* prefix  = [self spogPrefixMatchingSubject:s predicate:p object:o graph:g];
    
    void (^testQuad)(id<GTWQuad>) = ^(id<GTWQuad> q) {
        if (s && !([s isKindOfClass:[GTWVariable class]])) {
            if (![s isEqual:q.subject])
                return;
        }
        if (p && !([p isKindOfClass:[GTWVariable class]])) {
            if (![p isEqual:q.predicate])
                return;
        }
        if (o && !([o isKindOfClass:[GTWVariable class]])) {
            if (![o isEqual:q.object])
                return;
        }
        if (g && !([g isKindOfClass:[GTWVariable class]])) {
            if (![g isEqual:q.graph])
                return;
        }
        //        NSLog(@"enumerating matching quad: %@", q);
        block(q);
    };
    
    id<GTWQuad> (^dataToQuad)(NSData*) = ^id<GTWQuad>(NSData* data) {
        NSData* skey        = [data subdataWithRange:NSMakeRange(0, 8)];
        NSData* pkey        = [data subdataWithRange:NSMakeRange(8, 8)];
        NSData* okey        = [data subdataWithRange:NSMakeRange(16, 8)];
        NSData* gkey        = [data subdataWithRange:NSMakeRange(24, 8)];
        
        id<GTWTerm> s       = [self _termFromIDData:skey];
        id<GTWTerm> p       = [self _termFromIDData:pkey];
        id<GTWTerm> o       = [self _termFromIDData:okey];
        id<GTWTerm> g       = [self _termFromIDData:gkey];
        if (!s || !p || !o || !g) {
            NSLog(@"bad quad decoded from AOF quadstore");
            return nil;
        }
        GTWQuad* q          = [[GTWQuad alloc] initWithSubject:s predicate:p object:o graph:g];
        return q;
    };
    
    GTWAOFBTree* spog   = _indexes[@"SPOG"];
    [spog enumerateKeysAndObjectsMatchingPrefix:prefix usingBlock:^(NSData *key, NSData *obj, BOOL *stop) {
        NSData* data        = key;
        id<GTWQuad> q       = dataToQuad(data);
        if (q) {
            testQuad(q);
        } else {
            *stop   = YES;
        }
    }];
    if (NO) {
        // if the raw quads pages are used to store quads that aren't in the b+ tree, this block should be enabled
        [_quads enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            NSData* data        = obj;
            id<GTWQuad> q       = dataToQuad(data);
            if (q) {
                testQuad(q);
            } else {
                *stop   = YES;
            }
        }];
    }
    return YES;
}

- (BOOL) enumerateQuadsWithBlock: (void (^)(id<GTWQuad> q)) block error:(NSError *__autoreleasing*)error {
    return [self enumerateQuadsMatchingSubject:nil predicate:nil object:nil graph:nil usingBlock:block error:error];
}

//@optional
//- (NSEnumerator*) quadEnumeratorMatchingSubject: (id<GTWTerm>) s predicate: (id<GTWTerm>) p object: (id<GTWTerm>) o graph: (id<GTWTerm>) g error:(NSError **)error;
//- (BOOL) addIndexType: (NSString*) type value: (NSArray*) positions synchronous: (BOOL) sync error: (NSError**) error;
//- (NSString*) etagForQuadsMatchingSubject: (id<GTWTerm>) s predicate: (id<GTWTerm>) p object: (id<GTWTerm>) o graph: (id<GTWTerm>) g error:(NSError **)error;
//- (NSUInteger) countGraphsWithOutError:(NSError **)error;
//- (NSUInteger) countQuadsMatchingSubject: (id<GTWTerm>) s predicate: (id<GTWTerm>) p object: (id<GTWTerm>) o graph: (id<GTWTerm>) g error:(NSError **)error;

- (NSDate*) lastModifiedDateForQuadsMatchingSubject: (id<GTWTerm>) s predicate: (id<GTWTerm>) p object: (id<GTWTerm>) o graph: (id<GTWTerm>) g error:(NSError *__autoreleasing*)error {
    NSData* prefix  = [self spogPrefixMatchingSubject:s predicate:p object:o graph:g];
//    NSLog(@"PREFIX: %@", prefix);
    GTWAOFBTree* spog       = _indexes[@"SPOG"];
    GTWAOFBTreeNode* lca    = [spog lcaNodeForKeysWithPrefix:prefix];
//    NSLog(@"LCA: %@", lca);
    return [lca lastModified];
    
    // this is rather coarse-grained, but we don't expect to be using the raw-quads a lot
//    return [_quads lastModified];
}

- (GTWAOFQuadStore*) rewriteWithUpdateContext:(GTWAOFUpdateContext*) ctx {
    NSInteger prevID                    = [self previousPageID];
    NSInteger newPrevID                 = -1;
    if (prevID >= 0) {
        GTWAOFQuadStore* prev   = [[GTWAOFQuadStore alloc] initWithPageID:prevID fromAOF:self.aof];
//        NSLog(@"-> previous quadstore: %@", prev);
        if (prev) {
            GTWAOFQuadStore* newprev    = [prev rewriteWithUpdateContext:ctx];
            newPrevID   = newprev.pageID;
        }
//    } else {
//        NSLog(@"-> no previous quadstore");
    }
    
    GTWAOFBTree* oldspog                = _indexes[@"SPOG"];
    NSMutableDictionary* dictPageMap    = [NSMutableDictionary dictionary];
    GTWMutableAOFRawQuads* quads        = [_quads rewriteWithUpdateContext:ctx];
    GTWMutableAOFRawDictionary* dict    = [_dict rewriteWithPageMap:dictPageMap updateContext:ctx];
    GTWAOFBTree* spog                   = [oldspog rewriteWithUpdateContext:ctx];
    GTWAOFBTree* t2i                    = [_btreeTerm2ID rewriteWithUpdateContext:ctx];
    GTWAOFBTree* i2t;
    {
        // the id2term btree needs to be completely reconstructed becaue it has pageIDs of RawDictionary pages in the pair values
        NSMutableArray* pairs           = [NSMutableArray array];
        NSDictionary* pageMap    = [dictPageMap copy];
        [_btreeID2Term enumerateKeysAndObjectsUsingBlock:^(NSData *key, NSData *obj, BOOL *stop) {
            uint64_t big_pid = 0;
            [obj getBytes:&big_pid range:NSMakeRange(0, 8)];
            unsigned long long pid = NSSwapBigLongLongToHost((unsigned long long) big_pid);
            NSInteger oldPageID    = (NSInteger) pid;
            NSNumber* newPageNumber = pageMap[@(oldPageID)];
            NSInteger newPageID;
            if (newPageNumber) {
                newPageID   = [newPageNumber integerValue];
            } else {
                NSData* termData        = [dict keyForObject:key];
                GTWAOFPage* p           = [dict pageForKey:termData];
                newPageID               = p.pageID;
            }
            
//            NSLog(@"Remapping dictionary page %lld -> %lld", (long long)oldPageID, (long long)newPageID);
            pid     = (int64_t) newPageID;
            big_pid  = NSSwapHostLongLongToBig(pid);
            NSData* value   = [NSData dataWithBytes:&big_pid length:8];
            [pairs addObject:@[key, value]];
        }];
        NSEnumerator* e = [pairs objectEnumerator];
        i2t  = [[GTWMutableAOFBTree alloc] initBTreeWithKeySize:_btreeID2Term.keySize valueSize:_btreeID2Term.valSize pairEnumerator:e updateContext:ctx];
    }
    
    
//    NSLog(@"rewriting AOF QuadStore with previous QuadStore at page %lld", (long long)prevID);
//    NSLog(@"-> %@", self.aof);
    GTWMutableAOFQuadStore* newstore    = [[GTWMutableAOFQuadStore alloc] initWithPreviousPageID:newPrevID rawDictionary:dict rawQuads:quads idToTerm:i2t termToID:t2i btreeIndexes:@{@"SPOG": spog} updateContext:ctx];
    [ctx registerPageObject:newstore];
    return newstore;
}

- (NSData*) hashData:(NSData*)data {
    unsigned char digest[CC_SHA1_DIGEST_LENGTH];
    if (CC_SHA1([data bytes], (CC_LONG)[data length], digest)) {
        NSData* hash    = [NSData dataWithBytes:digest length:CC_SHA1_DIGEST_LENGTH];
        return hash;
    }
    return nil;
}

- (NSInteger) dictID {
    return _quads.pageID;
}

- (NSInteger) quadsID {
    return _quads.pageID;
}

- (NSInteger) btreeSPOGID {
    GTWAOFBTree* spog   = _indexes[@"SPOG"];
    return spog.pageID;
}

- (NSInteger) btreeID2TermID {
    return _btreeID2Term.pageID;
}

- (NSInteger) btreeTerm2IDID {
    return _btreeTerm2ID.pageID;
}

@end


@implementation GTWMutableAOFQuadStore

+ (NSString*) usage {
    return @"{ \"file\": <Path to AOF file> }";
}

+ (NSDictionary*) classesImplementingProtocols {
    NSSet* set = [NSSet setWithObjects:@protocol(GTWQuadStore), @protocol(GTWMutableQuadStore), nil];
    return @{ (id)[GTWMutableAOFQuadStore class]: set };
}

+ (NSSet*) implementedProtocols {
    return [NSSet setWithObjects:@protocol(GTWMutableQuadStore), nil];
}

- (instancetype) initWithDictionary: (NSDictionary*) dictionary {
    return [self initWithFilename:dictionary[@"file"]];
}

- (GTWMutableAOFQuadStore*) initWithFilename: (NSString*) filename {
    if (self = [self init]) {
        self.aof    = [[GTWAOFDirectFile alloc] initWithFilename:filename flags:O_RDWR|O_SHLOCK];
        if (!self.aof)
            return nil;
        
        if (self = [self initWithAOF:self.aof]) {
            
        }
    }
    return self;
}

- (instancetype) initWithAOF: (id<GTWAOF,GTWMutableAOF>) aof {
    if (self = [self init]) {
        self.aof   = aof;
        // if we don't find a header page ID, we need to create new pages here
        NSInteger headerPageID  = [self lastQuadStoreHeaderPageID];
        if (headerPageID < 0) {
            //            NSLog(@"Failed to find a RawDictionary page in AOF file; creating an empty one");
            
            __block NSInteger headPageID    = -1;
            [self.aof updateWithBlock:^BOOL(GTWAOFUpdateContext *ctx) {
                self.mutableQuads       = [GTWMutableAOFRawQuads mutableQuadsWithQuads:@[] updateContext:ctx];
                self.mutableDict        = [GTWMutableAOFRawDictionary mutableDictionaryWithDictionary:@{} updateContext:ctx];
                _indexes[@"SPOG"]       = [[GTWMutableAOFBTree alloc] initEmptyBTreeWithKeySize:32 valueSize:0 updateContext:ctx];
                self.mutableBtreeID2Term    = [[GTWMutableAOFBTree alloc] initEmptyBTreeWithKeySize:8 valueSize:8 updateContext:ctx];
                self.mutableBtreeTerm2ID    = [[GTWMutableAOFBTree alloc] initEmptyBTreeWithKeySize:CC_SHA1_DIGEST_LENGTH valueSize:8 updateContext:ctx];
                assert(self.mutableBtreeTerm2ID.aof);
//                NSLog(@"ID->Term page ID: %lld", (long long)_mutableBtreeID2Term.pageID);
                headPageID  = [self writeNewQuadStoreHeaderPageWithPreviousPageID:-1 rawDictionary:self.mutableDict rawQuads:self.mutableQuads idToTerm:self.mutableBtreeID2Term termToID:self.mutableBtreeTerm2ID btreeIndexes:[self indexes] updateContext:ctx];
                return YES;
            }];
            _head   = [self.aof readPage:headPageID];
        } else {
            _head   = [self.aof readPage:headerPageID];
            BOOL ok = [self _loadPointers];
            if (!ok)
                return nil;
        }
    }
    return self;
}

- (GTWMutableAOFRawQuads *)mutableQuads {
    return _mutableQuads;
}

- (void)setMutableQuads:(GTWMutableAOFRawQuads *)mutableQuads {
    _mutableQuads       = mutableQuads;
    _quads              = mutableQuads;
}

- (GTWMutableAOFRawDictionary *)mutableDict {
    return _mutableDict;
}

- (void)setMutableDict:(GTWMutableAOFRawDictionary *)mutableDict {
    _mutableDict    = mutableDict;
    _dict               = mutableDict;
}

//- (GTWMutableAOFBTree *)mutableBtreeSPOG {
//    return _mutableBtreeSPOG;
//}
//
//- (void)setMutableBtreeSPOG:(GTWMutableAOFBTree *)mutableBtreeSPOG {
//    _mutableBtreeSPOG   = mutableBtreeSPOG;
//    _indexes[@"SPOG"]   = mutableBtreeSPOG;
//}

- (GTWMutableAOFBTree *)mutableBtreeTerm2ID {
    return _mutableBtreeTerm2ID;
}

- (void)setMutableBtreeTerm2ID:(GTWMutableAOFBTree *)mutableBtreeTerm2ID {
    _mutableBtreeTerm2ID    = mutableBtreeTerm2ID;
    _btreeTerm2ID           = mutableBtreeTerm2ID;
}

- (GTWMutableAOFBTree *)mutableBtreeID2Term {
    return _mutableBtreeID2Term;
}

- (void)setMutableBtreeID2Term:(GTWMutableAOFBTree *)mutableBtreeID2Term {
    _mutableBtreeID2Term    = mutableBtreeID2Term;
    _btreeID2Term           = mutableBtreeID2Term;
}

- (BOOL) _loadPointers {
    GTWAOFPage* p   = _head;
    NSData* data    = p.data;
    NSData* tdata   = [data subdataWithRange:NSMakeRange(0, 4)];
    if (memcmp(tdata.bytes, QUAD_STORE_COOKIE, 4)) {
        NSLog(@"*** Bad QuadStore cookie: %@", tdata);
        return NO;
    }
    
    int offset  = DATA_OFFSET;
    while ((offset+16) <= [self.aof pageSize]) {
        uint64_t big_offset = 0;
        NSData* type    = [data subdataWithRange:NSMakeRange(offset, 4)];
        if (!memcmp(type.bytes, "\0\0\0\0", 4)) {
            break;
        }
        NSData* name    = [data subdataWithRange:NSMakeRange(offset+4, 4)];
        [data getBytes:&big_offset range:NSMakeRange(offset+8, 8)];
        offset  += 16;
        
        NSString* typeName  = [[NSString alloc] initWithData:type encoding:NSUTF8StringEncoding];
        NSString* order     = [[NSString alloc] initWithData:name encoding:NSUTF8StringEncoding];
        uint64_t pageID     = NSSwapBigLongLongToHost(big_offset);
        if ([typeName isEqualToString:@"INDX"]) {
            if ([order isEqualToString:@"SPOG"]) {
//                NSLog(@"Found BTree index at page %llu", (unsigned long long)pageID);
                _indexes[@"SPOG"]   = [[GTWMutableAOFBTree alloc] initWithRootPageID:pageID fromAOF:self.aof];
            } else {
                NSLog(@"Unexpected index order: %@", order);
                return NO;
            }
        } else if ([typeName isEqualToString:@"T2ID"]) {
            //            NSLog(@"Found BTree Term->ID tree at page %llu", (unsigned long long)pageID);
            self.mutableBtreeTerm2ID   = [[GTWMutableAOFBTree alloc] initWithRootPageID:pageID fromAOF:self.aof];
            assert(self.mutableBtreeTerm2ID.aof);
        } else if ([typeName isEqualToString:@"ID2T"]) {
            //            NSLog(@"Found BTree ID->Term tree at page %llu", (unsigned long long)pageID);
            self.mutableBtreeID2Term   = [[GTWMutableAOFBTree alloc] initWithRootPageID:pageID fromAOF:self.aof];
            NSData* token           = [NSData dataWithBytes:&NEXT_ID_TOKEN_VALUE length:8];
            NSData* value           = [_btreeID2Term objectForKey:token];
            uint64_t bignext;
            [value getBytes:&bignext length:8];
            NSInteger nextID    = (NSInteger)NSSwapBigLongLongToHost(bignext);
            _gen.nextID         = nextID;
        } else if ([typeName isEqualToString:@"DICT"]) {
//            NSLog(@"Found Raw Dictionary index at page %llu", (unsigned long long)pageID);
            self.mutableDict    = [[GTWMutableAOFRawDictionary alloc] initWithPageID:pageID fromAOF:self.aof];
        } else if ([typeName isEqualToString:@"QUAD"]) {
//            NSLog(@"Found Raw Quads index at page %llu", (unsigned long long)pageID);
            self.mutableQuads   = [[GTWMutableAOFRawQuads alloc] initWithPageID:pageID fromAOF:self.aof];
        } else {
            NSLog(@"Unexpected index pointer for page %llu: %@", (unsigned long long)pageID, typeName);
            return NO;
        }
    }
    return YES;
}

- (NSData*) dataFromQuad: (id<GTWQuad>) q {
    NSMutableData* quadData     = [NSMutableData data];
    for (id<GTWTerm> t in [q allValues]) {
        NSData* termData    = [self dataFromTerm: t];
        NSData* ident   = [self _IDDataFromTermData:termData];
        if (!ident) {
            //            NSLog(@"No ID found for term %@", t);
            return nil;
        }
        [quadData appendData:ident];
    }
    return quadData;
}

- (GTWMutableAOFQuadStore*) initWithPreviousPageID:(NSInteger)prevID rawDictionary:(GTWMutableAOFRawDictionary*)dict rawQuads:(GTWMutableAOFRawQuads*)quads idToTerm:(GTWAOFBTree*)i2t termToID:(GTWAOFBTree*)t2i btreeIndexes:(NSDictionary*)indexes updateContext:(GTWAOFUpdateContext*) ctx {
    if (self = [self init]) {
        NSInteger pageID    = [self writeNewQuadStoreHeaderPageWithPreviousPageID:prevID rawDictionary:dict rawQuads:quads idToTerm:i2t termToID:t2i btreeIndexes:indexes updateContext:ctx];
        _head               = [ctx readPage:pageID];
        self.mutableQuads   = quads;
        self.mutableDict    = dict;
        _indexes[@"SPOG"]   = indexes[@"SPOG"];
        _btreeID2Term       = i2t;
        _btreeTerm2ID       = t2i;
    }
    return self;
}

- (NSInteger) writeNewQuadStoreHeaderPageWithPreviousPageID:(NSInteger)prevID rawDictionary:(GTWAOFRawDictionary*)dict rawQuads:(GTWAOFRawQuads*)quads idToTerm:(GTWAOFBTree*)i2t termToID:(GTWAOFBTree*)t2i btreeIndexes:(NSDictionary*)indexes updateContext:(GTWAOFUpdateContext*) ctx {
    NSDictionary* pointers  = @{@"QUAD": quads, @"DICT": dict, @"ID2T": i2t, @"T2ID": t2i};
    NSData* pageData    = newQuadStoreHeaderData([ctx pageSize], prevID, pointers, indexes, NO);
    if(!pageData)
        return NO;
    GTWAOFPage* page    = [ctx createPageWithData:pageData];
//    NSLog(@"QuadStore header is at page %llu", (unsigned long long)page.pageID);
    return page.pageID;
}

//- (NSUInteger) nextID {
//    __block NSUInteger curMaxID = 0;
//    [_dict enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
//        NSUInteger ident  = integerFromData(obj);
//        if (ident > curMaxID) {
//            curMaxID    = ident;
//        }
//    }];
//    NSUInteger nextID   = curMaxID+1;
//    return nextID;
//}

- (BOOL) addQuad:(id<GTWQuad>)q error:(NSError *__autoreleasing*)error {
    if (_bulkLoading) {
        [_bulkQuads addObject:q];
        if ([_bulkQuads count] >= BULK_LOADING_BATCH_SIZE) {
            if (self.verbose)
                NSLog(@"Flushing %llu quads", (unsigned long long)[_bulkQuads count]);
            [self flushBulkQuads];
        }
        return YES;
    } else {
        [self addQuads:@[q] error:error];
        [self.aof updateWithBlock:^BOOL(GTWAOFUpdateContext *ctx) {
            [self writeNewQuadStoreHeaderPageWithPreviousPageID:self.pageID rawDictionary:_dict rawQuads:_quads idToTerm:_btreeID2Term termToID:_btreeTerm2ID btreeIndexes:_indexes updateContext:ctx];
            return YES;
        }];
        return YES;
    }
}

/**
 Caller is responsible for calling the writeNewQuadStoreHeaderPage... method to write a new header page.
 */
- (BOOL) addQuads: (NSArray*) quads error:(NSError *__autoreleasing*)error {
#if DEBUG
    NSInteger count;
    {
        GTWAOFBTree* spog   = _indexes[@"SPOG"];
        count = [spog count];
    }
#endif
//    __block NSUInteger nextID   = [self nextID];
    NSMutableDictionary* map    = [NSMutableDictionary dictionary];
    NSMutableArray* quadsData   = [NSMutableArray array];
//    GTWTermIDGenerator* gen     = [[GTWTermIDGenerator alloc] initWithNextAvailableCounter:nextID];
    for (id<GTWQuad> q in quads) {
        NSMutableData* quadData = [NSMutableData data];
        for (id<GTWTerm> t in [q allValues]) {
            BOOL verbose    = NO;
//            if ([t.value rangeOfString:@"(Boris_Groys|Heinrich_Gustav_Magnus)" options:NSRegularExpressionSearch].location != NSNotFound) {
//                verbose = YES;
//                NSLog(@"************************\nTerm: %@", t);
//            }
            NSData* ident      = [_gen identifierForTerm:t assign:NO];
            if (!ident) {
                NSData* termData    = [self dataFromTerm:t];
                ident       = map[termData];
                if (!ident) {
                    ident           = [self _IDDataFromTermData:termData];
                    if (verbose && ident)
                        NSLog(@"term already has ID: %@", ident);
                }
                if (!ident) {
                    if (verbose)
                        NSLog(@"term does not yet have an ID: %@", t);
                    ident      = [_gen identifierForTerm:t assign:YES];
                    if (!ident || [ident length] != 8) {
                        if (verbose)
                            NSLog(@"Unexpected term ID: %@", ident);
                        break;
                    }
//                    ident           = dataFromInteger(nextID++);
                    if (verbose)
                        NSLog(@"assigned ID %@", ident);
                    map[termData]   = ident;
                }
            }
            [quadData appendData:ident];
        }
        [quadsData addObject:quadData];
    }
    
    GTWMutableAOFBTree* i2t = self.mutableBtreeID2Term;
    GTWMutableAOFBTree* t2i = self.mutableBtreeTerm2ID;
    
    //    NSLog(@"creating new quads head");
    __block GTWMutableAOFRawQuads* rawquads = self.mutableQuads;
    GTWMutableAOFBTree* btree   = _indexes[@"SPOG"];
    __block NSInteger insertedCount = 0;
    [self.aof updateWithBlock:^BOOL(GTWAOFUpdateContext *ctx) {
        for (NSData* quadData in quadsData) {
            BOOL ok = [btree insertValue:[NSData data] forKey:quadData updateContext:ctx];
            if (ok) {
                insertedCount++;
            } else {
                NSLog(@"******** Duplicate insert? %@", quadData);
            }
        }
        if (NO) {
            // don't duplicate the quad in the rawquads and the btree; at some point, we can add here until we overflow and then bulk load the rawquads into the btree
            rawquads   = [rawquads mutableQuadsByAddingQuads:quadsData updateContext:ctx];
        }
//        NSLog(@"addQuads ctx: %@", ctx.createdPages);

        if ([map count]) {
            self.mutableDict    = [self.mutableDict dictionaryByAddingDictionary:map updateContext:ctx];
            GTWAOFRawDictionary* dict   = _dict;
//            [self.aof updateWithBlock:^BOOL(GTWAOFUpdateContext *ctx) {
                for (NSData* termData in map) {
                    NSData* hash    = [self hashData:termData];
    //                NSLog(@"generated hash %@ for term %@", hash, termData);
                    NSData* termID  = map[termData];
                    GTWAOFPage* p   = [dict pageForKey:termData];
                    NSInteger pageID;
                    if (p) {
                        pageID  = p.pageID;
                    } else {
                        pageID  = -1;
                    }
    //                NSLog(@"map: %@ -> %lld", termID, (long long)pageID);
                    
                    int64_t pid     = (int64_t) pageID;
                    int64_t bigpid  = NSSwapHostLongLongToBig(pid);
                    NSData* value   = [NSData dataWithBytes:&bigpid length:8];
                    [i2t insertValue:value forKey:termID updateContext:ctx];
                    [t2i insertValue:termID forKey:hash updateContext:ctx];
    //                NSLog(@"****** %@ -> %@", hash, termID);
                }
//                return YES;
//            }];
        }
        
        uint64_t next_id_value  = (uint64_t)_gen.nextID;
        uint64_t big_next       = NSSwapHostLongLongToBig(next_id_value);
        NSData* token           = [NSData dataWithBytes:&NEXT_ID_TOKEN_VALUE length:8];
        NSData* value           = [NSData dataWithBytes:&big_next length:8];
        [i2t replaceValue:value forKey:token updateContext:ctx];
        return YES;
    }];
    
#if DEBUG
    {
        GTWAOFBTree* spog   = _indexes[@"SPOG"];
        NSInteger newcount  = [spog count];
        if ((count+insertedCount) != newcount) {
            NSLog(@"SPOG index count is bad after inserting %lld new quads (old count = %lld, new count == %lld)", (long long)[quads count], (long long)count, (long long)newcount);
            assert(0);
        }
    }
#endif
    return YES;
}

- (BOOL) removeQuad: (id<GTWQuad>) q error:(NSError *__autoreleasing*)error {
    if (_bulkLoading) {
        NSLog(@"Cannot remove quad while bulk loading is in progress");
        return NO;
    } else {
        [self removeQuads:@[q] error:error];
        [self.aof updateWithBlock:^BOOL(GTWAOFUpdateContext *ctx) {
            [self writeNewQuadStoreHeaderPageWithPreviousPageID:self.pageID rawDictionary:_dict rawQuads:_quads idToTerm:_btreeID2Term termToID:_btreeTerm2ID btreeIndexes:[self indexes] updateContext:ctx];
            return YES;
        }];
        return YES;
    }
}

/**
 Caller is responsible for calling the writeNewQuadStoreHeaderPage... method to write a new header page.
 */
- (BOOL) removeQuads: (NSArray*) quads error:(NSError *__autoreleasing*)error {
//    __block NSUInteger nextID   = [self nextID];
    NSMutableArray* quadsData   = [NSMutableArray array];
//    GTWTermIDGenerator* gen     = [[GTWTermIDGenerator alloc] initWithNextAvailableCounter:nextID];
    for (id<GTWQuad> q in quads) {
        NSMutableData* quadData = [NSMutableData data];
        BOOL ok = YES;
        for (id<GTWTerm> t in [q allValues]) {
            NSData* ident      = [_gen identifierForTerm:t assign:NO];
            if (!ident) {
                ident               = [self _IDDataFromTermData:[self dataFromTerm:t]];
                if (!ident) {
                    NSLog(@"no identifier for term %@", t);
                    ok  = NO;
                    break;
                }
            }
            [quadData appendData:ident];
        }
        if (ok) {
            [quadsData addObject:quadData];
        }
    }
    NSLog(@"Remove quads: %@", quadsData);
    //    NSLog(@"creating new quads head");
    GTWMutableAOFBTree* btree   = _indexes[@"SPOG"];
    [self.aof updateWithBlock:^BOOL(GTWAOFUpdateContext *ctx) {
        for (NSData* quadData in quadsData) {
            [btree removeValueForKey:quadData updateContext:ctx];
        }
        //        NSLog(@"addQuads ctx: %@", ctx.createdPages);
        return YES;
    }];
    return YES;
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

- (void) flushBulkQuads {
    NSError* error;
    if ([_bulkQuads count]) {
        [self addQuads:_bulkQuads error:&error];
        if (error) {
            NSLog(@"%@", error);
        }
        [_bulkQuads removeAllObjects];
    }
}

- (void) endBulkLoad {
    if (!_bulkLoading) {
        NSLog(@"endBulkLoad called on store that is not bulk loading.");
        return;
    }
    [self flushBulkQuads];
    _bulkLoading    = NO;

    // rewrite QuadStore header page
    [self.aof updateWithBlock:^BOOL(GTWAOFUpdateContext *ctx) {
        [self writeNewQuadStoreHeaderPageWithPreviousPageID:self.pageID rawDictionary:_dict rawQuads:_quads idToTerm:_btreeID2Term termToID:_btreeTerm2ID btreeIndexes:[self indexes] updateContext:ctx];
        return YES;
    }];
}

NSData* newQuadStoreHeaderData( NSUInteger pageSize, int64_t prevPageID, NSDictionary* pagePointers, NSDictionary* indexPointers, BOOL verbose ) {
    int64_t max     = ((pageSize - DATA_OFFSET) / 16);
    if ([pagePointers count] > max) {
        NSLog(@"Too many index/page pointers seen while creating QuadStore header page");
        return nil;
    }
    
    uint64_t ts     = (uint64_t) [[NSDate date] timeIntervalSince1970];
    int64_t prev    = (int64_t) prevPageID;
    if (verbose) {
        NSLog(@"creating quads page data with previous page ID: %lld (%lld)", prevPageID, prev);
    }
    uint64_t bigts  = NSSwapHostLongLongToBig(ts);
    int64_t bigprev = NSSwapHostLongLongToBig(prev);
    
    NSMutableData* data = [NSMutableData dataWithLength:pageSize];
    [data replaceBytesInRange:NSMakeRange(0, 4) withBytes:QUAD_STORE_COOKIE];
    [data replaceBytesInRange:NSMakeRange(TS_OFFSET, 8) withBytes:&bigts];
    [data replaceBytesInRange:NSMakeRange(PREV_OFFSET, 8) withBytes:&bigprev];
    int offset  = DATA_OFFSET;
    for (NSString* name in indexPointers) {
        id<GTWAOFBackedObject> obj  = indexPointers[name];
        NSInteger pageID            = [obj pageID];
        if (verbose) {
            NSLog(@"handling index: %@", obj);
        }
        
        NSMutableData* key;
        key = [NSMutableData dataWithBytes:"INDX" length:4];
        [key appendData:[name dataUsingEncoding:NSUTF8StringEncoding]];
        if ([key length] != 8) {
            NSLog(@"Bad key size for QuadStore page key: '%@'", key);
            return nil;
        }
        
        [data replaceBytesInRange:NSMakeRange(offset, 8) withBytes:key.bytes];
        offset  += 8;
        
        int64_t pid     = (int64_t) pageID;
        int64_t bigpid  = NSSwapHostLongLongToBig(pid);
        [data replaceBytesInRange:NSMakeRange(offset, 8) withBytes:&bigpid];
        offset  += 8;
    }
    for (NSString* name in pagePointers) {
        id<GTWAOFBackedObject> obj  = pagePointers[name];
        NSInteger pageID            = [obj pageID];
        if (verbose) {
            NSLog(@"handling page pointer: %@", obj);
        }
        
        NSMutableData* key;
        NSString* string    = [NSString stringWithFormat:@"%@    ", name];
        key = [[string dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
        
        if ([key length] != 8) {
            NSLog(@"Bad key size for QuadStore page key: '%@'", key);
            return nil;
        }
        
        [data replaceBytesInRange:NSMakeRange(offset, 8) withBytes:key.bytes];
        offset  += 8;
        
        int64_t pid     = (int64_t) pageID;
        int64_t bigpid  = NSSwapHostLongLongToBig(pid);
        [data replaceBytesInRange:NSMakeRange(offset, 8) withBytes:&bigpid];
        offset  += 8;
    }
    if ([data length] != pageSize) {
        NSLog(@"page has bad size for quadstore: %llu", (unsigned long long)[data length]);
        return nil;
    }
    return data;
}

@end

