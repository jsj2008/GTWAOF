//
//  GTWAOFMemory.h
//  GTWAOF
//
//  Created by Gregory Williams on 12/28/13.
//  Copyright (c) 2013 Gregory Todd Williams. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "GTWAOF.h"

@interface GTWAOFMemory : NSObject<GTWAOF,GTWMutableAOF> {
    NSCache* _objectCache;
}

@property dispatch_queue_t updateQueue;
@property (readonly) NSMutableDictionary* pages;
@property (readonly) NSUInteger pageSize;

@end
