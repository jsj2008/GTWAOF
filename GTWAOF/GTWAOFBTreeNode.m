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
#define FLAGS_OFFSET    24
#define SIZES_OFFSET    28
#define DATA_OFFSET     32

#define KEY_LENGTH      32
#define VAL_LENGTH      8
#define OFFSET_LENGTH   8

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

- (GTWAOFBTreeNode*) initWithPageID:(NSInteger)pageID parent:(GTWAOFBTreeNode*)parent fromAOF:(id<GTWAOF>)aof {
    if (self = [self init]) {
        _aof        = aof;
        _page       = [aof readPage:pageID];
        _parent     = parent;
        if (![self _loadType]) {
            return nil;
        }
        [self _loadEntries];
    }
    return self;
}

- (GTWAOFBTreeNode*) initWithPage:(GTWAOFPage*)page parent:(GTWAOFBTreeNode*)parent fromAOF:(id<GTWAOF>)aof {
    if (self = [self init]) {
        _aof        = aof;
        _page       = page;
        _parent     = parent;
        if (![self _loadType]) {
            return nil;
        }
        [self _loadEntries];
    }
    return self;
}

- (GTWAOFBTreeNode*) init {
    if (self = [super init]) {
        _keySize    = KEY_LENGTH;
        _valSize    = VAL_LENGTH;
        [self _updateConstraints];
    }
    return self;
}

- (void) setKeySize:(NSInteger)keySize {
    _keySize    = keySize;
    [self _updateConstraints];
}

- (void) setValSize:(NSInteger)valSize {
    _valSize    = valSize;
    [self _updateConstraints];
}

+ (NSInteger) maxInternalPageKeysForKeySize:(NSInteger)keySize {
    return ((AOF_PAGE_SIZE-DATA_OFFSET)/(keySize+OFFSET_LENGTH)-1);
}

+ (NSInteger) maxLeafPageKeysForKeySize:(NSInteger)keySize valueSize:(NSInteger)valSize {
    NSInteger d = keySize+valSize;
    if (d == 0) {
        d   = 1;
    }
    return ((AOF_PAGE_SIZE-DATA_OFFSET)/d);
}

- (void) _updateConstraints {
    _maxInternalPageKeys    = [[self class] maxInternalPageKeysForKeySize:_keySize];
    _maxLeafPageKeys        = [[self class] maxLeafPageKeysForKeySize:_keySize valueSize:_valSize];
}

- (BOOL) _loadType {
    GTWAOFPage* p   = _page;
    NSData* data    = p.data;
    NSData* tdata   = [data subdataWithRange:NSMakeRange(0, 4)];
    if (!memcmp(tdata.bytes, BTREE_LEAF_NODE_COOKIE, 4)) {
        _type   = GTWAOFBTreeLeafNodeType;
    } else if (!memcmp(tdata.bytes, BTREE_INTERNAL_NODE_COOKIE, 4)) {
        _type   = GTWAOFBTreeInternalNodeType;
    } else {
        return NO;
    }
    
    uint16_t big_ksize  = 0;
    uint16_t big_vsize  = 0;
    uint32_t big_flags  = 0;
    [data getBytes:&big_flags range:NSMakeRange(FLAGS_OFFSET, 4)];
    _flags = NSSwapBigIntToHost(big_flags);

    [data getBytes:&big_ksize range:NSMakeRange(SIZES_OFFSET, 2)];
    _keySize = (NSInteger)NSSwapBigShortToHost((unsigned long) big_ksize);
    [data getBytes:&big_vsize range:NSMakeRange(SIZES_OFFSET+2, 2)];
    _valSize = (NSInteger)NSSwapBigShortToHost((unsigned long) big_vsize);
    [self _updateConstraints];
    
    return YES;
}

- (void) _loadEntries {
    if (self.type == GTWAOFBTreeLeafNodeType) {
        int offset  = DATA_OFFSET;
        NSUInteger count    = [self count];
        NSInteger i;
        NSData* data    = _page.data;
        NSMutableArray* keys    = [NSMutableArray array];
        NSMutableArray* vals    = [NSMutableArray array];
        for (i = 0; i < count; i++) {
            NSData* key = [data subdataWithRange:NSMakeRange(offset, self.keySize)];
            NSData* val = [data subdataWithRange:NSMakeRange(offset+self.keySize, self.valSize)];
            [keys addObject:key];
            [vals addObject:val];
            offset      += self.keySize+self.valSize;
        }
        _keys       = [keys copy];
        _objects    = [vals copy];
    } else {
        int offset  = DATA_OFFSET;
        NSUInteger count    = [self count];
        NSInteger i;
        NSData* data    = _page.data;
        NSMutableArray* keys    = [NSMutableArray array];
        NSMutableArray* pageIDs = [NSMutableArray array];
        for (i = 0; i < count; i++) {
            NSData* key = [data subdataWithRange:NSMakeRange(offset, self.keySize)];
            NSData* val = [data subdataWithRange:NSMakeRange(offset+self.keySize, OFFSET_LENGTH)];
            NSUInteger pageID   = integerFromData(val);
            NSNumber* number    = [NSNumber numberWithInteger:pageID];
            [keys addObject:key];
            [pageIDs addObject:number];
            offset      += self.keySize+OFFSET_LENGTH;
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

- (BOOL) isRoot {
    uint32_t f = (_flags & GTWAOFBTreeRoot);
    return (f) ? YES : NO;
}

- (BOOL) isFull {
    NSUInteger count    = [_keys count];
    if (self.type == GTWAOFBTreeInternalNodeType) {
        return (count == self.maxLeafPageKeys);
    } else {
        return (count == self.maxInternalPageKeys);
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

- (NSArray*) allObjects {
    return _objects;
}

- (instancetype) parent {
    return _parent;
}

- (NSArray*) childrenPageIDs {
    return _pageIDs;
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
    assert(self.type == GTWAOFBTreeInternalNodeType);
    NSInteger i;
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
    NSInteger i;
    NSUInteger count    = [self count];
    BOOL stop           = NO;
    for (i = 0; i < count; i++) {
        block(_keys[i], _objects[i], &stop);
        if (stop)
            break;
    }
    return;
}

- (instancetype) childForKey:(NSData*)key {
    assert(self.type != GTWAOFBTreeLeafNodeType);
    Class class = [self class];
    NSInteger i;
    NSUInteger count    = [self count];
    for (i = 0; i < count; i++) {
        NSData* k = _keys[i];
        NSComparisonResult r    = [key gtw_compare:k];
        if (r != NSOrderedDescending) {
            NSNumber* number    = _pageIDs[i];
            NSInteger pageID    = [number integerValue];
            return [[class alloc] initWithPageID:pageID parent:self fromAOF:_aof];
        }
    }
    NSNumber* number    = _pageIDs[count];
    NSInteger pageID    = [number integerValue];
    return [[class alloc] initWithPageID:pageID parent:self fromAOF:_aof];
}

- (NSString*) description {
    NSMutableString *description = [NSMutableString stringWithFormat:@"<%@: %p; Page %llu; [0, %@]%@>", NSStringFromClass([self class]), self, (unsigned long long)self.pageID, [self maxKey], [self isRoot] ? @"; ROOT" : @""];
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

    if ([self isRoot]) {
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
        NSInteger i;
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
//        NSLog(@"Internal node with children pointers: %@", _pageIDs);
        if ((1+count) != [_pageIDs count]) {
            NSLog(@"Unexpected children pointer count (%llu) is not keys+1 (%llu+1)", (unsigned long long)[_pageIDs count], (unsigned long long)(count));
            return NO;
        }
        NSInteger i;
        NSData* lastMaxKey  = nil;
        for (i = 0; i <= count; i++) {
            NSNumber* number    = _pageIDs[i];
            NSInteger pageID    = [number integerValue];
            GTWAOFBTreeNode* child  = [[GTWAOFBTreeNode alloc] initWithPageID:pageID parent:self fromAOF:_aof];
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

+ (NSData*) newLeafDataWithPageSize:(NSUInteger)pageSize root:(BOOL)root keySize:(NSInteger)keySize valueSize:(NSInteger)valSize keys:(NSArray*)keys objects:(NSArray*)objects verbose:(BOOL)verbose {
    uint64_t ts     = (uint64_t) [[NSDate date] timeIntervalSince1970];
    if (verbose) {
        NSLog(@"creating btree leaf page data");
    }
    uint64_t bigts  = NSSwapHostLongLongToBig(ts);
    int64_t count       = [keys count];
    unsigned int flags  = 0;
    if (root) {
        flags   |= GTWAOFBTreeRoot;
    }
    int16_t ksize       = (int16_t) keySize;
    int16_t vsize       = (int16_t) valSize;

    int64_t bigcount    = NSSwapHostLongLongToBig(count);
    uint32_t bigflags   = (uint32_t) NSSwapHostIntToBig(flags);
    int16_t bigksize    = NSSwapHostShortToBig(ksize);
    int16_t bigvsize    = NSSwapHostShortToBig(vsize);
    
    NSMutableData* data = [NSMutableData dataWithLength:pageSize];
    [data replaceBytesInRange:NSMakeRange(0, 4) withBytes:BTREE_LEAF_NODE_COOKIE];
    [data replaceBytesInRange:NSMakeRange(TS_OFFSET, 8) withBytes:&bigts];
    [data replaceBytesInRange:NSMakeRange(COUNT_OFFSET, 8) withBytes:&bigcount];
    [data replaceBytesInRange:NSMakeRange(FLAGS_OFFSET, 4) withBytes:&bigflags];
    [data replaceBytesInRange:NSMakeRange(SIZES_OFFSET, 2) withBytes:&bigksize];
    [data replaceBytesInRange:NSMakeRange(SIZES_OFFSET+2, 2) withBytes:&bigvsize];
    
    __block int offset  = DATA_OFFSET;
    NSInteger i;
    NSInteger maxPageKeys   = [GTWAOFBTreeNode maxLeafPageKeysForKeySize:keySize valueSize:valSize];
    if (count > maxPageKeys) {
        NSLog(@"Too many key-value pairs (%llu) in new leaf node (max %llu)", (unsigned long long)count, (unsigned long long)maxPageKeys);
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
        if (klen != keySize) {
            NSLog(@"Key length (%llu) is of unexpected size (expecting %llu)", (unsigned long long)klen, (unsigned long long)keySize);
            return nil;
        }
        if (vlen != valSize) {
            NSLog(@"Value length (%llu) is of unexpected size (expecting %llu)", (unsigned long long)vlen, (unsigned long long)valSize);
            return nil;
        }
        
        [data replaceBytesInRange:NSMakeRange(offset, keySize) withBytes:[k bytes]];
        offset  += keySize;
        
        [data replaceBytesInRange:NSMakeRange(offset, valSize) withBytes:[v bytes]];
        offset  += valSize;
    }
    if ([data length] != pageSize) {
        NSLog(@"page has bad size for quads");
        return nil;
    }
    return data;
}

+ (NSData*) newInternalDataWithPageSize:(NSUInteger)pageSize root:(BOOL)root keySize:(NSInteger)keySize valueSize:(NSInteger)valSize keys:(NSArray*)keys childrenIDs:(NSArray*)childrenPageIDs verbose:(BOOL)verbose {
    uint64_t ts     = (uint64_t) [[NSDate date] timeIntervalSince1970];
    if (verbose) {
        NSLog(@"creating btree internal page data with pointers: %@", childrenPageIDs);
    }
    uint64_t bigts  = NSSwapHostLongLongToBig(ts);
    int64_t count       = [keys count];
    int32_t flags       = 0;
    if (root) {
        flags   |= GTWAOFBTreeRoot;
    }
    int16_t ksize       = (int16_t) keySize;
    int16_t vsize       = (int16_t) valSize;

    int64_t bigcount    = NSSwapHostLongLongToBig(count);
    int32_t bigflags    = (int32_t) NSSwapHostIntToBig((unsigned int) flags);
    int16_t bigksize    = NSSwapHostShortToBig(ksize);
    int16_t bigvsize    = NSSwapHostShortToBig(vsize);

    NSMutableData* data = [NSMutableData dataWithLength:pageSize];
    [data replaceBytesInRange:NSMakeRange(0, 4) withBytes:BTREE_INTERNAL_NODE_COOKIE];
    [data replaceBytesInRange:NSMakeRange(TS_OFFSET, 8) withBytes:&bigts];
    [data replaceBytesInRange:NSMakeRange(COUNT_OFFSET, 8) withBytes:&bigcount];
    [data replaceBytesInRange:NSMakeRange(FLAGS_OFFSET, 4) withBytes:&bigflags];
    [data replaceBytesInRange:NSMakeRange(SIZES_OFFSET, 2) withBytes:&bigksize];
    [data replaceBytesInRange:NSMakeRange(SIZES_OFFSET+2, 2) withBytes:&bigvsize];
    
    __block int offset  = DATA_OFFSET;
    NSInteger i;
    NSInteger maxPageKeys   = [GTWAOFBTreeNode maxInternalPageKeysForKeySize:keySize];
    if (count > maxPageKeys) {
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
        if (klen != keySize) {
            NSLog(@"Key length is of unexpected size (%llu)", (unsigned long long)klen);
            return nil;
        }
        if (vlen != OFFSET_LENGTH) {
            NSLog(@"Page ID pointer length is of unexpected size (%llu)", (unsigned long long)vlen);
            return nil;
        }
        
        [data replaceBytesInRange:NSMakeRange(offset, keySize) withBytes:[k bytes]];
        offset  += keySize;
        
        [data replaceBytesInRange:NSMakeRange(offset, OFFSET_LENGTH) withBytes:[v bytes]];
        offset  += OFFSET_LENGTH;
    }
    
    {
        NSNumber* number    = childrenPageIDs[count];
        NSData* v   = dataFromInteger([number integerValue]);
//        NSLog(@"handling last-value %@", v);
        [data replaceBytesInRange:NSMakeRange(offset, OFFSET_LENGTH) withBytes:[v bytes]];
        offset  += OFFSET_LENGTH;
    }
    
    if ([data length] != pageSize) {
        NSLog(@"page has bad size for quads");
        return nil;
    }
    return data;
}

- (GTWMutableAOFBTreeNode*) initInternalWithParent:(GTWAOFBTreeNode*)parent keySize:(NSInteger)keySize valueSize:(NSInteger)valSize keys:(NSArray*)keys pageIDs:(NSArray*)objects updateContext:(GTWAOFUpdateContext*) ctx {
    if (self = [self init]) {
        [self setKeySize:keySize];
        [self setValSize:valSize];
        BOOL root       = (parent) ? NO : YES;
        NSData* data    = [[self class] newInternalDataWithPageSize:[ctx pageSize] root:root keySize:keySize valueSize:valSize keys:keys childrenIDs:objects verbose:NO];
        if (!data)
            return nil;
        GTWAOFPage* p   = [ctx createPageWithData: data];
        self            = [self initWithPage:p parent:parent fromAOF:ctx.aof];
    }
    return self;
}

- (GTWMutableAOFBTreeNode*) initLeafWithParent:(GTWAOFBTreeNode*)parent keySize:(NSInteger)keySize valueSize:(NSInteger)valSize keys:(NSArray*)keys objects:(NSArray*)objects updateContext:(GTWAOFUpdateContext*) ctx {
    BOOL root       = (parent) ? NO : YES;
    NSData* data    = [[self class] newLeafDataWithPageSize:[ctx pageSize] root:root keySize:keySize valueSize:valSize keys:keys objects:objects verbose:NO];
    if (!data)
        return nil;
    GTWAOFPage* p   = [ctx createPageWithData: data];
    return [self initWithPage:p parent:parent fromAOF:ctx.aof];
}

+ (GTWMutableAOFBTreeNode*) rewriteInternalNode:(GTWAOFBTreeNode*)node replacingChildID:(NSInteger)oldID withNewNode:(GTWAOFBTreeNode*)newNode updateContext:(GTWAOFUpdateContext*) ctx {
    assert(node.type == GTWAOFBTreeInternalNodeType);
    NSMutableArray* keys    = [[node allKeys] mutableCopy];
    NSMutableArray* ids     = [[node childrenPageIDs] mutableCopy];
    NSUInteger i            = [ids indexOfObject:@(oldID)];
    if (i == NSNotFound) {
        NSLog(@"Attempt to rewrite node with unrecognized child ID %llu", (unsigned long long)oldID);
        return nil;
    }
    
    ids[i]          = @(newNode.pageID);
    if (i < ([keys count]-1)) {
        keys[i] = [newNode maxKey];
    }
    NSData* data    = [[self class] newInternalDataWithPageSize:[ctx pageSize] root:node.isRoot keySize:node.keySize valueSize:node.valSize keys:keys childrenIDs:ids verbose:NO];
    if (!data)
        return nil;
    GTWAOFPage* p   = [ctx createPageWithData:data];
    return [[GTWMutableAOFBTreeNode alloc] initWithPage:p parent:node.parent fromAOF:ctx.aof];
}

+ (GTWMutableAOFBTreeNode*) rewriteLeafNode:(GTWAOFBTreeNode*)node addingObject:(NSData*)object forKey:(NSData*)key updateContext:(GTWAOFUpdateContext*) ctx {
    assert(node.type == GTWAOFBTreeLeafNodeType);
    // TODO: assert that node isn't full
    NSMutableArray* keys    = [[node allKeys] mutableCopy];
    NSMutableArray* vals    = [[node allObjects] mutableCopy];
    NSUInteger i    = -1;
    for (i = 0; i < [keys count]; i++) {
        if ([key gtw_compare:keys[i]] == NSOrderedAscending)
            break;
    }
    [keys insertObject:key atIndex:i];
    [vals insertObject:object atIndex:i];
    NSData* data    = [self newLeafDataWithPageSize:[ctx pageSize] root:node.isRoot keySize:node.keySize valueSize:node.valSize keys:keys objects:vals verbose:NO];
    if (!data)
        return nil;
    GTWAOFPage* p   = [ctx createPageWithData:data];
    return [[GTWMutableAOFBTreeNode alloc] initWithPage:p parent:node.parent fromAOF:ctx.aof];
}

@end
