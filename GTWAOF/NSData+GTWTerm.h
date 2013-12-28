//
//  NSData+GTWTerm.h
//  GTWAOF
//
//  Created by Gregory Williams on 12/27/13.
//  Copyright (c) 2013 Gregory Todd Williams. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <GTWSWBase/GTWSWBase.h>

@interface NSData (GTWTerm)

+ (NSData*) gtw_dataFromTerm:(id<GTWTerm>)term;
- (id<GTWTerm>) gtw_term;

@end
