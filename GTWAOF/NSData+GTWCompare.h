//
//  NSData+GTWCompare.h
//  GTWAOF
//
//  Created by Gregory Williams on 12/19/13.
//  Copyright (c) 2013 Gregory Todd Williams. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSData (GTWCompare)

- (NSComparisonResult)gtw_compare:(NSData *)aData;
- (NSComparisonResult) gtw_trucatedCompare:(NSData*)aData;
- (BOOL) gtw_hasPrefix:(NSData*)data;

- (NSUInteger) integerFromHostLongLong;
+ (NSData*) bigLongLongDataWithInteger:(NSUInteger)value;

@end
