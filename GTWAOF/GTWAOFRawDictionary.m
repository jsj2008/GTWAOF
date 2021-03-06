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
#import "GTWAOFRawValue.h"
#import "GZIP.h"
#import "GTWAOFPage+GTWAOFLinkedPage.h"
#import "NSData+GTWCompare.h"

#define TS_OFFSET       8
#define PREV_OFFSET     16
#define COUNT_OFFSET    24
#define DATA_OFFSET     32
#define GZIP_TERM_LENGTH_THRESHOLD 100
static const BOOL SHOULD_COMPRESS_LONG_DATA   = YES;

typedef NS_ENUM(char, GTWAOFDictionaryTermFlag) {
    GTWAOFDictionaryTermFlagSimple = 0,
    GTWAOFDictionaryTermFlagCompressed,
    GTWAOFDictionaryTermFlagExtendedPagePair,
};

@implementation GTWAOFRawDictionary

- (GTWAOFRawDictionary*) initFindingDictionaryInAOF:(id<GTWAOF,GTWMutableAOF>)aof {
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
            NSLog(@"Failed to find a RawDictionary page in AOF file");
            return nil;
//            return [GTWAOFRawDictionary dictionaryWithDictionary:@{} aof:aof];
        }
        [self _loadEntries];
        
        if (![[_head cookie] isEqual:[NSData dataWithBytes:RAW_DICT_COOKIE length:4]]) {
            NSLog(@"Bad cookie for raw quads");
            return nil;
        }
        [aof setObject:self forPage:_head.pageID];
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

+ (GTWAOFRawDictionary*) rawDictionaryWithPageID:(NSInteger)pageID fromAOF:(id<GTWAOF,GTWMutableAOF>)aof {
    GTWAOFRawDictionary* d   = [aof cachedObjectForPage:pageID];
    if (d) {
        if (![d isKindOfClass:self]) {
            NSLog(@"Cached object is of unexpected type for page %lld", (long long)pageID);
            return nil;
        }
        return d;
    }
    return [[GTWAOFRawDictionary alloc] initWithPageID:pageID fromAOF:aof];
}

- (GTWAOFRawDictionary*) initWithPageID:(NSInteger)pageID fromAOF:(id<GTWAOF,GTWMutableAOF>)aof {
    GTWAOFRawDictionary* d   = [aof cachedObjectForPage:pageID];
    if (d) {
        if (![d isKindOfClass:[self class]]) {
            NSLog(@"Cached object is of unexpected type for page %lld", (long long)pageID);
            return nil;
        }
//        NSLog(@"cached raw dictionary for page %lld", (long long)pageID);
        return d;
//    } else {
//        NSLog(@"NO cached raw dictionary for page %lld", (long long)pageID);
    }
    if (self = [self init]) {
        _aof    = aof;
        _head   = [aof readPage:pageID];
        [self _loadEntries];
        
        if (![[_head cookie] isEqual:[NSData dataWithBytes:RAW_DICT_COOKIE length:4]]) {
            NSLog(@"Bad cookie for raw quads");
            return nil;
        }
        [aof setObject:self forPage:_head.pageID];
    }
    return self;
}

- (GTWAOFRawDictionary*) initWithPage:(GTWAOFPage*)page fromAOF:(id<GTWAOF,GTWMutableAOF>)aof {
    if (self = [self init]) {
        _aof    = aof;
        _head   = page;
        [self _loadEntries];
        
        if (![[_head cookie] isEqual:[NSData dataWithBytes:RAW_DICT_COOKIE length:4]]) {
            NSLog(@"Bad cookie for raw quads");
            return nil;
        }
        [aof setObject:self forPage:_head.pageID];
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

- (NSString*) pageType {
    return @(RAW_DICT_COOKIE);
}

- (NSInteger) pageID {
    return _head.pageID;
}

- (NSInteger) previousPageID {
    GTWAOFPage* p   = _head;
    NSUInteger prev = [p.data gtw_integerFromBigLongLongRange:NSMakeRange(PREV_OFFSET, 8)];
    return (NSInteger)prev;
}

- (GTWAOFPage*) head {
    return _head;
}

- (NSDate*) lastModified {
    GTWAOFPage* p   = _head;
    NSUInteger ts = [p.data gtw_integerFromBigLongLongRange:NSMakeRange(TS_OFFSET, 8)];
    return [NSDate dateWithTimeIntervalSince1970:(double)ts];
}

- (NSUInteger) count {
    GTWAOFPage* p       = _head;
    NSUInteger count = [p.data gtw_integerFromBigLongLongRange:NSMakeRange(COUNT_OFFSET, 8)];
    return count;
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

- (NSData*) objectForKey:(id)aKey {
    id o    = [_pageDict objectForKey:aKey];
    if (o) {
        return o;
    } else if (self.previousPageID >= 0) {
        GTWAOFRawDictionary* prev   = [self previousPage];
        return [prev objectForKey:aKey];
    }
    return nil;
}

- (GTWAOFPage*) pageForKey:(id)aKey {
    id o    = [_pageDict objectForKey:aKey];
    if (o) {
        return _head;
    } else if (self.previousPageID >= 0) {
        GTWAOFRawDictionary* prev   = [self previousPage];
        return [prev pageForKey:aKey];
    }
    return nil;
}

- (GTWAOFRawDictionary*) previousPage {
    if (self.previousPageID >= 0) {
        return [GTWAOFRawDictionary rawDictionaryWithPageID:self.previousPageID fromAOF:_aof];
    } else {
        return nil;
    }
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

+ (NSUInteger) decodeDataPair:(NSData*)pair location:(NSUInteger)location usingBlock:(void (^)(NSData* key, NSRange keyrange, NSData* obj, NSRange objrange, BOOL *stop))block{
    int offset      = (int) location;
    NSData* data    = pair;
    uint32_t bigklen, bigvlen;
    char kflags, vflags;
    
    [data getBytes:&kflags range:NSMakeRange(offset, 1)];
    //        NSLog(@"ok");
    offset++;
    
    [data getBytes:&bigklen range:NSMakeRange(offset, 4)];
    offset  += 4;
    uint32_t klen = (uint32_t) NSSwapBigIntToHost(bigklen);
    //        NSLog(@"decoding key of length %llu\n", (unsigned long long)klen);
    
    if (!klen)
        return 0;
//    NSLog(@"key flag: %x", (int) kflags);
    
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
    
    BOOL stop   = NO;
    block(key, keyrange, value, valrange, &stop);
    if (stop)
        return 0;
    return (offset - location);
}

+ (void)enumerateDataPairsForPage:(GTWAOFPage*) p fromAOF:(id<GTWAOF>)aof usingBlock:(void (^)(NSData* key, NSRange keyrange, NSData* obj, NSRange objrange, BOOL *stop))block {
//    NSLog(@"Dictionary Page: %lu", p.pageID);
    NSData* data    = p.data;
    
    int offset      = DATA_OFFSET;
    while (offset < (aof.pageSize-10)) {
        char kflags;

//        NSLog(@"key offset %llu", (unsigned long long)offset);
        [data getBytes:&kflags range:NSMakeRange(offset, 1)];
//        NSLog(@"ok");
        
        if (kflags & GTWAOFDictionaryTermFlagExtendedPagePair) {
            offset++;       // skip past the kflags byte
            uint32_t bigklen;
            [data getBytes:&bigklen range:NSMakeRange(offset, 4)];
            offset  += 4;   // skip past the klen int
            uint32_t klen = (uint32_t) NSSwapBigIntToHost(bigklen);
//            NSLog(@"decoding key of length %llu\n", (unsigned long long)klen);
            
            if (!klen)
                break;
            
            if (klen != 8) {
                NSLog(@"Unexpected page ID length (%"PRIu32") when looking for extended page", klen);
                break;
            }
            unsigned long long pageID   = (unsigned long long) [data gtw_integerFromBigLongLongRange:NSMakeRange(offset, klen)];
            
//            NSLog(@"found extended page dictionary pair (on page %llu)", (unsigned long long)pageID);
            GTWAOFRawValue* v   = [GTWAOFRawValue rawValueWithPageID:pageID fromAOF:aof];
            NSData* pair        = [v data];
            NSUInteger read     = [self decodeDataPair:pair location:0 usingBlock:block];
//            NSLog(@"read %llu bytes from extended page(s)", (unsigned long long) read);
            if (read == 0)
                break;
            
        } else {
            NSUInteger read     = [self decodeDataPair:data location:offset usingBlock:block];
//            NSLog(@"read %llu bytes from dictionary page", (unsigned long long) read);
            if (read == 0)
                break;
            offset              += read;
        }
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
//    int64_t prev    = (int64_t) prevPageID;
    if (verbose)
        NSLog(@"creating dictionary page data with previous page ID: %lld (%lld)", prevPageID, prevPageID);
    
    NSData* timestamp   = [NSData gtw_bigLongLongDataWithInteger:ts];
    NSData* previous    = [NSData gtw_bigLongLongDataWithInteger:prevPageID];
    NSData* count       = [NSData gtw_bigLongLongDataWithInteger:0];
    
    NSMutableData* data = [NSMutableData dataWithLength:pageSize];
    [data replaceBytesInRange:NSMakeRange(0, 4) withBytes:RAW_DICT_COOKIE];
    [data replaceBytesInRange:NSMakeRange(TS_OFFSET, 8) withBytes:timestamp.bytes];
    [data replaceBytesInRange:NSMakeRange(PREV_OFFSET, 8) withBytes:previous.bytes];
    [data replaceBytesInRange:NSMakeRange(COUNT_OFFSET, 8) withBytes:count.bytes];
    return data;
}

static NSData* packedDataForPair( NSData* key, char kflags, NSData* val, char vflags ) {
    NSMutableData* data = [NSMutableData data];
    uint32_t klen       = (uint32_t) [key length];
    uint32_t vlen       = (uint32_t) [val length];
    uint32_t bigklen    = NSSwapHostIntToBig(klen);
    uint32_t bigvlen    = NSSwapHostIntToBig(vlen);
    
    [data appendBytes:&kflags length:1];
    [data appendBytes:&bigklen length:4];
    [data appendBytes:[key bytes] length:klen];
    
    [data appendBytes:&vflags length:1];
    [data appendBytes:&bigvlen length:4];
    [data appendBytes:[val bytes] length:vlen];
    
    return data;
}

static NSData* packedDataForExtendedPagePair( GTWAOFPage* p ) {
    NSMutableData* data = [NSMutableData data];
    uint32_t klen       = 8;
    uint32_t bigklen    = NSSwapHostIntToBig(klen);
    int64_t pageID      = (int64_t) p.pageID;
    char kflags         = GTWAOFDictionaryTermFlagExtendedPagePair;
    
    NSData* pid         = [NSData gtw_bigLongLongDataWithInteger:pageID];
    
    [data appendBytes:&kflags length:1];
    [data appendBytes:&bigklen length:4];
    [data appendBytes:pid.bytes length:8];
    
    return data;
}

NSData* newDictData( GTWAOFUpdateContext* ctx, NSMutableDictionary* dict, int64_t prevPageID, NSMutableSet* consumedKeys, BOOL verbose ) {
    NSUInteger pageSize = [ctx pageSize];
    NSMutableData* data = emptyDictData(pageSize, prevPageID, verbose);
    NSArray* keys       = [[dict keyEnumerator] allObjects];
//    NSLog(@"attempting to pack %llu keys", (unsigned long long)[keys count]);
    static NSInteger saved = 0;
    
    if ([keys count] == 0) {
        return data;
    }
    
    NSMutableDictionary* packedData = [NSMutableDictionary dictionary];
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
        
        char kflags = GTWAOFDictionaryTermFlagSimple;
        char vflags = GTWAOFDictionaryTermFlagSimple;
        
        uint32_t klen   = (uint32_t) [key length];
//        uint32_t vlen   = (uint32_t) [val length];

        if (SHOULD_COMPRESS_LONG_DATA) {
            if (klen > GZIP_TERM_LENGTH_THRESHOLD) {
                NSData* gzkey   = [key gzippedData];
                klen            = (uint32_t) [gzkey length];
                saved           += ([key length] - [gzkey length]);
                key             = gzkey;
                klen            = (uint32_t) [gzkey length];
                kflags          |= GTWAOFDictionaryTermFlagCompressed;
                //            NSLog(@"would save %lld bytes in gzipping (%d)", (long long)([key length] - [gzkey length]), GTWAOFDictionaryTermFlagCompressed);
            }
        }
        
        NSData* packed  = packedDataForPair(key, kflags, val, vflags);
        if ([packed length] > ([ctx pageSize] - DATA_OFFSET)) {
            GTWAOFPage* p   = [GTWMutableAOFRawValue valuePageWithData:packed updateContext:ctx];
            packed          = packedDataForExtendedPagePair(p);
        }
        
        [packedData setObject:packed forKey:k];
    }
    
//    NSLog(@"packed data pairs: %@", packedData);

    if (verbose && SHOULD_COMPRESS_LONG_DATA) {
        NSLog(@"saved %lld bytes by gzipping", (long long)saved);
    }
    
    int64_t count   = 0;
    NSMutableSet* handled   = [NSMutableSet set];
    NSUInteger offset       = DATA_OFFSET;
    for (NSData* key in packedData) {
        NSData* packed  = packedData[key];
        count++;
        NSUInteger length = [packed length];
        if ((offset + length) > pageSize) {
            break;
        }
        
        if (consumedKeys) {
            [consumedKeys addObject:key];
        }
        
//        NSLog(@"{ %llu, %llu } %@", (unsigned long long)offset, (unsigned long long)length, packed);
        [data replaceBytesInRange:NSMakeRange(offset, length) withBytes:[packed bytes]];
        offset  += length;
        [handled addObject:packed];
        [dict removeObjectForKey:key];
    }
    
    NSData* countdata   = [NSData gtw_bigLongLongDataWithInteger:count];
    [data replaceBytesInRange:NSMakeRange(COUNT_OFFSET, 8) withBytes:countdata.bytes];
    
    if ([data length] != pageSize) {
        NSLog(@"page has bad size (%llu) for keys: %@", (unsigned long long) [data length], handled);
        return nil;
    }
    return data;
}

- (GTWMutableAOFRawDictionary*) rewriteWithPageMap:(NSMutableDictionary*)map updateContext:(GTWAOFUpdateContext*) ctx {
    // TODO: rewriting should not be changing the timestamp. figure out a way to preserve it.
    NSInteger prevID            = -1;
    GTWAOFRawDictionary* prev   = [self previousPage];
    if (prev) {
        GTWMutableAOFRawDictionary* newprev    = [prev rewriteWithPageMap:map updateContext:ctx];
        prevID  = newprev.pageID;
        GTWMutableAOFRawDictionary* newdict    = [newprev dictionaryByAddingDictionary:_pageDict updateContext:ctx];
        if (map) {
            map[@(self.pageID)] = @(newdict.pageID);
        }
        return newdict;
    } else {
        GTWMutableAOFRawDictionary* newdict     = [GTWMutableAOFRawDictionary mutableDictionaryWithDictionary:_pageDict updateContext:ctx];
        if (map) {
            map[@(self.pageID)] = @(newdict.pageID);
        }
        return newdict;
    }
}

- (GTWMutableAOFRawDictionary*) rewriteWithUpdateContext:(GTWAOFUpdateContext*) ctx {
    return [self rewriteWithPageMap:nil updateContext:ctx];
}

@end


@implementation GTWMutableAOFRawDictionary

+ (GTWAOFPage*) dictionaryPageWithDictionary:(NSDictionary*)dict updateContext:(GTWAOFUpdateContext*) ctx {
    NSMutableDictionary* d  = [dict mutableCopy];
    GTWAOFPage* page;
    
    int64_t prev  = -1;
    if ([d count]) {
        while ([d count]) {
            NSData* data    = newDictData(ctx, d, prev, nil, NO);
            if(!data)
                return NO;
            page    = [ctx createPageWithData:data];
            prev    = page.pageID;
        }
    } else {
        NSData* empty   = emptyDictData([ctx pageSize], prev, NO);
        page            = [ctx createPageWithData:empty];
    }
    
    return page;
}

+ (instancetype) mutableDictionaryWithDictionary:(NSDictionary*) dict updateContext:(GTWAOFUpdateContext*) ctx; {
    GTWAOFPage* page    = [GTWMutableAOFRawDictionary dictionaryPageWithDictionary:dict updateContext:ctx];
    //    NSLog(@"new dictionary head: %@", page);
    GTWMutableAOFRawDictionary* n   = [[GTWMutableAOFRawDictionary alloc] initWithPage:page fromAOF:ctx];
    [ctx registerPageObject:n];
    return n;
}

- (instancetype) dictionaryByAddingDictionary:(NSDictionary*)dict settingPageIDs:(NSMutableDictionary*)pageDict updateContext:(GTWAOFUpdateContext*)ctx {
    NSMutableDictionary* d  = [dict mutableCopy];
    int64_t prev  = self.pageID;
    GTWAOFPage* page;
    if ([d count]) {
        while ([d count]) {
            NSUInteger lastCount    = [d count];
            NSMutableSet* consumedKeys  = [NSMutableSet set];
            NSData* data    = newDictData(ctx, d, prev, consumedKeys, self.verbose);
            if (lastCount == [d count]) {
                NSLog(@"Failed to encode any dictionary terms in page creation loop");
                return NO;
            }
            if(!data)
                return NO;
            page    = [ctx createPageWithData:data];
            prev    = page.pageID;
            for (NSData* key in consumedKeys) {
                pageDict[key]   = @(page.pageID);
            }
        }
    } else {
        NSData* empty   = emptyDictData(ctx.pageSize, prev, self.verbose);
        page            = [ctx createPageWithData:empty];
    }
    GTWMutableAOFRawDictionary* n   = [[GTWMutableAOFRawDictionary alloc] initWithPage:page fromAOF:ctx];
    [ctx registerPageObject:n];
    return n;
}

- (instancetype) dictionaryByAddingDictionary:(NSDictionary*) dict updateContext:(GTWAOFUpdateContext*)ctx {
    return [self dictionaryByAddingDictionary:dict settingPageIDs:nil updateContext:ctx];
}

- (instancetype) dictionaryByAddingDictionary:(NSDictionary*) dict {
    __block GTWMutableAOFRawDictionary* newDict;
    [self.aof updateWithBlock:^BOOL(GTWAOFUpdateContext *ctx) {
        newDict = [self dictionaryByAddingDictionary:dict updateContext:ctx];
        return YES;
    }];
    return newDict;
}

- (GTWMutableAOFRawDictionary*) initFindingDictionaryInAOF:(id<GTWAOF,GTWMutableAOF>)aof {
    if (self = [self init]) {
        self.aof    = aof;
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
//            NSLog(@"Failed to find a RawDictionary page in AOF file; creating an empty one");
            __block GTWMutableAOFRawDictionary* dict;
            [aof updateWithBlock:^BOOL(GTWAOFUpdateContext *ctx) {
                dict    = [GTWMutableAOFRawDictionary mutableDictionaryWithDictionary:@{} updateContext:ctx];
                return YES;
            }];
            return dict;
        }
        [self _loadEntries];
    }
    return self;
}

@end
