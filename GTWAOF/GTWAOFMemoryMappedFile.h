//
//  GTWAOFMemoryMappedFile.h
//  GTWAOF
//
//  Created by Gregory Williams on 1/1/14.
//  Copyright (c) 2014 Gregory Todd Williams. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "GTWAOF.h"

@interface GTWAOFMemoryMappedFile : NSObject<GTWAOF> {
    int _fd;
    NSMutableDictionary* _mapped;
    NSMapTable* _pageCache;
//    NSCache* _pageCache;
    NSCache* _objectCache;
}

@property (readonly) NSString* filename;
@property dispatch_queue_t updateQueue;
@property (readonly) NSUInteger pageSize;
@property (readonly) NSUInteger pageCount;

- (GTWAOFMemoryMappedFile*) initWithFilename: (NSString*) filename;
- (GTWAOFMemoryMappedFile*) initWithFilename: (NSString*) filename flags:(int)oflag;

@end
