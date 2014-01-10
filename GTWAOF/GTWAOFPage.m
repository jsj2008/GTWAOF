//
//  GTWAOFPage.m
//  GTWAOF
//
//  Created by Gregory Williams on 12/8/13.
//  Copyright (c) 2013 Gregory Todd Williams. All rights reserved.
//

#import "GTWAOFPage.h"
#import "GTWAOF.h"

@implementation GTWAOFPage

- (GTWAOFPage*) initWithPageID: (NSInteger) pageID data: (NSData*)data committed:(BOOL)committed {
    if (self = [self init]) {
        _pageID     = pageID;
        _committed  = committed;
        _data       = [data copy];
    }
    return self;
}

- (GTWAOFPage*) init {
    if (self = [super init]) {
        _committed  = NO;
        _pageID     = -1;
    }
    return self;
}

- (NSData*) data {
    return _data;
}

- (void) setData:(NSData *)data {
    _data       = data;
    _committed  = NO;
}

- (void) commitWithPageID: (NSInteger) pageID {
    _committed  = YES;
    _pageID     = pageID;
}

- (NSString*) description {
    NSMutableString* cookie = [NSMutableString string];
    const char* data    = [self.data bytes];
    for (int i = 0; i < 4; i++) {
        char c  = data[i];
        if (c >= 0x20 && c <= 0x7e) {
            [cookie appendFormat:@"%c", c];
        } else {
            [cookie appendFormat:@"%%%2d", c];
        }
    }
    NSMutableString *description = [NSMutableString stringWithFormat:@"<%@: %p; %04lu: '%@…'>", NSStringFromClass([self class]), self, _pageID, cookie];
    return description;
}

@end
