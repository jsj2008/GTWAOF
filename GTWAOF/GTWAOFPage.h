//
//  GTWAOFPage.h
//  GTWAOF
//
//  Created by Gregory Williams on 12/8/13.
//  Copyright (c) 2013 Gregory Todd Williams. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface GTWAOFPage : NSObject {
    NSData* _data;
}

@property (readonly) BOOL committed;
@property (readonly) NSInteger pageID;

- (GTWAOFPage*) initWithPageID: (NSInteger) pageID data: (NSData*)data committed:(BOOL)committed;
- (NSData*) data;
- (void) setData:(NSData *)data;
- (void) commitWithPageID: (NSInteger) pageID;

@end
