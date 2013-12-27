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
        _active         = YES;
        nextPageID      = [aof pageCount];
        _createdPages   = [NSMutableArray array];
        _registeredObjects  = [NSMutableSet set];
        _pageIndex      = [NSMutableDictionary dictionary];
    }
    return self;
}

- (NSUInteger) pageSize {
    return [_aof pageSize];
}

- (NSUInteger) pageCount {
    if (_active) {
        return nextPageID;
    } else {
        return [_aof pageCount];
    }
}

- (GTWAOFPage*) readPage: (NSInteger) pageID {
    if (_active) {
        GTWAOFPage* p   = _pageIndex[@(pageID)];
        if (p) {
            return p;
        }
    }
    return [_aof readPage:pageID];
}

- (GTWAOFPage*) createPageWithData: (NSData*)data {
    if (_active) {
        uint64_t pageID	= __sync_fetch_and_add(&(nextPageID), 1);
    //    NSLog(@"creating new page %llu", (unsigned long long)pageID);
        GTWAOFPage* page    = [[GTWAOFPage alloc] initWithPageID:pageID data:data committed:NO];
        [_createdPages addObject:page];
        _pageIndex[@(pageID)]   = page;
        return page;
    } else {
        @throw [NSException exceptionWithName:@"us.kasei.sparql.aof.updatecontext" reason:@"Cannot create new pages on inactive update context" userInfo:@{}];
    }
}

- (BOOL)updateWithBlock:(BOOL(^)(GTWAOFUpdateContext* ctx))block {
    @throw [NSException exceptionWithName:@"us.kasei.sparql.aof.updatecontext" reason:@"Cannot run nested update blocks" userInfo:@{}];
}

- (void) registerPageObject:(id)object {
    [_registeredObjects addObject:object];
}

- (NSString*) description {
    return [NSMutableString stringWithFormat:@"<%@: %p; %llu new pages>", NSStringFromClass([self class]), self, (unsigned long long)[_createdPages count]];
}

- (id)cachedObjectForPage:(NSInteger)pageID {
    return [_aof cachedObjectForPage:pageID];
}

- (void)setObject:(id)object forPage:(NSInteger)pageID {
    // can't cache the objects in an update context because they might not make it to disk
}

@end
