//
//  GTWAOFRawQuads.h
//  GTWAOF
//
//  Created by Gregory Williams on 12/9/13.
//  Copyright (c) 2013 Gregory Todd Williams. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "GTWAOF.h"
#import "GTWAOFPage.h"

#define RAW_QUADS_COOKIE "RQDS"

@class GTWMutableAOFRawQuads;

@interface GTWAOFRawQuads : NSObject<GTWAOFBackedObject> {
    GTWAOFPage* _head;
}

@property BOOL verbose;
@property (readwrite) id<GTWAOF> aof;

- (NSDate*) lastModified;
- (NSInteger) pageID;
- (NSInteger) previousPageID;
- (GTWAOFPage*) head;
- (GTWAOFRawQuads*) previousPage;

- (GTWAOFRawQuads*) initFindingQuadsInAOF:(id<GTWAOF>)aof;
- (GTWAOFRawQuads*) initWithPageID:(NSInteger)pageID fromAOF:(id<GTWAOF>)aof;
- (GTWAOFRawQuads*) initWithPage:(GTWAOFPage*)page fromAOF:(id<GTWAOF>)aof;

- (NSUInteger) count;
- (id) objectAtIndex: (NSUInteger) index;
- (void)enumerateDataRangeUsingBlock:(void (^)(NSData* obj, NSRange range, BOOL *stop))block;
- (void)enumerateObjectsUsingBlock:(void (^)(id obj, NSUInteger idx, BOOL *stop))block;
+ (void)enumerateObjectsForPage:(NSInteger) pageID fromAOF:(id<GTWAOF>)aof usingBlock:(void (^)(NSData* key, NSRange range, NSUInteger idx, BOOL *stop))block followTail:(BOOL)follow;
- (GTWMutableAOFRawQuads*) rewriteWithUpdateContext:(GTWAOFUpdateContext*) ctx;

@end

@interface GTWMutableAOFRawQuads : GTWAOFRawQuads

+ (GTWMutableAOFRawQuads*) mutableQuadsWithQuads:(NSArray *)quads updateContext:(GTWAOFUpdateContext*) ctx;
- (GTWMutableAOFRawQuads*) mutableQuadsByAddingQuads:(NSArray*) quads updateContext:(GTWAOFUpdateContext*) ctx;
+ (GTWAOFPage*) quadsPageWithQuads:(NSArray*)quads previousPageID: (NSInteger) prevID updateContext:(GTWAOFUpdateContext*) ctx;

@end
