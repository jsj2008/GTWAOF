//
//  GTWAOFUpdateContext.m
//  GTWAOF
//
//  Created by Gregory Williams on 12/8/13.
//  Copyright (c) 2013 Gregory Todd Williams. All rights reserved.
//

#import "GTWAOFUpdateContext.h"

@implementation GTWAOFUpdateContext

- (GTWAOFUpdateContext*) initWithAOF: (id<GTWAOF>) aof {
    if (self = [self init]) {
        self.aof    = aof;
        nextPageID  = [aof pageCount];
        _createdPages   = [NSMutableArray array];
    }
    return self;
}

- (NSUInteger) pageSize {
    return [_aof pageSize];
}

- (GTWAOFPage*) readPage: (NSInteger) pageID {
    return [self.aof readPage:pageID];
}

- (GTWAOFPage*) createPageWithData: (NSData*)data {
	uint64_t pageID	= __sync_fetch_and_add(&(nextPageID), 1);
    GTWAOFPage* page    = [[GTWAOFPage alloc] initWithPageID:pageID data:data committed:NO];
    [_createdPages addObject:page];
    return page;
}

@end
