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

@interface GTWAOFRawValue : NSObject {
    id<GTWAOF> _aof;
    GTWAOFPage* _head;
}

@property BOOL verbose;
@property NSData* data;

- (NSDate*) lastModified;
- (NSInteger) pageID;
- (NSInteger) previousPageID;
- (GTWAOFPage*) head;

- (GTWAOFRawValue*) initWithPageID:(NSInteger)pageID fromAOF:(id<GTWAOF>)aof;
- (GTWAOFRawValue*) initWithPage:(GTWAOFPage*)page fromAOF:(id<GTWAOF>)aof;

- (NSUInteger) length;
- (NSUInteger) pageLength;

@end

@interface GTWMutableAOFRawValue : GTWAOFRawValue

+ (GTWMutableAOFRawValue*) valueWithData:(NSData*) data updateContext:(GTWAOFUpdateContext*) ctx;
+ (GTWAOFPage*) valuePageWithData:(NSData*)data updateContext:(GTWAOFUpdateContext*) ctx;

@end
