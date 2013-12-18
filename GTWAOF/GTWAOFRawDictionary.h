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
    NSDictionary* _pageDict;
    NSDictionary* _revPageDict;
    NSCache* _cache;
    NSCache* _revCache;
    id _prevPage;
}

@property BOOL verbose;

- (NSDate*) lastModified;
- (NSUInteger) count;
- (NSInteger) pageID;
- (NSInteger) previousPageID;

- (GTWAOFRawDictionary*) initFindingDictionaryInAOF:(id<GTWAOF>)aof;
- (GTWAOFRawDictionary*) initWithPageID:(NSInteger)pageID fromAOF:(id<GTWAOF>)aof;
- (GTWAOFRawDictionary*) initWithPage:(GTWAOFPage*)page fromAOF:(id<GTWAOF>)aof;

- (id) objectForKey:(id)aKey;
- (NSEnumerator*) keyEnumerator;
- (NSData*)keyForObject:(NSData*)anObject;
- (void)enumerateKeysAndObjectsUsingBlock:(void (^)(id key, id obj, BOOL *stop))block;

@end

@interface GTWMutableAOFRawDictionary : GTWAOFRawDictionary

+ (instancetype) mutableDictionaryWithDictionary:(NSDictionary*) dict updateContext:(GTWAOFUpdateContext*) ctx;
- (GTWMutableAOFRawDictionary*) dictionaryByAddingDictionary:(NSDictionary*) dict;
+ (GTWAOFPage*) dictionaryPageWithDictionary:(NSDictionary*)dict updateContext:(GTWAOFUpdateContext*) ctx;

@end
