//
//  GTWAOFDirectFile.m
//  GTWAOF
//
//  Created by Gregory Williams on 12/8/13.
//  Copyright (c) 2013 Gregory Todd Williams. All rights reserved.
//

#import "GTWAOFDirectFile.h"
#include <stddef.h>
#include <stdlib.h>
#include <stdio.h>
#include <fcntl.h>
#include <string.h>
#include <unistd.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/uio.h>
#include <errno.h>
#include <inttypes.h>
#import <stdio.h>
#import "GTWAOFPage.h"
#import "GTWAOFUpdateContext.h"

@implementation GTWAOFDirectFile

- (GTWAOFDirectFile*) initWithFilename: (NSString*) file {
    return [self initWithFilename:file flags:O_RDWR|O_SHLOCK];
}

- (GTWAOFDirectFile*) initWithFilename: (NSString*) file flags:(int)oflag {
    if (self = [self init]) {
        _filename   = file;
        
        NSURL* url    = [[NSURL fileURLWithPath:file] absoluteURL];
        const char* filename    = [url fileSystemRepresentation];
        NSLog(@"AOF file: %s", filename);
        
//        const char* filename  = [file UTF8String];
        struct stat sbuf;
        int sr	= stat(filename, &sbuf);
        if (sr == -1 && errno == ENOENT) {
            struct stat buf;
            fd			= open(filename, O_CREAT|oflag);
            if (fd < 0) {
                perror("*** failed to create database file");
                return nil;
            }
            fchmod(fd, S_IRUSR|S_IWUSR|S_IRGRP);
            _pageSize   = AOF_PAGE_SIZE;
            fstat(fd, &buf);
            _pageCount  = (buf.st_size / _pageSize);
        } else {
            struct stat buf;
            
            struct stat sbuf;
            if (stat(filename, &sbuf)) {
                perror("Cannot stat database file");
                return NULL;
            }
            
            off_t size	= sbuf.st_size;
            if ((size % AOF_PAGE_SIZE) != 0) {
                unsigned extra	= size % AOF_PAGE_SIZE;
                fprintf(stderr, "*** database file size (%lu) is not a multiple of the page size (%u extra bytes)\n", (unsigned long) size, extra);
                return NULL;
            }
            
            fd			= open(filename, oflag);
            if (fd == -1) {
                perror("*** failed to open database file");
                return nil;
            }
            _pageSize   = AOF_PAGE_SIZE;
            fstat(fd, &buf);
            _pageCount	= (buf.st_size / _pageSize);
        }
    }
    return self;
}

- (GTWAOFDirectFile*) init {
    if (self = [super init]) {
        self.updateQueue    = dispatch_queue_create("us.kasei.sparql.aof", DISPATCH_QUEUE_SERIAL);
        _pageCache          = [[NSCache alloc] init];
        [_pageCache setCountLimit:32];
    }
    return self;
}

- (GTWAOFPage*) readPage: (NSInteger) pageID {
//    NSLog(@"*** reading page %d", (int)pageID);
	if (pageID >= _pageCount)
		return nil;
    
    GTWAOFPage* page    = [_pageCache objectForKey:@(pageID)];
    if (page) {
//        NSLog(@"got cached page %lld\n", (long long) pageID);
        return page;
    }
    
	uint64_t offset	= pageID * _pageSize;
    char* buf   = malloc(_pageSize);
    size_t to_read  = _pageSize;
	ssize_t nread       = 0;
	ssize_t total_read	= 0;
	do {
		nread = pread(fd, &(buf[nread]), to_read, offset+total_read);
		if (nread < 0) {
			if (errno != EINTR) {
				perror ("read");
				return nil;
			}
            
			/* We are here because the read() call was interrupted before
			 * anything was read. */
		} else if (nread == 0) {
			break;
		} else {
			to_read		-= nread;
			total_read	+= nread;
		}
	} while (1);
    NSData* data    = [NSData dataWithBytesNoCopy:buf length:_pageSize];
    page    = [[GTWAOFPage alloc] initWithPageID:pageID data:data committed:YES];
    
//    NSLog(@"caching page %lld\n", (long long) pageID);
    [_pageCache setObject:page forKey:@(pageID)];
    return page;
}

- (BOOL)updateWithBlock:(BOOL(^)(GTWAOFUpdateContext* ctx))block {
    @autoreleasepool {
        __block BOOL shouldCommit;
        __block GTWAOFUpdateContext* ctx;
        dispatch_sync(self.updateQueue, ^{
            ctx = [[GTWAOFUpdateContext alloc] initWithAOF:self];
            shouldCommit    = block(ctx);
        });
        if (shouldCommit) {
            NSArray* pages  = ctx.createdPages;
            if ([pages count]) {
    //            NSLog(@"Should commit changes in update context: %@", ctx);
                NSMutableData* data = [NSMutableData data];
                GTWAOFPage* first   = pages[0];
                NSInteger prevID    = first.pageID-1;
                for (GTWAOFPage* p in pages) {
                    if ([p.data length] != _pageSize) {
                        NSLog(@"Page has unexpected size %lu", [p.data length]);
                        return NO;
                    }

                    if (p.pageID == (prevID+1)) {
    //                    NSLog(@"-> %lu\n", p.pageID);
                        [data appendData:p.data];
                        prevID  = p.pageID;
                    } else {
                        NSLog(@"Pages aren't consecutive in commit");
                        return NO;
                    }
                }
                
                off_t offset    = self.pageCount * self.pageSize;
                const void* buf   = [data bytes];
                size_t to_write = [data length];
                ssize_t nwrite;
                ssize_t written = 0;
                while (written < to_write) {
                    //d		fprintf(stderr, "- trying to write %d bytes to offset %d\n", (int) (to_write-written), (int) (offset+written));
                    nwrite = pwrite(fd, (char*)buf+written, to_write-written, offset+written);
                    if (nwrite < 0) {
                        if (errno != EINTR) {
                            perror ("write");
                            return NO;
                        }
                        
                        /* We are here because write() call was interrupted
                         * before anything could be written. */
                    } else {
                        written += nwrite;
                    }
                }
                _pageCount  += [pages count];
                for (id<GTWAOFBackedObject> object in ctx.registeredObjects) {
                    object.aof  = self;
                }
            } else {
                NSLog(@"update is empty");
            }
            
            return YES;
        } else {
            return NO;
        }
    }
}

- (NSString*) description {
    NSMutableString *description = [NSMutableString stringWithFormat:@"<%@: %p; %@; %lu pages>", NSStringFromClass([self class]), self, _filename, _pageCount];
    return description;
}

@end
