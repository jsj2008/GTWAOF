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

#define QUAD_STORE_COOKIE "QDST"

@interface GTWAOFQuadStore : NSObject<GTWQuadStore,GTWAOFBackedObject> {
    GTWAOFPage* _head;
    NSInteger _dictID;
    NSInteger _quadsID;
    NSInteger _btreeSPOGID;
    NSInteger _btreeID2TermID;
    GTWAOFRawQuads* _quads;
    GTWAOFRawDictionary* _dict;
    GTWAOFBTree* _btreeSPOG;
    GTWAOFBTree* _btreeID2Term;
    NSCache* _termCache;
}

@property BOOL verbose;
@property (readwrite) id<GTWAOF> aof;

- (GTWAOFQuadStore*) initWithFilename: (NSString*) filename;
- (GTWAOFQuadStore*) initWithAOF: (id<GTWAOF>) aof;
- (GTWAOFQuadStore*) initWithPageID:(NSInteger)pageID fromAOF:(id<GTWAOF>)aof;
- (GTWAOFQuadStore*) initWithPage:(GTWAOFPage*)page fromAOF:(id<GTWAOF>)aof;
- (GTWAOFQuadStore*) rewriteWithUpdateContext:(GTWAOFUpdateContext*) ctx;
- (NSSet*) indexes;

@end


@interface GTWMutableAOFQuadStore : GTWAOFQuadStore<GTWMutableQuadStore> {
    NSMutableArray* _bulkQuads;
    GTWMutableAOFRawDictionary* _mutableDict;
    GTWMutableAOFRawQuads* _mutableQuads;
    GTWMutableAOFBTree* _mutableBtreeSPOG;
    GTWMutableAOFBTree* _mutableBtreeID2Term;
}

@property BOOL bulkLoading;

- (GTWMutableAOFQuadStore*) initWithFilename: (NSString*) filename;
- (GTWMutableAOFQuadStore*) initWithPreviousPageID:(NSInteger)prevID rawDictionary:(GTWMutableAOFRawDictionary*)dict rawQuads:(GTWMutableAOFRawQuads*)quads idToTerm:(GTWAOFBTree*)i2t btreeIndexes:(NSDictionary*)indexes updateContext:(GTWAOFUpdateContext*) ctx;

- (void) beginBulkLoad;
- (void) endBulkLoad;

@end
