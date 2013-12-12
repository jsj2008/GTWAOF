//
//  GTWAOF.h
//  GTWAOF
//
//  Created by Gregory Williams on 12/8/13.
//  Copyright (c) 2013 Gregory Todd Williams. All rights reserved.
//

#define AOF_PAGE_SIZE 8192
//#define AOF_PAGE_SIZE 2048

#import <Foundation/Foundation.h>
#import "GTWAOFPage.h"

@class GTWAOFUpdateContext;
@protocol GTWAOF <NSObject>

- (NSUInteger) pageCount;
- (NSUInteger) pageSize;
- (GTWAOFPage*) readPage: (NSInteger) pageID;
- (BOOL)updateWithBlock:(BOOL(^)(GTWAOFUpdateContext* ctx))block;

@end
