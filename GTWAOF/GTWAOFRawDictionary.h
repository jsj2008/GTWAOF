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

@class GTWMutableAOFRawDictionary;

@interface GTWAOFRawDictionary : NSObject<GTWAOFBackedObject> {
    GTWAOFPage* _head;
    NSDictionary* _pageDict;
    NSDictionary* _revPageDict;
    NSCache* _cache;
    NSCache* _revCache;
//    id _prevPage;
}

@property BOOL verbose;
@property (readwrite) id<GTWAOF> aof;

- (NSDate*) lastModified;
- (NSUInteger) count;
- (NSInteger) pageID;
- (NSInteger) previousPageID;

+ (GTWAOFRawDictionary*) rawDictionaryWithPageID:(NSInteger)pageID fromAOF:(id<GTWAOF>)aof;
- (GTWAOFRawDictionary*) initFindingDictionaryInAOF:(id<GTWAOF>)aof;
- (GTWAOFRawDictionary*) initWithPageID:(NSInteger)pageID fromAOF:(id<GTWAOF>)aof;
- (GTWAOFRawDictionary*) initWithPage:(GTWAOFPage*)page fromAOF:(id<GTWAOF>)aof;

- (NSData*) objectForKey:(id)aKey;
- (GTWAOFPage*) pageForKey:(id)aKey;
- (NSEnumerator*) keyEnumerator;
- (NSData*)keyForObject:(NSData*)anObject;
- (void)enumerateKeysAndObjectsUsingBlock:(void (^)(id key, id obj, BOOL *stop))block;
- (GTWMutableAOFRawDictionary*) rewriteWithUpdateContext:(GTWAOFUpdateContext*) ctx;
- (GTWMutableAOFRawDictionary*) rewriteWithPageMap:(NSMutableDictionary*)map updateContext:(GTWAOFUpdateContext*) ctx;

@end

@interface GTWMutableAOFRawDictionary : GTWAOFRawDictionary

@property (readwrite) id<GTWAOF,GTWMutableAOF> aof;

+ (instancetype) mutableDictionaryWithDictionary:(NSDictionary*) dict updateContext:(GTWAOFUpdateContext*) ctx;
- (instancetype) dictionaryByAddingDictionary:(NSDictionary*) dict updateContext:(GTWAOFUpdateContext*)ctx;
- (instancetype) dictionaryByAddingDictionary:(NSDictionary*)dict settingPageIDs:(NSMutableDictionary*)pageDict updateContext:(GTWAOFUpdateContext*)ctx;
- (GTWMutableAOFRawDictionary*) dictionaryByAddingDictionary:(NSDictionary*) dict;
+ (GTWAOFPage*) dictionaryPageWithDictionary:(NSDictionary*)dict updateContext:(GTWAOFUpdateContext*) ctx;

@end
