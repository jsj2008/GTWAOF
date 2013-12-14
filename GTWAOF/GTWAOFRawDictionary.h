//
//  GTWAOFRawDictionary.h
//  GTWAOF
//
//  Created by Gregory Williams on 12/8/13.
//  Copyright (c) 2013 Gregory Todd Williams. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "GTWAOF.h"
#import "GTWAOFPage.h"

#define RAW_DICT_COOKIE "RDCT"

@interface GTWAOFRawDictionary : NSObject {
    id<GTWAOF> _aof;
    GTWAOFPage* _head;
    NSCache* _cache;
    NSCache* _revCache;
}

@property BOOL verbose;

+ (GTWAOFRawDictionary*) dictionaryWithDictionary:(NSDictionary*) dict aof:(id<GTWAOF>)aof;
- (GTWAOFRawDictionary*) dictionaryByAddingDictionary:(NSDictionary*) dict;

- (NSDate*) lastModified;
- (NSInteger) pageID;
- (NSInteger) previousPageID;

- (GTWAOFRawDictionary*) initFindingDictionaryInAOF:(id<GTWAOF>)aof;
- (GTWAOFRawDictionary*) initWithPageID:(NSInteger)pageID fromAOF:(id<GTWAOF>)aof;
- (GTWAOFRawDictionary*) initWithPage:(GTWAOFPage*)page fromAOF:(id<GTWAOF>)aof;

- (id) objectForKey:(id)aKey;
- (NSEnumerator*) keyEnumerator;
- (void)enumerateKeysAndObjectsUsingBlock:(void (^)(id key, id obj, BOOL *stop))block;
- (void)enumerateDataPairsUsingBlock:(void (^)(NSData *keydata, NSRange keyrange, NSData *objdata, NSRange objrange, BOOL *stop))block;
- (NSArray *)allKeysForObject:(id)anObject;
- (NSData*)anyKeyForObject:(NSData*)anObject;
- (NSData*)anyKeyForData:(NSData*)anObject withRange:(NSRange) range;

@end
