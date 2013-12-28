//
//  NSIndexSet+GTWIndexRange.m
//  GTWAOF
//
//  Created by Gregory Williams on 12/27/13.
//  Copyright (c) 2013 Gregory Todd Williams. All rights reserved.
//

#import "NSIndexSet+GTWIndexRange.h"

@implementation NSIndexSet (GTWIndexRange)

- (NSString*) gtw_indexRanges {
    NSMutableArray* ranges  = [NSMutableArray array];
    [self enumerateRangesUsingBlock:^(NSRange range, BOOL *stop) {
        if (range.length > 1) {
            [ranges addObject:[NSString stringWithFormat:@"%lld–%lld", (long long)range.location, (long long)range.location+range.length-1]];
        } else{
            [ranges addObject:[NSString stringWithFormat:@"%lld", (long long)range.location]];
        }
    }];
    return [ranges componentsJoinedByString:@", "];
}

@end
