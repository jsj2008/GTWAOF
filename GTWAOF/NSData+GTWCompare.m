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

- (NSComparisonResult) gtw_trucatedCompare:(NSData*)aData {
    NSData *truncated1, *truncated2;
    if ([self length] > [aData length]) {
        truncated1  = [self subdataWithRange:NSMakeRange(0, [aData length])];
        truncated2  = aData;
    } else {
        truncated2  = [aData subdataWithRange:NSMakeRange(0, [self length])];
        truncated1  = self;
    }
    NSComparisonResult r    = [truncated1 gtw_compare:truncated2];
    return r;
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

- (NSUInteger) integerFromHostLongLong {
    long long bign;
    [self getBytes:&bign range:NSMakeRange(0, 8)];
    long long n = NSSwapBigLongLongToHost(bign);
    return (NSUInteger) n;
}

+ (NSData*) bigLongLongDataWithInteger:(NSUInteger)value {
    long long n = (long long) value;
    long long bign  = NSSwapHostLongLongToBig(n);
    return [NSData dataWithBytes:&bign length:8];
}

@end
