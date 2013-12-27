//
//  GTWAOFDirectFile.h
//  GTWAOF
//
//  Created by Gregory Williams on 12/8/13.
//  Copyright (c) 2013 Gregory Todd Williams. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "GTWAOF.h"

@interface GTWAOFDirectFile : NSObject<GTWAOF> {
    int _fd;
//    NSString* _filename;
    NSCache* _pageCache;
    NSCache* _objectCache;
}

@property (readonly) NSString* filename;
@property dispatch_queue_t updateQueue;
@property (readonly) NSUInteger pageSize;
@property (readonly) NSUInteger pageCount;

- (GTWAOFDirectFile*) initWithFilename: (NSString*) filename;
- (GTWAOFDirectFile*) initWithFilename: (NSString*) filename flags:(int)oflag;

@end
