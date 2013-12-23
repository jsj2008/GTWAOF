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
                return NSOrderedAscending;
            } else {
                return NSOrderedDescending;
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

- (BOOL) gtw_hasPrefix:(NSData*)aData {
    NSUInteger len  = [self length];
    NSUInteger alen = [aData length];
    if (alen > len)
        return NO;
    if (memcmp(self.bytes, aData.bytes, alen)) {
        return NO;
    } else {
        return YES;
    }
}

@end
