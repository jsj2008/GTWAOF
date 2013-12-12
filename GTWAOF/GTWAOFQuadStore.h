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

@interface GTWAOFQuadStore : NSObject<GTWQuadStore, GTWMutableQuadStore> {
    id<GTWAOF> _aof;
    GTWAOFRawQuads* _quads;
    GTWAOFRawDictionary* _dict;
    NSMutableArray* _bulkQuads;
}

@property BOOL bulkLoading;
@property BOOL verbose;

- (GTWAOFQuadStore*) initWithFilename: (NSString*) filename;
- (GTWAOFQuadStore*) initWithAOF: (id<GTWAOF>) aof;

- (void) beginBulkLoad;
- (void) endBulkLoad;

@end
