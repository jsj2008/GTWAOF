//
//  GTWAOFRawValue.m
//  GTWAOF
//
//  Created by Gregory Williams on 12/16/13.
//  Copyright (c) 2013 Gregory Todd Williams. All rights reserved.
//

/**
 4  cookie              [RVAL]
 4  padding
 8  timestamp           (seconds since epoch)
 8  prev_page_id
 8	(vl) value length	(the number of quads in this page, stored as a big-endian integer)
 vl	value bytes
 */
#import "GTWAOFRawValue.h"
#import "GTWAOFUpdateContext.h"
#import "GTWAOFPage+GTWAOFLinkedPage.h"
#import "NSData+GTWCompare.h"

#define TS_OFFSET       8
#define PREV_OFFSET     16
#define LENGTH_OFFSET   24
#define DATA_OFFSET     32

@implementation GTWAOFRawValue

- (void) _loadData {
    NSMutableData* data = [NSMutableData data];
    if ([self previousPageID] >= 0) {
        GTWAOFRawValue* prev    = [self previousPage];
        [data appendData: [prev data]];
    }
    
    GTWAOFPage* p   = _head;
    unsigned long long length   = [p.data gtw_integerFromBigLongLongRange:NSMakeRange(LENGTH_OFFSET, 8)];
    NSData* pageData    = [p.data subdataWithRange: NSMakeRange(DATA_OFFSET, length)];
    [data appendData: pageData];
    self.data   = [data copy];
}

+ (GTWAOFRawValue*) rawValueWithPageID:(NSInteger)pageID fromAOF:(id<GTWAOF>)aof {
    GTWAOFRawValue* d   = [aof cachedObjectForPage:pageID];
    if (d) {
        if (![d isKindOfClass:self]) {
            NSLog(@"Cached object is of unexpected type for page %lld", (long long)pageID);
            return nil;
        }
        return d;
    }
    return [[GTWAOFRawValue alloc] initWithPageID:pageID fromAOF:aof];
}

- (GTWAOFRawValue*) initWithPageID:(NSInteger)pageID fromAOF:(id<GTWAOF>)aof {
    if (self = [self init]) {
        _aof    = aof;
        _head   = [aof readPage:pageID];
        [self _loadData];
        
        if (![[_head cookie] isEqual:[NSData dataWithBytes:RAW_VALUE_COOKIE length:4]]) {
            NSLog(@"Bad cookie for raw quads");
            return nil;
        }
        [aof setObject:self forPage:_head.pageID];
    }
    return self;
}

- (GTWAOFRawValue*) initWithPage:(GTWAOFPage*)page fromAOF:(id<GTWAOF,GTWMutableAOF>)aof {
    if (self = [self init]) {
        _aof    = aof;
        _head   = page;
        [self _loadData];
        
        if (![[_head cookie] isEqual:[NSData dataWithBytes:RAW_VALUE_COOKIE length:4]]) {
            NSLog(@"Bad cookie for raw quads");
            return nil;
        }
        [aof setObject:self forPage:_head.pageID];
    }
    return self;
}

- (NSString*) pageType {
    return @(RAW_VALUE_COOKIE);
}

- (NSInteger) pageID {
    return _head.pageID;
}

- (NSInteger) previousPageID {
    GTWAOFPage* p   = _head;
    NSUInteger prev   = [p.data gtw_integerFromBigLongLongRange:NSMakeRange(PREV_OFFSET, 8)];
    return (NSInteger) prev;
}

- (GTWAOFRawValue*) previousPage {
    GTWAOFRawValue* prev   = [GTWAOFRawValue rawValueWithPageID:self.previousPageID fromAOF:_aof];
    return prev;
}

- (GTWAOFPage*) head {
    return _head;
}

- (NSDate*) lastModified {
    GTWAOFPage* p   = _head;
    NSUInteger ts   = [p.data gtw_integerFromBigLongLongRange:NSMakeRange(TS_OFFSET, 8)];
    return [NSDate dateWithTimeIntervalSince1970:(double)ts];
}

- (NSUInteger) length {
    return [self.data length];
}

- (NSUInteger) pageLength {
    GTWAOFPage* p   = _head;
    NSUInteger length   = [p.data gtw_integerFromBigLongLongRange:NSMakeRange(LENGTH_OFFSET, 8)];
    return length;
}

NSMutableData* emptyValueData( NSUInteger pageSize, int64_t prevPageID, BOOL verbose ) {
    uint64_t ts     = (uint64_t) [[NSDate date] timeIntervalSince1970];
    int64_t prev    = (int64_t) prevPageID;
    if (verbose) {
        NSLog(@"creating quads page data with previous page ID: %lld (%lld)", prevPageID, prev);
    }
    uint64_t bigts  = NSSwapHostLongLongToBig(ts);
    int64_t bigprev = NSSwapHostLongLongToBig(prev);
    
    int64_t biglength    = 0;
    
    NSMutableData* data = [NSMutableData dataWithLength:pageSize];
    [data replaceBytesInRange:NSMakeRange(0, 4) withBytes:RAW_VALUE_COOKIE];
    [data replaceBytesInRange:NSMakeRange(TS_OFFSET, 8) withBytes:&bigts];
    [data replaceBytesInRange:NSMakeRange(PREV_OFFSET, 8) withBytes:&bigprev];
    [data replaceBytesInRange:NSMakeRange(LENGTH_OFFSET, 8) withBytes:&biglength];
    return data;
}

NSData* newValueData( NSUInteger pageSize, NSMutableData* value, int64_t prevPageID, BOOL verbose ) {
    int64_t max     = pageSize - DATA_OFFSET;
    int64_t vlength = [value length];
    int64_t length  = (max < vlength) ? max : vlength;
    int64_t biglength    = NSSwapHostLongLongToBig(length);
    
    NSMutableData* data = emptyValueData(pageSize, prevPageID, verbose);
    [data replaceBytesInRange:NSMakeRange(LENGTH_OFFSET, 8) withBytes:&biglength];
    __block int offset  = DATA_OFFSET;
//    NSUInteger i;
    
    const char* bytes   = [value bytes];
    [data replaceBytesInRange:NSMakeRange(offset, length) withBytes:bytes];
    NSData* tail    = [value subdataWithRange:NSMakeRange(length, [value length]-length)];
    [value setData:tail];
//    NSLog(@"New length of value data is %llu", (unsigned long long) [value length]);
    if ([data length] != pageSize) {
        NSLog(@"page has bad size for value");
        return nil;
    }
    return data;
}

- (GTWMutableAOFRawValue*) rewriteWithUpdateContext:(GTWAOFUpdateContext*) ctx {
    // TODO: rewriting should not be changing the timestamp. figure out a way to preserve it.
    return [GTWMutableAOFRawValue valueWithData:self.data updateContext:ctx];
}

@end

@implementation GTWMutableAOFRawValue

+ (GTWAOFPage*) valuePageWithData:(NSData*)data updateContext:(GTWAOFUpdateContext*) ctx {
    NSMutableData* d   = [data mutableCopy];
    int64_t prev  = -1;
    
    GTWAOFPage* page;
    if ([d length]) {
        while ([d length]) {
            NSData* pageData    = newValueData([ctx pageSize], d, prev, NO);
            if(!pageData)
                return NO;
            page    = [ctx createPageWithData:pageData];
            prev    = page.pageID;
        }
    } else {
        NSData* empty   = emptyValueData([ctx pageSize], prev, NO);
        page            = [ctx createPageWithData:empty];
    }
    return page;
}

+ (GTWMutableAOFRawValue*) valueWithData:(NSData*) data updateContext:(GTWAOFUpdateContext*) ctx {
    GTWAOFPage* page    = [GTWMutableAOFRawValue valuePageWithData:data updateContext:ctx];
    //    NSLog(@"new quads head: %@", page);
    GTWMutableAOFRawValue* n    = [[GTWMutableAOFRawValue alloc] initWithPage:page fromAOF:ctx];
    [ctx registerPageObject:n];
    return n;
}

@end
