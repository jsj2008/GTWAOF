//
//  GTWAOFRawDictionary.m
//  GTWAOF
//
//  Created by Gregory Williams on 12/8/13.
//  Copyright (c) 2013 Gregory Todd Williams. All rights reserved.
//

/**
 4  cookie          [RDCT]
 4  padding
 8  timestamp       (seconds since epoch)
 8  prev_page_id
 *  DATA
 */
#import "GTWAOFRawDictionary.h"
#import "GTWAOFUpdateContext.h"

#define TS_OFFSET   8
#define PREV_OFFSET 16
#define DATA_OFFSET 24

@implementation GTWAOFRawDictionary

+ (GTWAOFRawDictionary*) dictionaryWithDictionary:(NSDictionary*) dict aof:(id<GTWAOF>)_aof {
    NSMutableDictionary* d  = [dict mutableCopy];
    __block GTWAOFPage* page;
    BOOL ok = [_aof updateWithBlock:^BOOL(GTWAOFUpdateContext *ctx) {
        int64_t prev  = -1;
        if ([d count]) {
            while ([d count]) {
                NSData* data    = newDictData([_aof pageSize], d, prev, NO);
                if(!data)
                    return NO;
                page    = [ctx createPageWithData:data];
                prev    = page.pageID;
            }
        } else {
            NSData* empty   = emptyDictData([_aof pageSize], prev, NO);
            page            = [ctx createPageWithData:empty];
        }
        return YES;
    }];
    if (!ok)
        return nil;
//    NSLog(@"new dictionary head: %@", page);
    return [[GTWAOFRawDictionary alloc] initWithPage:page fromAOF:_aof];
}

- (GTWAOFRawDictionary*) dictionaryByAddingDictionary:(NSDictionary*) dict {
    NSMutableDictionary* d  = [dict mutableCopy];
    __block GTWAOFPage* page;
    BOOL ok = [_aof updateWithBlock:^BOOL(GTWAOFUpdateContext *ctx) {
        int64_t prev  = self.pageID;
        if ([d count]) {
            while ([d count]) {
                NSData* data    = newDictData([_aof pageSize], d, prev, self.verbose);
                if(!data)
                    return NO;
                page    = [ctx createPageWithData:data];
                prev    = page.pageID;
            }
        } else {
            NSData* empty   = emptyDictData([_aof pageSize], prev, self.verbose);
            page            = [ctx createPageWithData:empty];
        }
        return YES;
    }];
    if (!ok)
        return nil;
    //    NSLog(@"new dictionary head: %@", page);
    return [[GTWAOFRawDictionary alloc] initWithPage:page fromAOF:_aof];
}

- (GTWAOFRawDictionary*) initFindingDictionaryInAOF:(id<GTWAOF>)aof {
    if (self = [self init]) {
        _aof    = aof;
        _head   = nil;
        NSInteger pageID;
        NSInteger pageCount = [aof pageCount];
        for (pageID = pageCount-1; pageID >= 0; pageID--) {
//            NSLog(@"Checking block %lu for dictionary head", pageID);
            GTWAOFPage* p   = [aof readPage:pageID];
            NSData* data    = p.data;
            char cookie[5] = { 0,0,0,0,0 };
            [data getBytes:cookie length:4];
            if (!strncmp(cookie, RAW_DICT_COOKIE, 4)) {
                _head   = p;
                break;
            }
        }
        
        if (!_head) {
            return [GTWAOFRawDictionary dictionaryWithDictionary:@{} aof:aof];
        }
    }
    return self;
}

- (GTWAOFRawDictionary*) initWithPageID:(NSInteger)pageID fromAOF:(id<GTWAOF>)aof {
    if (self = [self init]) {
        _aof    = aof;
        _head   = [aof readPage:pageID];
    }
    return self;
}

- (GTWAOFRawDictionary*) initWithPage:(GTWAOFPage*)page fromAOF:(id<GTWAOF>)aof {
    if (self = [self init]) {
        _aof    = aof;
        _head   = page;
    }
    return self;
}

- (GTWAOFRawDictionary*) init {
    if (self = [super init]) {
        _cache  = [[NSCache alloc] init];
        _revCache   = [[NSCache alloc] init];
        [_cache setCountLimit:1024];
        [_revCache setCountLimit:1024];
    }
    return self;
}

- (NSInteger) pageID {
    return _head.pageID;
}

- (NSInteger) previousPageID {
    GTWAOFPage* p   = _head;
    NSData* data    = p.data;
    uint64_t big_prev = 0;
    [data getBytes:&big_prev range:NSMakeRange(PREV_OFFSET, 8)];
    unsigned long long prev = NSSwapBigLongLongToHost((unsigned long long) big_prev);
    return (NSInteger) prev;
}

- (GTWAOFPage*) head {
    return _head;
}

- (NSDate*) lastModified {
    GTWAOFPage* p   = _head;
    NSData* data    = p.data;
    uint64_t big_ts = 0;
    [data getBytes:&big_ts range:NSMakeRange(TS_OFFSET, 8)];
    unsigned long long ts = NSSwapBigLongLongToHost((unsigned long long) big_ts);
    return [NSDate dateWithTimeIntervalSince1970:(double)ts];
}

- (NSEnumerator*) keyEnumerator {
    NSMutableArray* keys    = [NSMutableArray array];
    [self enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        [keys addObject:key];
    }];
    return [keys objectEnumerator];
}

- (id) objectForKey:(id)aKey {
    __block id value    = [_cache objectForKey:aKey];
    if (value)
        return value;
    
    [self enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
//        NSLog(@"%@ <=> %@", key, aKey);
        if ([key isEqual:aKey]) {
            [_cache setObject:obj forKey:key];
            [_revCache setObject:key forKey:obj];
            value   = obj;
            *stop   = YES;
        }
    }];
    return value;
}

- (NSArray *)allKeysForObject:(id)anObject {
    NSMutableArray* keys    = [NSMutableArray array];
    [self enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        //        NSLog(@"%@ <=> %@", key, aKey);
        if ([obj isEqual:anObject]) {
            [keys addObject:key];
        }
    }];
    return [keys copy];
}

- (NSData*)anyKeyForData:(NSData*)anObject withRange:(NSRange) range {
    __block NSData* theKey;
    const char* anObjectBytes   = &(((const char*) anObject.bytes)[range.location]);
    [self enumerateKeysAndObjectsUsingBlock:^(NSData* key, NSData* obj, BOOL *stop) {
        const char* objBytes        = &(((const char*) obj.bytes)[range.location]);
        if (!memcmp(objBytes, anObjectBytes, range.length)) {
            theKey  = key;
            *stop   = YES;
        }
    }];
    return theKey;
}

- (NSData*)anyKeyForObject:(NSData*)anObject {
    __block NSData* theKey  = [_revCache objectForKey:anObject];
    if (theKey)
        return theKey;
    [self enumerateDataPairsUsingBlock:^(NSData *keydata, NSRange keyrange, NSData *objdata, NSRange objrange, BOOL *stop) {
        const char* objbytes    = &(((const char*)objdata.bytes)[objrange.location]);
        if (!memcmp(objbytes, anObject.bytes, objrange.length)) {
            NSData* key = [keydata subdataWithRange:keyrange];
            theKey  = key;
            *stop   = YES;
        }
    }];
    return theKey;
}

+ (void)enumerateDataPairsForPage:(NSInteger) pageID fromAOF:(id<GTWAOF>)aof usingBlock:(void (^)(NSData* key, NSRange keyrange, NSData* obj, NSRange objrange, BOOL *stop))block {
    while (pageID >= 0) {
        GTWAOFRawDictionary* d  = [[GTWAOFRawDictionary alloc] initWithPageID:pageID fromAOF:aof];
//        NSLog(@"Dictionary Page: %lu", d.pageID);
//        NSLog(@"Dictionary Page Last-Modified: %@", [d lastModified]);
        GTWAOFPage* p   = d.head;
        NSData* data    = p.data;
        int64_t big_prev_page_id    = -1;
        [data getBytes:&big_prev_page_id range:NSMakeRange(PREV_OFFSET, 8)];
        long long prev_page_id = NSSwapBigLongLongToHost(big_prev_page_id);
//        NSLog(@"Dictionary Previous Page: %"PRId64, prev_page_id);
        
        int offset      = DATA_OFFSET;
        uint16_t bigklen, bigvlen;
        
        BOOL stop   = NO;
        
        while (offset < (aof.pageSize-4)) {
            [data getBytes:&bigklen range:NSMakeRange(offset, 2)];
            offset  += 2;
            
            unsigned short klen = NSSwapBigShortToHost(bigklen);
            if (!klen)
                break;
//            char* kbuf      = malloc(klen);
//            [data getBytes:kbuf range:NSMakeRange(offset, klen)];
            NSData* key     = [data subdataWithRange:NSMakeRange(offset, klen)];
            offset  += klen;
//            NSData* key     = [NSData dataWithBytesNoCopy:kbuf length:klen];
            
            [data getBytes:&bigvlen range:NSMakeRange(offset, 2)];
            offset  += 2;
            
            unsigned short vlen = NSSwapBigShortToHost(bigvlen);
//            char* vbuf      = malloc(vlen);
//            [data getBytes:vbuf range:NSMakeRange(offset, vlen)];
            NSData* value   = [data subdataWithRange:NSMakeRange(offset, vlen)];
            offset  += vlen;
//            NSData* value   = [NSData dataWithBytesNoCopy:vbuf length:vlen];
            
            NSRange keyrange    = NSMakeRange(0, key.length);
            NSRange valrange    = NSMakeRange(0, value.length);
            block(key, keyrange, value, valrange, &stop);
            if (stop)
                break;
        }
        pageID  = prev_page_id;
    }
}

- (void)enumerateDataPairsUsingBlock:(void (^)(NSData *keydata, NSRange keyrange, NSData *objdata, NSRange objrange, BOOL *stop))block {
    [GTWAOFRawDictionary enumerateDataPairsForPage:self.pageID fromAOF:_aof usingBlock:block];
}

- (void)enumerateKeysAndObjectsUsingBlock:(void (^)(id key, id obj, BOOL *stop))block {
    [GTWAOFRawDictionary enumerateDataPairsForPage:self.pageID fromAOF:_aof usingBlock:^(NSData *keydata, NSRange keyrange, NSData *objdata, NSRange objrange, BOOL *stop) {
        NSData* k   = [keydata subdataWithRange:keyrange];
        NSData* v   = [objdata subdataWithRange:objrange];
        block(k, v, stop);
    }];
}

NSMutableData* emptyDictData( NSUInteger pageSize, int64_t prevPageID, BOOL verbose ) {
    uint64_t ts     = (uint64_t) [[NSDate date] timeIntervalSince1970];
    int64_t prev    = (int64_t) prevPageID;
    if (verbose)
        NSLog(@"creating dictionary page data with previous page ID: %lld (%lld)", prevPageID, prev);
    uint64_t bigts  = NSSwapHostLongLongToBig(ts);
    int64_t bigprev = NSSwapHostLongLongToBig(prev);
    
    NSMutableData* data = [NSMutableData dataWithLength:pageSize];
    [data replaceBytesInRange:NSMakeRange(0, 4) withBytes:RAW_DICT_COOKIE];
    [data replaceBytesInRange:NSMakeRange(8, 8) withBytes:&bigts];
    [data replaceBytesInRange:NSMakeRange(16, 8) withBytes:&bigprev];
    return data;
}

NSData* newDictData( NSUInteger pageSize, NSMutableDictionary* dict, int64_t prevPageID, BOOL verbose ) {
    NSMutableData* data = emptyDictData(pageSize, prevPageID, verbose);
    __block int offset  = DATA_OFFSET;
    NSArray* keys   = [[dict keyEnumerator] allObjects];
    NSMutableSet* setKeys   = [NSMutableSet set];
    int tmp_offset  = offset;
    for (id key in keys) {
        id val              = dict[key];
        if (![key isKindOfClass:[NSData class]]) {
            NSLog(@"Attempt to add key that is not a NSData object (%@)", [key class]);
            return nil;
        }
        if (![val isKindOfClass:[NSData class]]) {
            NSLog(@"Attempt to add value that is not a NSData object (%@)", [val class]);
            return nil;
        }
        
        short klen          = [key length];
        short vlen          = [val length];
        size_t len          = klen + vlen + 2 + 2;
        if (tmp_offset+len < pageSize) {
            tmp_offset  += len;
            [setKeys addObject:key];
            int remaining   = (int) (pageSize-tmp_offset);
            if (verbose)
                NSLog(@"packed size is %d (+%d; %d remaining)", tmp_offset, (int) len, remaining);
            if (remaining < 16) {
                if (verbose)
                    NSLog(@"Not enough remaining room in page (%d)", remaining);
                break;
            }
        } else {
            if (verbose)
                NSLog(@"skipping item of size %d (too big for packed size %d)", (int) len, tmp_offset);
        }
    }
    
    NSArray* sortedKeys   = [[setKeys allObjects] sortedArrayUsingComparator:^NSComparisonResult(id obj1, id obj2) {
        int r   = memcmp([obj1 bytes], [obj2 bytes], 32);
        if (r < 0) {
            return NSOrderedAscending;
        } else if (r > 0) {
            return NSOrderedDescending;
        } else {
            return NSOrderedSame;
        }
    }];
    
    
    
//    NSArray* sortedKeys = [[setKeys allObjects] sortedArrayUsingSelector:@selector(compare:)];
    for (id key in sortedKeys) {
        NSData* val         = dict[key];
        short klen          = [key length];
        short vlen          = [val length];
        uint16_t bigklen    = NSSwapHostShortToBig(klen);
        uint16_t bigvlen    = NSSwapHostShortToBig(vlen);
        [data replaceBytesInRange:NSMakeRange(offset, 2) withBytes:&bigklen];
        offset  += 2;
        [data replaceBytesInRange:NSMakeRange(offset, klen) withBytes:[key bytes]];
        offset  += klen;
        
        [data replaceBytesInRange:NSMakeRange(offset, 2) withBytes:&bigvlen];
        offset  += 2;
        [data replaceBytesInRange:NSMakeRange(offset, vlen) withBytes:[val bytes]];
        offset  += vlen;
        [dict removeObjectForKey:key];
        [setKeys addObject:key];
        [dict removeObjectForKey:key];
    }
    if ([setKeys count] == 0) {
        NSLog(@"dictionary data is too large for database page");
        return nil;
    }
    if ([data length] != pageSize) {
        NSLog(@"page has bad size for keys: %@", setKeys);
        return nil;
    }
    return data;
}

@end
