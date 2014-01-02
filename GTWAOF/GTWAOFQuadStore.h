//
//  GTWAOFQuadStore.h
//  GTWAOF
//
//  Created by Gregory Williams on 12/9/13.
//  Copyright (c) 2013 Gregory Todd Williams. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <GTWSWBase/GTWSWBase.h>
#import "GTWAOF.h"
#import "GTWAOFDirectFile.h"
#import "GTWAOFRawDictionary.h"
#import "GTWAOFRawQuads.h"
#import "GTWAOFBTree.h"
#import "GTWTermIDGenerator.h"

#define QUAD_STORE_COOKIE "QDST"

@interface GTWAOFQuadStore : NSObject<GTWQuadStore,GTWAOFBackedObject> {
    GTWAOFPage* _head;
    GTWAOFRawQuads* _quads;
    GTWAOFRawDictionary* _dict;
    NSMutableDictionary* _indexes;
    GTWAOFBTree* _btreeID2Term;
    GTWAOFBTree* _btreeTerm2ID;
    NSCache* _termToRawDataCache;
    NSCache* _termDataToIDCache;
    NSMapTable* _IDToTermCache;
    GTWTermIDGenerator* _gen;
}

@property (readwrite) BOOL verbose;
@property (readwrite) id<GTWAOF> aof;
@property (readonly) GTWAOFBTree* btreeID2Term;
@property (readonly) GTWAOFBTree* btreeTerm2ID;
@property (readwrite) GTWTermIDGenerator* gen;

+ (NSSet*) implementedProtocols;
- (GTWAOFQuadStore*) initWithFilename: (NSString*) filename;
- (GTWAOFQuadStore*) initWithAOF: (id<GTWAOF>) aof;
- (GTWAOFQuadStore*) initWithPageID:(NSInteger)pageID fromAOF:(id<GTWAOF>)aof;
- (GTWAOFQuadStore*) initWithPage:(GTWAOFPage*)page fromAOF:(id<GTWAOF>)aof;
- (GTWAOFQuadStore*) rewriteWithUpdateContext:(GTWAOFUpdateContext*) ctx;
- (NSDictionary*) indexes;
- (NSData*) hashData:(NSData*)data;

@end


@interface GTWMutableAOFQuadStore : GTWAOFQuadStore<GTWMutableQuadStore> {
    NSMutableArray* _bulkQuads;
    GTWMutableAOFRawDictionary* _mutableDict;
    GTWMutableAOFRawQuads* _mutableQuads;
    GTWMutableAOFBTree* _mutableBtreeID2Term;
    GTWMutableAOFBTree* _mutableBtreeTerm2ID;
}

@property BOOL bulkLoading;
@property (readwrite) id<GTWAOF,GTWMutableAOF> aof;
@property (readwrite) GTWMutableAOFRawDictionary* mutableDict;
@property (readwrite) GTWMutableAOFRawQuads* mutableQuads;
@property (readwrite) GTWMutableAOFBTree* mutableBtreeID2Term;
@property (readwrite) GTWMutableAOFBTree* mutableBtreeTerm2ID;

- (GTWMutableAOFQuadStore*) initWithFilename: (NSString*) filename;
- (GTWMutableAOFQuadStore*) initWithPreviousPageID:(NSInteger)prevID rawDictionary:(GTWMutableAOFRawDictionary*)dict rawQuads:(GTWMutableAOFRawQuads*)quads idToTerm:(GTWAOFBTree*)i2t termToID:(GTWAOFBTree*)t2i btreeIndexes:(NSDictionary*)indexes updateContext:(GTWAOFUpdateContext*) ctx;

- (void) beginBulkLoad;
- (void) endBulkLoad;

@end
