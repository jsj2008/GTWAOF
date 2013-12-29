//
//  GTWAOFMemory.m
//  GTWAOF
//
//  Created by Gregory Williams on 12/28/13.
//  Copyright (c) 2013 Gregory Todd Williams. All rights reserved.
//

#import "GTWAOFMemory.h"
#import "GTWAOFUpdateContext.h"

@implementation GTWAOFMemory

- (GTWAOFMemory*) init {
    if (self = [super init]) {
        _updateQueue    = dispatch_queue_create("us.kasei.sparql.aof", DISPATCH_QUEUE_SERIAL);
        _pages          = [NSMutableDictionary dictionary];
        _pageSize       = AOF_PAGE_SIZE;
        _objectCache    = [[NSCache alloc] init];
        [_objectCache setCountLimit:128];
    }
    return self;
}

- (NSUInteger) pageCount {
    return [_pages count];
}

- (GTWAOFPage*) readPage: (NSInteger) pageID {
    return _pages[@(pageID)];
}

- (BOOL)updateWithBlock:(BOOL(^)(GTWAOFUpdateContext* ctx))block {
    @autoreleasepool {
        __block BOOL shouldCommit;
        __block GTWAOFUpdateContext* ctx;
        __block BOOL ok = YES;
        dispatch_sync(self.updateQueue, ^{
            ctx = [[GTWAOFUpdateContext alloc] initWithAOF:self];
            shouldCommit    = block(ctx);
            if (shouldCommit) {
                NSArray* pages  = ctx.createdPages;
                if ([pages count]) {
                    GTWAOFPage* first   = pages[0];
                    NSInteger prevID    = first.pageID-1;
                    for (GTWAOFPage* p in pages) {
                        if ([p.data length] != _pageSize) {
                            NSLog(@"Page has unexpected size %lu", [p.data length]);
                            ok  = NO;
                            return;
                        }
                        
                        if (p.pageID == (prevID+1)) {
                            _pages[@(p.pageID)] = p;
                            prevID  = p.pageID;
                        } else {
                            NSLog(@"Pages aren't consecutive in commit");
                            ok  = NO;
                            return;
                        }
                    }
                    for (id<GTWAOFBackedObject> object in ctx.registeredObjects) {
                        object.aof  = self;
                    }
                } else {
                    NSLog(@"update is empty");
                }
                
                ctx.active  = NO;
                ok  = YES;
                return;
            } else {
                ok  = NO;
                return;
            }
        });
        return ok;
    }
}

- (id)cachedObjectForPage:(NSInteger)pageID {
    return nil;
}

- (void)setObject:(id)object forPage:(NSInteger)pageID {
    return;
}

@end
