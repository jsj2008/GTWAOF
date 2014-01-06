//
//  GTWAOFPage+GTWAOFLinkedPage.m
//  GTWAOF
//
//  Created by Gregory Williams on 12/9/13.
//  Copyright (c) 2013 Gregory Todd Williams. All rights reserved.
//

#import "GTWAOFPage+GTWAOFLinkedPage.h"
#import "NSData+GTWCompare.h"

#define TS_OFFSET       8
#define PREV_OFFSET     16

@implementation GTWAOFPage (GTWAOFLinkedPage)

- (NSData*) cookie {
    NSData* data    = self.data;
    return [data subdataWithRange:NSMakeRange(0, 4)];
}
- (NSInteger) previousPageID {
    return (NSInteger)[self.data gtw_integerFromBigLongLongRange:NSMakeRange(PREV_OFFSET, 8)];
}

- (NSDate*) lastModified {
    NSUInteger ts   = [self.data gtw_integerFromBigLongLongRange:NSMakeRange(TS_OFFSET, 8)];
    return [NSDate dateWithTimeIntervalSince1970:(double)ts];
}

@end
