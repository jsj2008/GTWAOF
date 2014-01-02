//
//  GTWAOFMemoryMappedFile.m
//  GTWAOF
//
//  Created by Gregory Williams on 1/1/14.
//  Copyright (c) 2014 Gregory Todd Williams. All rights reserved.
//

#import "GTWAOFMemoryMappedFile.h"
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
#include <sys/mman.h>
#import <stdio.h>
#import "GTWAOFPage.h"
#import "GTWAOFUpdateContext.h"

static const size_t MMAP_CHUNK_SIZE = 16777216;

@implementation GTWAOFMemoryMappedFile

- (GTWAOFMemoryMappedFile*) initWithFilename: (NSString*) file {
    return [self initWithFilename:file flags:O_RDWR|O_SHLOCK];
}

- (GTWAOFMemoryMappedFile*) initWithFilename: (NSString*) file flags:(int)oflag {
    if (self = [self init]) {
        _filename   = file;
        
        NSURL* url    = [[NSURL fileURLWithPath:file] absoluteURL];
        const char* filename    = [url fileSystemRepresentation];
        //        NSLog(@"AOF file: %s", filename);
        
        //        const char* filename  = [file UTF8String];
        struct stat sbuf;
        int sr	= stat(filename, &sbuf);
        if (sr == -1 && errno == ENOENT) {
            struct stat buf;
            _fd			= open(filename, O_CREAT|oflag);
            if (_fd < 0) {
                perror("*** failed to create database file");
                return nil;
            }
            fchmod(_fd, S_IRUSR|S_IWUSR|S_IRGRP);
            _pageSize   = AOF_PAGE_SIZE;
            fstat(_fd, &buf);
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
            
            _fd			= open(filename, oflag);
            if (_fd == -1) {
                perror("*** failed to open database file");
                return nil;
            }
            _pageSize   = AOF_PAGE_SIZE;
            fstat(_fd, &buf);
            _pageCount	= (buf.st_size / _pageSize);
        }
    }
    return self;
}

- (GTWAOFMemoryMappedFile*) init {
    if (self = [super init]) {
        self.updateQueue    = dispatch_queue_create("us.kasei.sparql.aof", DISPATCH_QUEUE_SERIAL);
        _mapped             = [NSMutableDictionary dictionary];
        _pageCache          = [[NSMapTable alloc] init];
        _objectCache        = [[NSCache alloc] init];
        [_objectCache setCountLimit:512];
    }
    return self;
}

- (GTWAOFPage*) readPage: (NSInteger) pageID {
    if (pageID >= _pageCount)
        return nil;
    
    GTWAOFPage* page    = [_pageCache objectForKey:@(pageID)];
    if (page) {
        //        NSLog(@"got cached page %lld\n", (long long) pageID);
        return page;
    }
    
    off_t pageOffset	= pageID * _pageSize;
    off_t chunk         = pageOffset / MMAP_CHUNK_SIZE;
    off_t chunk_offset  = pageOffset % MMAP_CHUNK_SIZE;
    off_t offset        = chunk * MMAP_CHUNK_SIZE;
    
    NSData* data;
    NSValue* value = _mapped[@(chunk)];
    if (value) {
//        NSLog(@"page %lld already mapped to chunk %d", (long long)pageID, (int)chunk);
        char* ptr   = [value pointerValue];
        data        = [NSData dataWithBytesNoCopy:&(ptr[chunk_offset]) length:_pageSize freeWhenDone:NO];
    } else {
        NSLog(@"mmapping page %lld from fd %d for chunk %d with length %lld", (long long)pageID, _fd, (int)chunk, (long long)MMAP_CHUNK_SIZE);
        char* ptr   = mmap(NULL, MMAP_CHUNK_SIZE, PROT_READ, MAP_FILE|MAP_SHARED, _fd, offset);
        if (ptr == MAP_FAILED) {
            perror("mmap");
            return nil;
        }
        NSLog(@"mmapped page %lld at %p", (long long)pageID, ptr);
        _mapped[@(chunk)]  = [NSValue valueWithPointer:ptr];
        data    = [NSData dataWithBytesNoCopy:&(ptr[chunk_offset]) length:_pageSize freeWhenDone:NO];
    }
    page    = [[GTWAOFPage alloc] initWithPageID:pageID data:data committed:YES];
    [_pageCache setObject:page forKey:@(pageID)];
    return page;
}

- (NSString*) description {
    NSMutableString *description = [NSMutableString stringWithFormat:@"<%@: %p; %@; %lu pages>", NSStringFromClass([self class]), self, _filename, _pageCount];
    return description;
}

- (id)cachedObjectForPage:(NSInteger)pageID {
    return [_objectCache objectForKey:@(pageID)];
}

- (void)setObject:(id)object forPage:(NSInteger)pageID {
    [_objectCache setObject:object forKey:@(pageID)];
}

- (void)dealloc {
    NSLog(@"dealloc called");
    [_mapped enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        NSValue* value  = obj;
        void* ptr       = [value pointerValue];
        NSLog(@"unmapping %p", ptr);
        munmap(ptr, MMAP_CHUNK_SIZE);
    }];
    return;
}

@end
