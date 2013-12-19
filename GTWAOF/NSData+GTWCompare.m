//
//  NSData+GTWCompare.m
//  GTWAOF
//
//  Created by Gregory Williams on 12/19/13.
//  Copyright (c) 2013 Gregory Todd Williams. All rights reserved.
//

#import "NSData+GTWCompare.h"

@implementation NSData (GTWCompare)

- (NSComparisonResult)gtw_compare:(NSData *)aData {
    NSUInteger len  = [self length];
    NSUInteger alen = [aData length];
    int r;
    if (len == alen) {
        r   = memcmp(self.bytes, aData.bytes, len);
    } else {
        NSUInteger min  = (len < alen) ? len : alen;
        r   = memcmp(self.bytes, aData.bytes, min);
        if (r == 0) {
            if (len < alen) {
                r   = -1;
            } else {
                r   = 1;
            }
        }
    }
    if (r == 0) {
        return NSOrderedSame;
    } else if (r < 0) {
        return NSOrderedAscending;
    } else {
        return NSOrderedDescending;
    }
}

@end
