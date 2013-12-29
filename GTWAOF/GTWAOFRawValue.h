//
//  GTWAOFRawValue.h
//  GTWAOF
//
//  Created by Gregory Williams on 12/16/13.
//  Copyright (c) 2013 Gregory Todd Williams. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "GTWAOF.h"
#import "GTWAOFPage.h"

#define RAW_VALUE_COOKIE "RVAL"

@class GTWMutableAOFRawValue;

@interface GTWAOFRawValue : NSObject<GTWAOFBackedObject> {
    GTWAOFPage* _head;
}

@property BOOL verbose;
@property (readwrite) id<GTWAOF> aof;
@property NSData* data;

- (NSDate*) lastModified;
- (NSInteger) pageID;
- (NSInteger) previousPageID;
- (GTWAOFPage*) head;

+ (GTWAOFRawValue*) rawValueWithPageID:(NSInteger)pageID fromAOF:(id<GTWAOF>)aof;
- (GTWAOFRawValue*) initWithPageID:(NSInteger)pageID fromAOF:(id<GTWAOF>)aof;
- (GTWAOFRawValue*) initWithPage:(GTWAOFPage*)page fromAOF:(id<GTWAOF>)aof;

- (NSUInteger) length;
- (NSUInteger) pageLength;

- (GTWMutableAOFRawValue*) rewriteWithUpdateContext:(GTWAOFUpdateContext*) ctx;

@end

@interface GTWMutableAOFRawValue : GTWAOFRawValue

+ (GTWMutableAOFRawValue*) valueWithData:(NSData*) data updateContext:(GTWAOFUpdateContext*) ctx;
+ (GTWAOFPage*) valuePageWithData:(NSData*)data updateContext:(GTWAOFUpdateContext*) ctx;

@end
