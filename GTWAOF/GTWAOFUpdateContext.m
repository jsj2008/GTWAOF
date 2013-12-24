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
        _aof            = aof;
        nextPageID      = [aof pageCount];
        _createdPages   = [NSMutableArray array];
        _registeredObjects  = [NSMutableSet set];
    }
    return self;
}

- (NSUInteger) pageSize {
    return [_aof pageSize];
}

- (NSUInteger) pageCount {
    return nextPageID;
}

- (GTWAOFPage*) readPage: (NSInteger) pageID {
    // TODO: created pages should be stored so that direct access by pageID is possible
    for (GTWAOFPage* p in _createdPages) {
        NSInteger pid    = p.pageID;
        if (pid == pageID) {
            return p;
        }
    }
    return [_aof readPage:pageID];
}

- (GTWAOFPage*) createPageWithData: (NSData*)data {
	uint64_t pageID	= __sync_fetch_and_add(&(nextPageID), 1);
    GTWAOFPage* page    = [[GTWAOFPage alloc] initWithPageID:pageID data:data committed:NO];
    [_createdPages addObject:page];
    return page;
}

- (BOOL)updateWithBlock:(BOOL(^)(GTWAOFUpdateContext* ctx))block {
    @throw [NSException exceptionWithName:@"us.kasei.sparql.aof.updatecontext" reason:@"Cannot run nested update blocks" userInfo:@{}];
}

- (void) registerPageObject:(id)object {
    [_registeredObjects addObject:object];
}

@end
