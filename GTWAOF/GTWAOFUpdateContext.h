//
//  GTWAOFUpdateContext.h
//  GTWAOF
//
//  Created by Gregory Williams on 12/8/13.
//  Copyright (c) 2013 Gregory Todd Williams. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "GTWAOF.h"
#import "GTWAOFPage.h"

@interface GTWAOFUpdateContext : NSObject {
    uint64_t nextPageID;
}

@property id<GTWAOF> aof;
@property NSMutableArray* createdPages;

- (NSUInteger) pageSize;
- (GTWAOFUpdateContext*) initWithAOF: (id<GTWAOF>) aof;
- (GTWAOFPage*) readPage: (NSInteger) pageID;
- (GTWAOFPage*) createPageWithData: (NSData*)data;

@end
