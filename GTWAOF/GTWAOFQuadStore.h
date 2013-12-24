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

@interface GTWAOFQuadStore : NSObject<GTWQuadStore> {
    id<GTWAOF> _aof;
    GTWAOFRawQuads* _quads;
    GTWAOFRawDictionary* _dict;
    GTWAOFBTree* _btreeSPOG;
    NSCache* _termCache;
}

@property BOOL verbose;

- (GTWAOFQuadStore*) initWithFilename: (NSString*) filename;
- (GTWAOFQuadStore*) initWithAOF: (id<GTWAOF>) aof;

@end


@interface GTWMutableAOFQuadStore : GTWAOFQuadStore<GTWMutableQuadStore> {
    NSMutableArray* _bulkQuads;
    GTWMutableAOFRawDictionary* _mutableDict;
    GTWMutableAOFRawQuads* _mutableQuads;
    GTWMutableAOFBTree* _mutableBtree;
}

@property BOOL bulkLoading;

- (GTWAOFQuadStore*) initWithFilename: (NSString*) filename;

- (void) beginBulkLoad;
- (void) endBulkLoad;

@end
