//
//  GTWAOFBTreeNode.m
//  GTWAOF
//
//  Created by Gregory Williams on 12/18/13.
//  Copyright (c) 2013 Gregory Todd Williams. All rights reserved.
//

#import "GTWAOFBTreeNode.h"
#import "GTWAOFUpdateContext.h"
#import "NSData+GTWCompare.h"

#define TS_OFFSET       8
#define COUNT_OFFSET    16
#define RSVD_OFFSET     24
#define DATA_OFFSET     32

#define KEY_LENGTH      32
#define VAL_LENGTH      8
#define OFFSET_LENGTH   8
#define MAX_BTREE_INTERNAL_PAGE_KEYS ((AOF_PAGE_SIZE-DATA_OFFSET)/(KEY_LENGTH+OFFSET_LENGTH)-1)
#define MAX_BTREE_LEAF_PAGE_KEYS     ((AOF_PAGE_SIZE-DATA_OFFSET)/(KEY_LENGTH+VAL_LENGTH))

static NSData* dataFromInteger(NSUInteger value) {
    long long n = (long long) value;
    long long bign  = NSSwapHostLongLongToBig(n);
    return [NSData dataWithBytes:&bign length:8];
}

static NSUInteger integerFromData(NSData* data) {
    long long bign;
    [data getBytes:&bign range:NSMakeRange(0, 8)];
    long long n = NSSwapBigLongLongToHost(bign);
    return (NSUInteger) n;
}


@implementation GTWAOFBTreeNode

- (GTWAOFBTreeNode*) initWithPageID:(NSInteger)pageID parentID:(NSInteger)parentID fromAOF:(id<GTWAOF>)aof {
    if (self = [self init]) {
        _aof        = aof;
        _page       = [aof readPage:pageID];
        _parentID   = parentID;
        if (![self _loadType]) {
            return nil;
        }
        [self _loadEntries];
    }
    return self;
}

- (GTWAOFBTreeNode*) initWithPage:(GTWAOFPage*)page parentID:(NSInteger)parentID fromAOF:(id<GTWAOF>)aof {
    if (self = [self init]) {
        _aof        = aof;
        _page       = page;
        _parentID   = parentID;
        if (![self _loadType]) {
            return nil;
        }
        [self _loadEntries];
    }
    return self;
}

- (BOOL) _loadType {
    GTWAOFPage* p   = _page;
    NSData* data    = p.data;
    NSData* tdata   = [data subdataWithRange:NSMakeRange(0, 4)];
    if (!memcmp(tdata.bytes, BTREE_LEAF_NODE_COOKIE, 4)) {
        _type   = GTWAOFBTreeLeafNodeType;
    } else if (!memcmp(tdata.bytes, BTREE_INTERNAL_NODE_COOKIE, 4)) {
        _type   = GTWAOFBTreeInternalNodeType;
    } else if (!memcmp(tdata.bytes, BTREE_ROOT_NODE_COOKIE, 4)) {
        _type   = GTWAOFBTreeRootNodeType;
    } else {
        return NO;
    }
    return YES;
}

- (void) _loadEntries {
    if (self.type == GTWAOFBTreeLeafNodeType) {
        int offset  = DATA_OFFSET;
        NSUInteger count    = [self count];
        NSUInteger i;
        NSData* data    = _page.data;
        NSMutableArray* keys    = [NSMutableArray array];
        NSMutableArray* vals    = [NSMutableArray array];
        for (i = 0; i < count; i++) {
            NSData* key = [data subdataWithRange:NSMakeRange(offset, KEY_LENGTH)];
            NSData* val = [data subdataWithRange:NSMakeRange(offset+KEY_LENGTH, VAL_LENGTH)];
            [keys addObject:key];
            [vals addObject:val];
            offset      += KEY_LENGTH+VAL_LENGTH;
        }
        _keys       = [keys copy];
        _objects    = [vals copy];
    } else {
        int offset  = DATA_OFFSET;
        NSUInteger count    = [self count];
        NSUInteger i;
        NSData* data    = _page.data;
        NSMutableArray* keys    = [NSMutableArray array];
        NSMutableArray* pageIDs = [NSMutableArray array];
        for (i = 0; i < count; i++) {
            NSData* key = [data subdataWithRange:NSMakeRange(offset, KEY_LENGTH)];
            NSData* val = [data subdataWithRange:NSMakeRange(offset+KEY_LENGTH, OFFSET_LENGTH)];
            NSUInteger pageID   = integerFromData(val);
            NSNumber* number    = [NSNumber numberWithInteger:pageID];
            [keys addObject:key];
            [pageIDs addObject:number];
            offset      += KEY_LENGTH+OFFSET_LENGTH;
        }
        {
            NSData* val = [data subdataWithRange:NSMakeRange(offset, OFFSET_LENGTH)];
            NSUInteger pageID   = integerFromData(val);
            NSNumber* number    = [NSNumber numberWithInteger:pageID];
            [pageIDs addObject:number];
        }
        
        _keys       = [keys copy];
        _pageIDs    = [pageIDs copy];
    }
}


- (NSInteger) pageID {
    return _page.pageID;
}

- (NSDate*) lastModified {
    GTWAOFPage* p   = _page;
    NSData* data    = p.data;
    uint64_t big_ts = 0;
    [data getBytes:&big_ts range:NSMakeRange(TS_OFFSET, 8)];
    unsigned long long ts = NSSwapBigLongLongToHost((unsigned long long) big_ts);
    return [NSDate dateWithTimeIntervalSince1970:(double)ts];
}

- (NSUInteger) count {
    GTWAOFPage* p       = _page;
    NSData* data        = p.data;
    uint64_t big_count  = 0;
    [data getBytes:&big_count range:NSMakeRange(COUNT_OFFSET, 8)];
    unsigned long long count = NSSwapBigLongLongToHost((unsigned long long) big_count);
    return (NSUInteger) count;
}

- (NSArray*) allKeys {
    return _keys;
}

- (NSData*) maxKey {
    NSArray* keys   = [self allKeys];
    return [keys lastObject];
}

- (NSData*) minKey {
    NSArray* keys   = [self allKeys];
    return [keys firstObject];
}

- (void)enumerateKeysAndPageIDsUsingBlock:(void (^)(NSData* key, NSInteger pageID, BOOL *stop))block {
    assert(self.type != GTWAOFBTreeLeafNodeType);
    NSUInteger i;
    NSUInteger count    = [self count];
    BOOL stop           = NO;
    for (i = 0; i < count; i++) {
        NSNumber* number    = _pageIDs[i];
        block(_keys[i], [number integerValue], &stop);
        if (stop)
            break;
    }
    if (!stop) {
        NSNumber* number    = _pageIDs[count];
        block(nil, [number integerValue], &stop);
    }
    return;
}

- (void)enumerateKeysAndObjectsUsingBlock:(void (^)(NSData* key, NSData* obj, BOOL *stop))block {
    assert(self.type == GTWAOFBTreeLeafNodeType);
    NSUInteger i;
    NSUInteger count    = [self count];
    BOOL stop           = NO;
    for (i = 0; i < count; i++) {
        block(_keys[i], _objects[i], &stop);
        if (stop)
            break;
    }
    return;
}

- (GTWAOFBTreeNode*) childForKey:(NSData*)key {
    assert(self.type != GTWAOFBTreeLeafNodeType);
    NSUInteger i;
    NSUInteger count    = [self count];
    for (i = 0; i < count; i++) {
        NSData* k = _keys[i];
        NSComparisonResult r    = [key gtw_compare:k];
        if (r != NSOrderedDescending) {
            NSNumber* number    = _pageIDs[i];
            NSInteger pageID    = [number integerValue];
            return [[GTWAOFBTreeNode alloc] initWithPageID:pageID parentID:self.pageID fromAOF:_aof];
        }
    }
    NSNumber* number    = _pageIDs[count];
    NSInteger pageID    = [number integerValue];
    return [[GTWAOFBTreeNode alloc] initWithPageID:pageID parentID:self.pageID fromAOF:_aof];
}

- (NSString*) description {
    NSMutableString *description = [NSMutableString stringWithFormat:@"<%@: %p; [0, %@]>", NSStringFromClass([self class]), self, [self maxKey]];
    return description;
}

- (BOOL) verify {
    return [self verifyHavingSeenRoot:NO];
}

- (BOOL) verifyHavingSeenRoot:(BOOL)seenRoot {
    NSLog(@"Verifying B+ Tree node %@ (on page %lld)", self, (long long)self.pageID);
    NSInteger count = [self count];
    NSArray* keys   = [self allKeys];
    if (count != [keys count]) {
        NSLog(@"Key count doesn't match number of keys found");
        return NO;
    }

    if (self.type == GTWAOFBTreeRootNodeType) {
        if (seenRoot) {
            NSLog(@"Unexpected root found in page %lld after already encountering root", (long long)self.pageID);
            return NO;
        }
        seenRoot    = YES;
    }
    
    NSInteger expectedLength    = -1;
    for (NSData* key in keys) {
        if (expectedLength > 0) {
            if ([key length] != expectedLength) {
                NSLog(@"Key with unexpected length (%llu) found (expecting %llu): %@", (unsigned long long)[key length], (unsigned long long)expectedLength, key);
                return NO;
            }
        } else {
            expectedLength  = [key length];
        }
        NSData* last    = nil;
        NSUInteger i;
        for (i = 0; i < count; i++) {
            NSData* key = _keys[i];
            if (i > 0) {
                NSComparisonResult r    = [last gtw_compare:key];
                if (r != NSOrderedAscending) {
                    NSLog(@"Keys in node are not in sorted order:\n- %@\n- %@", last, key);
                    return NO;
                }
            }
            last    = key;
        }
    }
    
    if ([keys count]) {
        if (![[self maxKey] isEqual: [keys lastObject]]) {
            NSLog(@"maxKey in page isn't actually the maximum found:\n- %@\n- %@", [self maxKey], [keys lastObject]);
            return NO;
        }
    }
    
    if (self.type == GTWAOFBTreeLeafNodeType) {
    } else {
        NSLog(@"Internal or root node with children pointers: %@", _pageIDs);
        if ((1+count) != [_pageIDs count]) {
            NSLog(@"Unexpected children pointer count (%llu) is not keys+1 (%llu+1)", (unsigned long long)[_pageIDs count], (unsigned long long)(count));
            return NO;
        }
        NSInteger i;
        NSData* lastMaxKey  = nil;
        for (i = 0; i <= count; i++) {
            NSNumber* number    = _pageIDs[i];
            NSInteger pageID    = [number integerValue];
            GTWAOFBTreeNode* child  = [[GTWAOFBTreeNode alloc] initWithPageID:pageID parentID:self.pageID fromAOF:_aof];
            BOOL ok = [child verifyHavingSeenRoot:seenRoot];
            if (!ok)
                return NO;
            if (i > 0) {
                NSData* childMin    = [child minKey];
                NSComparisonResult r    = [lastMaxKey gtw_compare:childMin];
                if (r != NSOrderedAscending) {
                    NSLog(@"Child (on page %lld) minKey (%@) is not greater-than the previously seen maxKey (%@)", (long long)child.pageID, childMin, lastMaxKey);
                    return NO;
                }
            }
            
            if (i < count) {
                NSData* key = _keys[i];
                NSData* childMax    = [child maxKey];
                if (![key isEqual:childMax]) {
                    NSLog(@"Child at page %lld has max key that differs from parent at page %lld key value\n- %@\n- %@", (long long)child.pageID, (long long)self.pageID, childMax, key);
                    return NO;
                }
                lastMaxKey  = key;
            }
        }
    }
    return YES;
}

@end

@implementation GTWMutableAOFBTreeNode

NSData* newLeafNodeData( NSUInteger pageSize, NSArray* keys, NSArray* objects, BOOL verbose ) {
    uint64_t ts     = (uint64_t) [[NSDate date] timeIntervalSince1970];
    if (verbose) {
        NSLog(@"creating btree leaf page data");
    }
    uint64_t bigts  = NSSwapHostLongLongToBig(ts);
    int64_t count       = [keys count];
    int64_t bigcount    = NSSwapHostLongLongToBig(count);
    
    NSMutableData* data = [NSMutableData dataWithLength:pageSize];
    [data replaceBytesInRange:NSMakeRange(0, 4) withBytes:BTREE_LEAF_NODE_COOKIE];
    [data replaceBytesInRange:NSMakeRange(TS_OFFSET, 8) withBytes:&bigts];
    [data replaceBytesInRange:NSMakeRange(COUNT_OFFSET, 8) withBytes:&bigcount];
    
    __block int offset  = DATA_OFFSET;
    NSUInteger i;
    if (count > MAX_BTREE_LEAF_PAGE_KEYS) {
        NSLog(@"Too many key-value pairs (%llu) in new leaf node", (unsigned long long)count);
        return nil;
    }
    for (i = 0; i < count; i++) {
        NSData* k   = keys[i];
        NSData* v   = objects[i];
        if (verbose) {
            NSLog(@"handling key-value %@=%@", k, v);
        }
        
        NSUInteger klen = [k length];
        NSUInteger vlen = [v length];
        if (klen != KEY_LENGTH) {
            NSLog(@"Key length is of unexpected size (%llu)", (unsigned long long)klen);
            return nil;
        }
        if (vlen != VAL_LENGTH) {
            NSLog(@"Value length is of unexpected size (%llu)", (unsigned long long)vlen);
            return nil;
        }
        
        [data replaceBytesInRange:NSMakeRange(offset, KEY_LENGTH) withBytes:[k bytes]];
        offset  += KEY_LENGTH;
        
        [data replaceBytesInRange:NSMakeRange(offset, VAL_LENGTH) withBytes:[v bytes]];
        offset  += VAL_LENGTH;
    }
    if ([data length] != pageSize) {
        NSLog(@"page has bad size for quads");
        return nil;
    }
    return data;
}

NSData* newInternalNodeData( NSUInteger pageSize, BOOL root, NSArray* keys, NSArray* childrenPageIDs, BOOL verbose ) {
    uint64_t ts     = (uint64_t) [[NSDate date] timeIntervalSince1970];
    if (verbose) {
        NSLog(@"creating btree internal page data with pointers: %@", childrenPageIDs);
    }
    uint64_t bigts  = NSSwapHostLongLongToBig(ts);
    int64_t count       = [keys count];
    int64_t bigcount    = NSSwapHostLongLongToBig(count);
    
    NSMutableData* data = [NSMutableData dataWithLength:pageSize];
    [data replaceBytesInRange:NSMakeRange(0, 4) withBytes:(root ? BTREE_ROOT_NODE_COOKIE : BTREE_LEAF_NODE_COOKIE)];
    [data replaceBytesInRange:NSMakeRange(TS_OFFSET, 8) withBytes:&bigts];
    [data replaceBytesInRange:NSMakeRange(COUNT_OFFSET, 8) withBytes:&bigcount];
    
    __block int offset  = DATA_OFFSET;
    NSUInteger i;
    if (count > MAX_BTREE_INTERNAL_PAGE_KEYS) {
        NSLog(@"Too many key-value pairs (%llu) in new intermediate node", (unsigned long long)count);
        return nil;
    }
    for (i = 0; i < count; i++) {
        NSData* k   = keys[i];
        NSNumber* number    = childrenPageIDs[i];
        NSData* v   = dataFromInteger([number integerValue]);
        if (verbose) {
            NSLog(@"handling key-value %@=%@", k, v);
        }
        
        NSUInteger klen = [k length];
        NSUInteger vlen = [v length];
        if (klen != KEY_LENGTH) {
            NSLog(@"Key length is of unexpected size (%llu)", (unsigned long long)klen);
            return nil;
        }
        if (vlen != OFFSET_LENGTH) {
            NSLog(@"Page ID pointer length is of unexpected size (%llu)", (unsigned long long)vlen);
            return nil;
        }
        
        [data replaceBytesInRange:NSMakeRange(offset, KEY_LENGTH) withBytes:[k bytes]];
        offset  += KEY_LENGTH;
        
        [data replaceBytesInRange:NSMakeRange(offset, OFFSET_LENGTH) withBytes:[v bytes]];
        offset  += OFFSET_LENGTH;
    }
    
    {
        NSNumber* number    = childrenPageIDs[count];
        NSData* v   = dataFromInteger([number integerValue]);
        NSLog(@"handling last-value %@", v);
        [data replaceBytesInRange:NSMakeRange(offset, OFFSET_LENGTH) withBytes:[v bytes]];
        offset  += OFFSET_LENGTH;
    }
    
    if ([data length] != pageSize) {
        NSLog(@"page has bad size for quads");
        return nil;
    }
    return data;
}

- (GTWMutableAOFBTreeNode*) initInternalWithParentID: (NSInteger) parentID keys:(NSArray*)keys pageIDs:(NSArray*)objects updateContext:(GTWAOFUpdateContext*) ctx {
    if (self = [self init]) {
        BOOL root       = (parentID == -1) ? YES : NO;
        NSData* data    = newInternalNodeData([ctx pageSize], root, keys, objects, YES);
        GTWAOFPage* p   = [ctx createPageWithData: data];
        self            = [self initWithPage:p parentID:parentID fromAOF:ctx.aof];
    }
    return self;
}

- (GTWMutableAOFBTreeNode*) initLeafWithParentID: (NSInteger) parentID keys:(NSArray*)keys objects:(NSArray*)objects updateContext:(GTWAOFUpdateContext*) ctx {
    if (self = [self init]) {
        NSData* data    = newLeafNodeData([ctx pageSize], keys, objects, YES);
        GTWAOFPage* p   = [ctx createPageWithData: data];
        self    = [self initWithPage:p parentID:parentID fromAOF:ctx.aof];
    }
    return self;
}

@end
