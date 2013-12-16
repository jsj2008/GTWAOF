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
#import "GZIP.h"

#define TS_OFFSET   8
#define PREV_OFFSET 16
#define DATA_OFFSET 24
#define GZIP_TERM_LENGTH_THRESHOLD 100
static const BOOL SHOULD_COMPRESS_LONG_DATA   = YES;

typedef NS_ENUM(char, GTWAOFDictionaryTermFlag) {
    GTWAOFDictionaryTermFlagSimple = 0,
    GTWAOFDictionaryTermFlagCompressed
};

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
    NSUInteger pageSize = [_aof pageSize];
    BOOL ok = [_aof updateWithBlock:^BOOL(GTWAOFUpdateContext *ctx) {
        int64_t prev  = self.pageID;
        if ([d count]) {
            while ([d count]) {
                NSData* data    = newDictData(pageSize, d, prev, self.verbose);
                if(!data)
                    return NO;
                page    = [ctx createPageWithData:data];
                prev    = page.pageID;
            }
        } else {
            NSData* empty   = emptyDictData(pageSize, prev, self.verbose);
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
        [self _loadEntries];
    }
    return self;
}

- (void) _loadEntries {
    NSMutableDictionary* dict   = [NSMutableDictionary dictionary];
    NSMutableDictionary* rev    = [NSMutableDictionary dictionary];
    [GTWAOFRawDictionary enumerateDataPairsForPage:_head fromAOF:_aof usingBlock:^(NSData *key, NSRange keyrange, NSData *obj, NSRange objrange, BOOL *stop) {
        NSData* k   = [key subdataWithRange:keyrange];
        NSData* v   = [obj subdataWithRange:objrange];
        [dict setObject:v forKey:k];
        [rev setObject:k forKey:v];
    }];
    _pageDict       = [dict copy];
    _revPageDict    = [rev copy];
}

- (GTWAOFRawDictionary*) initWithPageID:(NSInteger)pageID fromAOF:(id<GTWAOF>)aof {
    if (self = [self init]) {
        _aof    = aof;
        _head   = [aof readPage:pageID];
        [self _loadEntries];
    }
    return self;
}

- (GTWAOFRawDictionary*) initWithPage:(GTWAOFPage*)page fromAOF:(id<GTWAOF>)aof {
    if (self = [self init]) {
        _aof    = aof;
        _head   = page;
        [self _loadEntries];
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
    NSMutableArray* keys   = [[_pageDict allKeys] mutableCopy];
    if (self.previousPageID >= 0) {
        GTWAOFRawDictionary* prev   = [self previousPage];
        NSEnumerator* e = [prev keyEnumerator];
        [keys addObjectsFromArray:[e allObjects]];
    }
    return [keys objectEnumerator];
}

- (id) objectForKey:(id)aKey {
    id o    = [_pageDict objectForKey:aKey];
    if (o) {
        return o;
    } else if (self.previousPageID >= 0) {
        GTWAOFRawDictionary* prev   = [self previousPage];
        return [prev objectForKey:aKey];
    }
    return nil;
}

- (GTWAOFRawDictionary*) previousPage {
    if (!_prevPage) {
        // TODO: this shouldn't be a strong ivar reference; have a global/scoped cache that holds the references
        GTWAOFRawDictionary* prev   = [[GTWAOFRawDictionary alloc] initWithPageID:self.previousPageID fromAOF:_aof];
        _prevPage   = prev;
    }
    return _prevPage;
}

- (NSData*)keyForObject:(NSData*)anObject {
    id o    = [_revPageDict objectForKey:anObject];
    if (o) {
        return o;
    } else if (self.previousPageID >= 0) {
        GTWAOFRawDictionary* prev   = [self previousPage];
        return [prev keyForObject:anObject];
    }
    return nil;
}

+ (void)enumerateDataPairsForPage:(GTWAOFPage*) p fromAOF:(id<GTWAOF>)aof usingBlock:(void (^)(NSData* key, NSRange keyrange, NSData* obj, NSRange objrange, BOOL *stop))block {
//        NSLog(@"Dictionary Page: %lu", d.pageID);
//        NSLog(@"Dictionary Page Last-Modified: %@", [d lastModified]);
    NSData* data    = p.data;
    
    int offset      = DATA_OFFSET;
    uint32_t bigklen, bigvlen;
    
    BOOL stop   = NO;
    
    while (offset < (aof.pageSize-10)) {
        char kflags, vflags;

//        NSLog(@"key offset %llu", (unsigned long long)offset);
        [data getBytes:&kflags range:NSMakeRange(offset, 1)];
//        NSLog(@"ok");
        offset++;
        
//        NSLog(@"key flag: %x", (int) kflags);
        
        [data getBytes:&bigklen range:NSMakeRange(offset, 4)];
        offset  += 4;
        
        uint32_t klen = (uint32_t) NSSwapBigIntToHost(bigklen);
//        NSLog(@"decoding key of length %llu\n", (unsigned long long)klen);
        
        if (!klen)
            break;
//            char* kbuf      = malloc(klen);
//            [data getBytes:kbuf range:NSMakeRange(offset, klen)];
//        NSData* key     = [data subdataWithRange:NSMakeRange(offset, klen)];
        NSData* key         = [data copy];
        NSRange keyrange    = NSMakeRange(offset, klen);
        offset  += klen;
        
        if (kflags & GTWAOFDictionaryTermFlagCompressed) {
            key         = [key subdataWithRange:keyrange];
            key         = [key gunzippedData];
            keyrange    = NSMakeRange(0, [key length]);
        }
        
//            NSData* key     = [NSData dataWithBytesNoCopy:kbuf length:klen];
        
//        NSLog(@"value offset %llu", (unsigned long long)offset);
        [data getBytes:&vflags range:NSMakeRange(offset, 1)];
//        NSLog(@"ok");
        offset++;
        
        [data getBytes:&bigvlen range:NSMakeRange(offset, 4)];
        offset  += 4;
        
        unsigned short vlen = NSSwapBigIntToHost(bigvlen);
//            char* vbuf      = malloc(vlen);
//            [data getBytes:vbuf range:NSMakeRange(offset, vlen)];
//        NSData* value   = [data subdataWithRange:NSMakeRange(offset, vlen)];
        NSData* value       = [data copy];
        NSRange valrange    = NSMakeRange(offset, vlen);
        offset  += vlen;
//            NSData* value   = [NSData dataWithBytesNoCopy:vbuf length:vlen];
        
        block(key, keyrange, value, valrange, &stop);
        if (stop)
            break;
    }
}

- (void)enumerateKeysAndObjectsUsingBlock:(void (^)(id key, id obj, BOOL *stop))block {
    __block BOOL _stop  = NO;
    [_pageDict enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        block(key, obj, &_stop);
        if (_stop)
            *stop   = YES;
    }];
    
    if (!_stop) {
        if (self.previousPageID >= 0) {
            GTWAOFRawDictionary* prev   = [self previousPage];
            [prev enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
                block(key, obj, &_stop);
                if (_stop)
                    *stop   = YES;
            }];
        }
    }
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
//    NSLog(@"attempting to pack %llu keys", (unsigned long long)[keys count]);
    static NSInteger saved = 0;
    for (NSData* k in keys) {
        NSData* key = k;
        id val              = dict[key];
        if (![key isKindOfClass:[NSData class]]) {
            NSLog(@"Attempt to add key that is not a NSData object (%@)", [key class]);
            return nil;
        }
        if (![val isKindOfClass:[NSData class]]) {
            NSLog(@"Attempt to add value that is not a NSData object (%@)", [val class]);
            return nil;
        }
        
        uint32_t klen   = (uint32_t) [key length];
        uint32_t vlen   = (uint32_t) [val length];
        if (SHOULD_COMPRESS_LONG_DATA) {
            if (klen > GZIP_TERM_LENGTH_THRESHOLD) {
                NSData* gzkey   = [key gzippedData];
                klen            = (uint32_t) [gzkey length];
                saved           += ([key length] - [gzkey length]);
    //            NSLog(@"would save %lld bytes in gzipping (%d)", (long long)([key length] - [gzkey length]), GTWAOFDictionaryTermFlagCompressed);
            }
        }
        
        size_t len          = klen + vlen + 5 + 5;
        if (tmp_offset+len < pageSize) {
            tmp_offset  += len;
            [setKeys addObject:key];
            int remaining   = (int) (pageSize-tmp_offset);
            if (verbose)
                NSLog(@"packed size is %d (+%d; %d remaining)", tmp_offset, (int) len, remaining);
            if (remaining < 22) {
                if (verbose)
                    NSLog(@"Not enough remaining room in page (%d)", remaining);
                break;
            }
        } else {
            if (verbose) {
                int remaining   = (int) (pageSize-tmp_offset);
                NSLog(@"skipping item of size %d (too big for packed size %d; %d remaining)", (int) len, tmp_offset, remaining);
            }
        }
    }
    if (SHOULD_COMPRESS_LONG_DATA) {
//        NSLog(@"saved %lld bytes by gzipping", (long long)saved);
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
    for (NSData* k in sortedKeys) {
        NSData* key = k;
        NSData* val = dict[key];
        char kflags = GTWAOFDictionaryTermFlagSimple;
        char vflags = GTWAOFDictionaryTermFlagSimple;
        uint32_t klen   = (uint32_t) [key length];
        uint32_t vlen   = (uint32_t) [val length];
        
        if (SHOULD_COMPRESS_LONG_DATA) {
            if (klen > GZIP_TERM_LENGTH_THRESHOLD) {
                NSData* gzkey       = [key gzippedData];
                if (gzkey) {
                    key     = gzkey;
                    klen    = (uint32_t) [gzkey length];
                    kflags  = GTWAOFDictionaryTermFlagCompressed;
                }
            }
        }
        
//        NSLog(@"encoding key of length %llu\n", (unsigned long long)klen);
        uint32_t bigklen    = NSSwapHostIntToBig(klen);
        uint32_t bigvlen    = NSSwapHostIntToBig(vlen);

        [data replaceBytesInRange:NSMakeRange(offset, 1) withBytes:&kflags];
        offset++;
//        NSLog(@"writing key length %llu at offset %llu", (unsigned long long)klen, (unsigned long long)offset);
        [data replaceBytesInRange:NSMakeRange(offset, 4) withBytes:&bigklen];
        offset  += 4;
        [data replaceBytesInRange:NSMakeRange(offset, klen) withBytes:[key bytes]];
        offset  += klen;
        
        [data replaceBytesInRange:NSMakeRange(offset, 1) withBytes:&vflags];
        offset++;
        [data replaceBytesInRange:NSMakeRange(offset, 4) withBytes:&bigvlen];
        offset  += 4;
        [data replaceBytesInRange:NSMakeRange(offset, vlen) withBytes:[val bytes]];
        offset  += vlen;
        [dict removeObjectForKey:k];
        [setKeys addObject:k];
        [dict removeObjectForKey:k];
    }
    if ([setKeys count] == 0) {
        NSLog(@"dictionary data is too large for database page");
        NSData* maxkey  = nil;
        uint32_t maxlen = 0;
        for (NSData* key in dict) {
            uint32_t klen   = (uint32_t) [key length];
            uint32_t vlen   = (uint32_t) [dict[key] length];
            uint32_t len    = klen + vlen;
            if (maxlen < len) {
                maxlen  = len;
                maxkey  = key;
            }
            // TODO: this isn't a great solution to dealing with data that won't fit into a page
            NSLog(@"*** Removing entry of length (%llu): %@ -> %@", (unsigned long long) maxlen, maxkey, dict[maxkey]);
            [dict removeObjectForKey:maxkey];
        }
        return data;
    }
    if ([data length] != pageSize) {
        NSLog(@"page has bad size (%llu) for keys: %@", (unsigned long long) [data length], setKeys);
        return nil;
    }
    return data;
}

@end
