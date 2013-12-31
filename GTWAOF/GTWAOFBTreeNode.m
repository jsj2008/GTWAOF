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
#import "GTWAOFPage+GTWAOFLinkedPage.h"

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

static inline NSUInteger integerFromData(NSData* data) {
    long long bign;
    [data getBytes:&bign range:NSMakeRange(0, 8)];
    long long n = NSSwapBigLongLongToHost(bign);
    return (NSUInteger) n;
}


@implementation GTWAOFBTreeNode

+ (GTWAOFBTreeNode*) nodeWithPageID:(NSInteger)pageID parent:(GTWAOFBTreeNode*)parent fromAOF:(id<GTWAOF>)aof {
    assert(aof);
    GTWAOFBTreeNode* d   = [aof cachedObjectForPage:pageID];
    if (d) {
        if (![d isKindOfClass:[GTWAOFBTreeNode class]]) {
            NSLog(@"Cached object is of unexpected type for page %lld", (long long)pageID);
            return nil;
        }
        return d;
    }
    return [[GTWAOFBTreeNode alloc] initWithPageID:pageID parent:parent fromAOF:aof];
}

- (GTWAOFBTreeNode*) initWithPageID:(NSInteger)pageID parent:(GTWAOFBTreeNode*)parent fromAOF:(id<GTWAOF>)aof {
    assert(aof);
    if (self = [self init]) {
        _aof        = aof;
        _page       = [aof readPage:pageID];
        if (!_page)
            return nil;
        _parent     = parent;
        if (![self _loadType]) {
            return nil;
        }
        [self _loadEntries];
        
        if (![[_page cookie] gtw_hasPrefix:[NSData dataWithBytes:"BPT" length:3]]) {
            NSLog(@"Bad cookie for raw quads");
            return nil;
        }
        [aof setObject:self forPage:_page.pageID];
    }
    return self;
}

- (GTWAOFBTreeNode*) initWithPage:(GTWAOFPage*)page parent:(GTWAOFBTreeNode*)parent fromAOF:(id<GTWAOF>)aof {
    GTWAOFBTreeNode* d   = [aof cachedObjectForPage:page.pageID];
    if (d) {
        if (![d isKindOfClass:[GTWAOFBTreeNode class]]) {
            NSLog(@"Cached object is of unexpected type for page %lld", (long long)page.pageID);
            return nil;
        }
        return d;
    }
    if (self = [self init]) {
        _aof        = aof;
        _page       = page;
        _parent     = parent;
        if (![self _loadType]) {
            return nil;
        }
        [self _loadEntries];
        
        if (![[_page cookie] gtw_hasPrefix:[NSData dataWithBytes:"BPT" length:3]]) {
            NSLog(@"Bad cookie for raw quads");
            return nil;
        }
        [aof setObject:self forPage:_page.pageID];
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

- (NSString*) pageType {
    return (self.type == GTWAOFBTreeInternalNodeType) ? @(BTREE_INTERNAL_NODE_COOKIE) : @(BTREE_LEAF_NODE_COOKIE);
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
    NSInteger ksize = self.keySize;
    if (self.type == GTWAOFBTreeLeafNodeType) {
        int offset  = DATA_OFFSET;
        NSUInteger count    = [self count];
        NSInteger i;
        NSData* data    = _page.data;
        NSMutableArray* keys    = [NSMutableArray array];
        NSMutableArray* vals    = [NSMutableArray array];
        NSInteger vsize = self.valSize;
        @autoreleasepool {
            for (i = 0; i < count; i++) {
                NSData* key = [data subdataWithRange:NSMakeRange(offset, ksize)];
                offset      += ksize;
                NSData* val = [data subdataWithRange:NSMakeRange(offset, vsize)];
                offset      += vsize;
                [keys addObject:key];
                [vals addObject:val];
            }
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
        @autoreleasepool {
            for (i = 0; i < count; i++) {
                NSData* key = [data subdataWithRange:NSMakeRange(offset, ksize)];
                offset      += ksize;
                NSData* val = [data subdataWithRange:NSMakeRange(offset, OFFSET_LENGTH)];
                offset      += OFFSET_LENGTH;
                NSUInteger pageID   = integerFromData(val);
                NSNumber* number    = [NSNumber numberWithInteger:pageID];
                [keys addObject:key];
                [pageIDs addObject:number];
            }
            {
                NSData* val = [data subdataWithRange:NSMakeRange(offset, OFFSET_LENGTH)];
                NSUInteger pageID   = integerFromData(val);
                NSNumber* number    = [NSNumber numberWithInteger:pageID];
                [pageIDs addObject:number];
            }
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
        return (count == self.maxInternalPageKeys);
    } else {
        return (count == self.maxLeafPageKeys);
    }
}

- (BOOL) isMinimum {
    NSUInteger count    = [_keys count];
    if (self.type == GTWAOFBTreeInternalNodeType) {
        return (count <= self.minInternalPageKeys);
    } else {
        return (count <= self.minLeafPageKeys);
    }
}

- (NSInteger) minInternalPageKeys {
    NSInteger max   = [self maxInternalPageKeys];
    NSInteger min   = max/2;
    return min;
}

- (NSInteger) minLeafPageKeys {
    NSInteger max   = [self maxLeafPageKeys];
    NSInteger min   = max/2;
    return min;
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

- (NSArray*) allPairs {
    assert(self.type == GTWAOFBTreeLeafNodeType);
    NSMutableArray* pairs   = [NSMutableArray array];
    for (NSInteger i = 0; i < [_keys count]; i++) {
        [pairs addObject:@[_keys[i], _objects[i]]];
    }
    return pairs;
}

- (NSArray*) childrenPageIDs {
    return _pageIDs;
}

- (NSData*) objectForKey:(NSData*)key {
    assert(self.type == GTWAOFBTreeLeafNodeType);
    NSArray* keys    = [self allKeys];
    NSArray* vals    = [self allObjects];
    NSInteger found         = -1;
    for (NSUInteger i = 0; i < [keys count]; i++) {
        if ([keys[i] isEqual:key]) {
            found   = i;
            break;
        }
    }
    if (found < 0) {
//        NSLog(@"Attempt to access node value for missing key: %@", key);
//        NSLog(@"--> existing keys: %@", keys);
        return nil;
    }
    return vals[found];
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
            return [class nodeWithPageID:pageID parent:self fromAOF:_aof];
        }
    }
    NSNumber* number    = _pageIDs[count];
    NSInteger pageID    = [number integerValue];
    return [[class alloc] initWithPageID:pageID parent:self fromAOF:_aof];
}

- (NSString*) longDescription {
    NSData* max = [self maxKey];
    NSString* type  = (self.type == GTWAOFBTreeLeafNodeType) ? @"Leaf" : @"Internal";
    NSInteger count = [self count];
    if (self.type == GTWAOFBTreeInternalNodeType) {
        count++;    // the count is for the keys. internal nodes also have a key-less (right-most) child
    }
    NSMutableString* description = [NSMutableString stringWithFormat:@"----------\n<%@ %@: %p; Page %llu; %lld items; [0, %@]%@>\n", type, NSStringFromClass([self class]), self, (unsigned long long)self.pageID, (unsigned long long)count, (max ? max : @"-"), [self isRoot] ? @"; ROOT" : @""];
    NSArray* keys   = [self allKeys];
    NSInteger keycount  = [keys count];
    if (self.type == GTWAOFBTreeInternalNodeType) {
        NSArray* objects = [self childrenPageIDs];
        for (NSInteger i = 0; i < keycount; i++) {
            NSInteger childPageID   = [objects[i] integerValue];
            GTWAOFBTreeNode* child  = [GTWAOFBTreeNode nodeWithPageID:childPageID parent:self fromAOF:self.aof];
            [description appendFormat:@"\t[%3d] %@ -> %@\n", (int)i, keys[i], child];
        }
        {
            NSInteger childPageID   = [objects[keycount] integerValue];
            GTWAOFBTreeNode* child  = [GTWAOFBTreeNode nodeWithPageID:childPageID parent:self fromAOF:self.aof];
            [description appendFormat:@"\t[%3d]      -> %@\n", (int)keycount, child];
        }
    } else {
        NSArray* objects = [self allObjects];
        for (NSInteger i = 0; i < keycount; i++) {
            [description appendFormat:@"\t[%3d] %@ -> %@\n", (int)i, keys[i], objects[i]];
        }
    }
    [description appendFormat:@"----------\n"];
    return description;
}

- (NSString*) description {
    NSData* max = [self maxKey];
    NSString* type  = (self.type == GTWAOFBTreeLeafNodeType) ? @"Leaf" : @"Internal";
    NSInteger count = [self count];
    if (self.type == GTWAOFBTreeInternalNodeType) {
        count++;    // the count is for the keys. internal nodes also have a key-less (right-most) child
    }
    NSMutableString *description = [NSMutableString stringWithFormat:@"<%@ %@: %p; Page %llu; %lld items; [0, %@]%@>", type, NSStringFromClass([self class]), self, (unsigned long long)self.pageID, (unsigned long long)count, (max ? max : @"-"), [self isRoot] ? @"; ROOT" : @""];
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
            GTWAOFBTreeNode* child  = [GTWAOFBTreeNode nodeWithPageID:pageID parent:self fromAOF:_aof];
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

- (GTWAOFBTreeNode*) fullestSibling {
    if (self.isRoot)
        return nil;
    GTWAOFBTreeNode* parent = self.parent;
    NSInteger pageID        = self.pageID;
    NSArray* array          = parent.childrenPageIDs;
    NSMutableArray* siblings    = [NSMutableArray array];
    for (NSInteger i = 0; i < [array count]; i++) {
        NSNumber* number    = array[i];
        if (pageID == [number integerValue]) {
            if (i > 0) {
                NSInteger pid = [array[i-1] integerValue];
                GTWAOFBTreeNode* sib   = [GTWAOFBTreeNode nodeWithPageID:pid parent:parent fromAOF:self.aof];
                [siblings addObject:sib];
            }
            if (i < ([array count]-1)) {
                NSInteger pid = [array[i+1] integerValue];
                GTWAOFBTreeNode* sib   = [GTWAOFBTreeNode nodeWithPageID:pid parent:parent fromAOF:self.aof];
                [siblings addObject:sib];
            }
        }
    }
    
    if ([siblings count] == 0) {
        return nil;
    } else if ([siblings count] == 1) {
        return siblings[0];
    } else {
        NSInteger lcount    = [siblings[0] count];
        NSInteger rcount    = [siblings[1] count];
        if (lcount > rcount) {
            return siblings[0];
        } else {
            return siblings[1];
        }
    }
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
    int32_t flags  = 0;
    if (root) {
        flags   |= GTWAOFBTreeRoot;
    }
    int16_t ksize       = (int16_t) keySize;
    int16_t vsize       = (int16_t) valSize;

    int64_t bigcount    = NSSwapHostLongLongToBig(count);
    int32_t bigflags   = (uint32_t) NSSwapHostIntToBig((unsigned int) flags);
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
    uint64_t bigts      = NSSwapHostLongLongToBig(ts);
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

- (GTWMutableAOFBTreeNode*) initInternalWithParent:(GTWAOFBTreeNode*)parent isRoot:(BOOL)root keySize:(NSInteger)keySize valueSize:(NSInteger)valSize keys:(NSArray*)keys pageIDs:(NSArray*)objects updateContext:(GTWAOFUpdateContext*) ctx {
    assert([keys count] == ([objects count]-1));
    if (self = [self init]) {
        [self setKeySize:keySize];
        [self setValSize:valSize];
        NSData* data    = [[self class] newInternalDataWithPageSize:[ctx pageSize] root:root keySize:keySize valueSize:valSize keys:keys childrenIDs:objects verbose:NO];
        if (!data)
            return nil;
        GTWAOFPage* p   = [ctx createPageWithData: data];
        self            = [self initWithPage:p parent:parent fromAOF:ctx];
        [ctx registerPageObject:self];
    }
    return self;
}

- (GTWMutableAOFBTreeNode*) initLeafWithParent:(GTWAOFBTreeNode*)parent isRoot:(BOOL)root keySize:(NSInteger)keySize valueSize:(NSInteger)valSize keys:(NSArray*)keys objects:(NSArray*)objects updateContext:(GTWAOFUpdateContext*) ctx {
    NSData* data    = [[self class] newLeafDataWithPageSize:[ctx pageSize] root:root keySize:keySize valueSize:valSize keys:keys objects:objects verbose:NO];
    if (!data)
        return nil;
    GTWAOFPage* p   = [ctx createPageWithData: data];
    self    = [self initWithPage:p parent:parent fromAOF:ctx];
    [ctx registerPageObject:self];
    return self;
}

+ (GTWMutableAOFBTreeNode*) rewriteInternalNode:(GTWAOFBTreeNode*)node replacingChildID:(NSInteger)oldID withNewNode:(GTWAOFBTreeNode*)newNode updateContext:(GTWAOFUpdateContext*) ctx {
    assert(node.type == GTWAOFBTreeInternalNodeType);
    NSMutableArray* keys    = [[node allKeys] mutableCopy];
    NSMutableArray* ids     = [[node childrenPageIDs] mutableCopy];
    NSInteger found         = -1;
    NSInteger count         = [ids count];
    for (NSInteger i = 0; i < count; i++) {
        if ([ids[i] isEqual:@(oldID)]) {
            found   = i;
            break;
        }
    }
    if (found < 0) {
        NSLog(@"Attempt to rewrite node with unrecognized child ID %llu", (unsigned long long)oldID);
        return nil;
    }
    
    ids[found]          = @(newNode.pageID);
    if (found < [keys count]) {
        keys[found] = [newNode maxKey];
    }
    NSData* data    = [[self class] newInternalDataWithPageSize:[ctx pageSize] root:node.isRoot keySize:node.keySize valueSize:node.valSize keys:keys childrenIDs:ids verbose:NO];
    if (!data)
        return nil;
    GTWAOFPage* p   = [ctx createPageWithData:data];
    GTWMutableAOFBTreeNode* n     = [[GTWMutableAOFBTreeNode alloc] initWithPage:p parent:node.parent fromAOF:ctx];
    [ctx registerPageObject:n];
    
//    NSLog(@"REWROTE:\n%@\n%@\n", [node longDescription], [n longDescription]);
    
    return n;
}

+ (GTWMutableAOFBTreeNode*) rewriteInternalNode:(GTWAOFBTreeNode*)node replacingChildren:(NSArray*)oldchildren withNewNode:(GTWAOFBTreeNode*)newNode updateContext:(GTWAOFUpdateContext*) ctx {
    assert(node.type == GTWAOFBTreeInternalNodeType);
    if (!node.isRoot) {
        assert(![node isMinimum]);
    }
    NSMutableArray* keys    = [[node allKeys] mutableCopy];
    NSMutableArray* ids     = [[node childrenPageIDs] mutableCopy];
    NSInteger keycount      = [keys count];
    NSMutableIndexSet* is   = [NSMutableIndexSet indexSet];
    for (GTWAOFBTreeNode* child in oldchildren) {
        NSUInteger i            = [ids indexOfObject:@(child.pageID)];
        if (i == NSNotFound) {
            NSLog(@"Attempt to rewrite node with unrecognized child ID %llu", (unsigned long long)child.pageID);
            return nil;
        }
        [is addIndex:i];
    }
    
    if ([is lastIndex] >= keycount) {
        [keys removeObjectAtIndex:[is firstIndex]];
    } else {
        [keys removeObjectsAtIndexes:is];
    }
    [ids removeObjectsAtIndexes:is];
    
    NSInteger i = [is firstIndex];
    [ids insertObject:@(newNode.pageID) atIndex:[is firstIndex]];
    if (i < (keycount-1)) {
        [keys insertObject:[newNode maxKey] atIndex:i];
    }
    NSData* data    = [[self class] newInternalDataWithPageSize:[ctx pageSize] root:node.isRoot keySize:node.keySize valueSize:node.valSize keys:keys childrenIDs:ids verbose:NO];
    if (!data)
        return nil;
    GTWAOFPage* p   = [ctx createPageWithData:data];
    GTWMutableAOFBTreeNode* n     = [[GTWMutableAOFBTreeNode alloc] initWithPage:p parent:node.parent fromAOF:ctx];
    [ctx registerPageObject:n];
    return n;
}

+ (GTWMutableAOFBTreeNode*) rewriteLeafNode:(GTWAOFBTreeNode*)node addingObject:(NSData*)object forKey:(NSData*)key updateContext:(GTWAOFUpdateContext*) ctx {
    assert(node.type == GTWAOFBTreeLeafNodeType);
    assert(![node isFull]);
    assert([key length] == node.keySize);
    assert([object length] == node.valSize);
    NSMutableArray* keys    = [[node allKeys] mutableCopy];
    NSMutableArray* vals    = [[node allObjects] mutableCopy];
    NSInteger keycount      = [keys count];
    NSUInteger i    = -1;
    for (i = 0; i < keycount; i++) {
        if ([key gtw_compare:keys[i]] == NSOrderedAscending)
            break;
    }
    [keys insertObject:key atIndex:i];
    [vals insertObject:object atIndex:i];
    assert((keycount+1) == [keys count]);
    assert((keycount+1) == [vals count]);
//    NSLog(@"rewriting leaf node with new item. leaf is root: %d", [node isRoot]);
    NSData* data    = [self newLeafDataWithPageSize:[ctx pageSize] root:[node isRoot] keySize:node.keySize valueSize:node.valSize keys:keys objects:vals verbose:NO];
    if (!data) {
        NSLog(@"*** Failed to create new leaf page data");
        return nil;
    }
    GTWAOFPage* p   = [ctx createPageWithData:data];
    GTWMutableAOFBTreeNode* n   = [[GTWMutableAOFBTreeNode alloc] initWithPage:p parent:node.parent fromAOF:ctx];
    [ctx registerPageObject:n];
    return n;
}

+ (GTWMutableAOFBTreeNode*) rewriteLeafNode:(GTWAOFBTreeNode*)node removingObjectForKey:(NSData*)key updateContext:(GTWAOFUpdateContext*) ctx {
    assert(node.type == GTWAOFBTreeLeafNodeType);
    assert(![node isMinimum]);
    NSMutableArray* keys    = [[node allKeys] mutableCopy];
    NSMutableArray* vals    = [[node allObjects] mutableCopy];
    NSInteger found    = -1;
    for (NSUInteger i = 0; i < [keys count]; i++) {
        if ([keys[i] isEqual:key]) {
            found   = i;
            break;
        }
    }
    if (found < 0) {
        NSLog(@"Attempt to rewrite node removing object for key that wasn't found: %@", key);
        return nil;
    }
    [keys removeObjectAtIndex:found];
    [vals removeObjectAtIndex:found];
    //    NSLog(@"rewriting leaf node removing item. leaf is root: %d", [node isRoot]);
    NSData* data    = [self newLeafDataWithPageSize:[ctx pageSize] root:[node isRoot] keySize:node.keySize valueSize:node.valSize keys:keys objects:vals verbose:NO];
    if (!data)
        return nil;
    GTWAOFPage* p   = [ctx createPageWithData:data];
    GTWMutableAOFBTreeNode* n   = [[GTWMutableAOFBTreeNode alloc] initWithPage:p parent:node.parent fromAOF:ctx];
    [ctx registerPageObject:n];
    return n;
}

+ (NSArray*) splitLeafNode:(GTWAOFBTreeNode*)node addingObject:(NSData*)object forKey:(NSData*)key updateContext:(GTWAOFUpdateContext*) ctx {
    assert(node.type == GTWAOFBTreeLeafNodeType);
    NSMutableArray* keys    = [[node allKeys] mutableCopy];
    NSMutableArray* vals    = [[node allObjects] mutableCopy];
    NSUInteger i    = -1;
    for (i = 0; i < [keys count]; i++) {
        if ([key gtw_compare:keys[i]] == NSOrderedAscending)
            break;
    }
    [keys insertObject:key atIndex:i];
    [vals insertObject:object atIndex:i];
    NSInteger count = [keys count];
    NSInteger mid   = count/2;
    NSRange lrange  = NSMakeRange(0, mid);
    NSRange rrange  = NSMakeRange(mid, count-mid);
    
    NSUInteger pageSize = [ctx pageSize];
    NSInteger keySize   = node.keySize;
    NSInteger valSize   = node.valSize;
    
    NSArray* lkeys  = [keys subarrayWithRange:lrange];
    NSArray* rkeys  = [keys subarrayWithRange:rrange];
    
    NSData* ldata   = [self newLeafDataWithPageSize:pageSize root:NO keySize:keySize valueSize:valSize keys:lkeys objects:[vals subarrayWithRange:lrange] verbose:NO];
    NSData* rdata   = [self newLeafDataWithPageSize:pageSize root:NO keySize:keySize valueSize:valSize keys:rkeys objects:[vals subarrayWithRange:rrange] verbose:NO];
    
    if (!(ldata && rdata))
        return nil;
    GTWAOFPage* lpage   = [ctx createPageWithData:ldata];
    GTWAOFPage* rpage   = [ctx createPageWithData:rdata];
    if (!(lpage && rpage))
        return nil;
    
    GTWMutableAOFBTreeNode* lhs = [[GTWMutableAOFBTreeNode alloc] initWithPage:lpage parent:node.parent fromAOF:ctx];
    GTWMutableAOFBTreeNode* rhs = [[GTWMutableAOFBTreeNode alloc] initWithPage:rpage parent:node.parent fromAOF:ctx];
    
    [ctx registerPageObject:lhs];
    [ctx registerPageObject:rhs];
    
    return @[lhs, rhs];
}

+ (NSArray*) splitOrReplaceInternalNode:(GTWAOFBTreeNode*)node replacingChildID:(NSInteger)oldID withNewNodes:(NSArray*)newNodes updateContext:(GTWAOFUpdateContext*) ctx {
    assert(node.type == GTWAOFBTreeInternalNodeType);
//    NSLog(@"splitting internal node");
    NSMutableArray* pair        = [NSMutableArray array];
    NSMutableArray* keys        = [[node allKeys] mutableCopy];
    NSMutableArray* children    = [[node childrenPageIDs] mutableCopy];
    NSUInteger i    = -1;
    for (i = 0; i < [children count]; i++) {
        NSNumber* number    = children[i];
        if ([number integerValue] == oldID)
            break;
    }
    
    GTWAOFBTreeNode* lhs    = newNodes[0];
    GTWAOFBTreeNode* rhs    = newNodes[1];
    
    if (i == ([children count]-1)) {
        // last child
        [children removeLastObject];
        [keys addObject:[lhs maxKey]];
        [children addObject:@(lhs.pageID)];
        [children addObject:@(rhs.pageID)];
    } else {
        [children removeObjectAtIndex:i];
        [keys removeObjectAtIndex:i];
        [keys insertObject:[rhs maxKey] atIndex:i];
        [keys insertObject:[lhs maxKey] atIndex:i];
        [children insertObject:@(rhs.pageID) atIndex:i];
        [children insertObject:@(lhs.pageID) atIndex:i];
    }
    
    if ([keys count] > node.maxInternalPageKeys) {
        NSInteger count = [children count];
        NSInteger mid   = count/2;
        NSRange lrange  = NSMakeRange(0, mid);
        NSRange rrange  = NSMakeRange(mid, count-mid);
        
        NSArray* lkeys      = [keys subarrayWithRange:NSMakeRange(0, mid-1)];
        NSArray* lchildren  = [children subarrayWithRange:lrange];
        NSArray* rkeys      = [keys subarrayWithRange:NSMakeRange(mid, count-mid-1)];
        NSArray* rchildren  = [children subarrayWithRange:rrange];
        
        NSData* ldata   = [self newInternalDataWithPageSize:[ctx pageSize] root:NO keySize:node.keySize valueSize:node.valSize keys:lkeys childrenIDs:lchildren verbose:NO];
        NSData* rdata   = [self newInternalDataWithPageSize:[ctx pageSize] root:NO keySize:node.keySize valueSize:node.valSize keys:rkeys childrenIDs:rchildren verbose:NO];
        if (!(ldata && rdata))
            return nil;
        
        GTWAOFPage* lpage   = [ctx createPageWithData:ldata];
        GTWAOFPage* rpage   = [ctx createPageWithData:rdata];
        if (!(lpage && rpage))
            return nil;
        
        GTWAOFBTreeNode* lnode    = [[GTWMutableAOFBTreeNode alloc] initWithPage:lpage parent:node.parent fromAOF:ctx];
        GTWAOFBTreeNode* rnode    = [[GTWMutableAOFBTreeNode alloc] initWithPage:rpage parent:node.parent fromAOF:ctx];
        [pair addObject:lnode];
        [pair addObject:rnode];
        for (GTWAOFBTreeNode* node in newNodes) {
            if ([lkeys containsObject:node]) {
                node.parent = lnode;
            } else {
                node.parent = rnode;
            }
        }
    } else {
        NSData* data   = [self newInternalDataWithPageSize:[ctx pageSize] root:[node isRoot] keySize:node.keySize valueSize:node.valSize keys:keys childrenIDs:children verbose:NO];
        if (!data)
            return nil;
        
        GTWAOFPage* page   = [ctx createPageWithData:data];
        if (!page)
            return nil;
        
        GTWAOFBTreeNode* newNode    = [[GTWMutableAOFBTreeNode alloc] initWithPage:page parent:node.parent fromAOF:ctx];
        lhs.parent  = newNode;
        rhs.parent  = newNode;
        [pair addObject:newNode];
    }
    
    for (id n in pair) {
        [ctx registerPageObject:n];
    }
    return [pair copy];
}

@end
