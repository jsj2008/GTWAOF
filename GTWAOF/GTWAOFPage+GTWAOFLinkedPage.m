//
//  GTWAOFPage+GTWAOFLinkedPage.m
//  GTWAOF
//
//  Created by Gregory Williams on 12/9/13.
//  Copyright (c) 2013 Gregory Todd Williams. All rights reserved.
//

#import "GTWAOFPage+GTWAOFLinkedPage.h"

#define TS_OFFSET       8
#define PREV_OFFSET     16

@implementation GTWAOFPage (GTWAOFLinkedPage)

- (NSData*) cookie {
    NSData* data    = self.data;
    return [data subdataWithRange:NSMakeRange(0, 4)];
}
- (NSInteger) previousPageID {
    NSData* data    = self.data;
    uint64_t big_prev = 0;
    [data getBytes:&big_prev range:NSMakeRange(PREV_OFFSET, 8)];
    unsigned long long prev = NSSwapBigLongLongToHost((unsigned long long) big_prev);
    return (NSInteger) prev;
}

- (NSDate*) lastModified {
    NSData* data    = self.data;
    uint64_t big_ts = 0;
    [data getBytes:&big_ts range:NSMakeRange(TS_OFFSET, 8)];
    unsigned long long ts = NSSwapBigLongLongToHost((unsigned long long) big_ts);
    return [NSDate dateWithTimeIntervalSince1970:(double)ts];
}

@end
