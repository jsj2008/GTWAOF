//
//  GTWAOF_Tests.m
//  GTWAOF Tests
//
//  Created by Gregory Williams on 12/19/13.
//  Copyright (c) 2013 Gregory Todd Williams. All rights reserved.
//


#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import "GTWAOF.h"
#import "GTWAOFDirectFile.h"
#import "GTWAOFUpdateContext.h"
#import "GTWAOFRawDictionary.h"
#import "GTWAOFRawQuads.h"
#import <SPARQLKit/SPARQLKit.h>
#import <SPARQLKit/SPKSPARQLLexer.h>
#import <SPARQLKit/SPKTurtleParser.h>
#import <GTWSWBase/GTWSWBase.h>
#import <GTWSWBase/GTWQuad.h>
#import <SPARQLKit/SPKNTriplesSerializer.h>
#import "GTWAOFQuadStore.h"
#import "GTWAOFRawValue.h"
#import "GTWAOFBTreeNode.h"
#import "GTWAOFBTree.h"

static NSData* dataFromInteger(NSUInteger value) {
    long long n = (long long) value;
    long long bign  = NSSwapHostLongLongToBig(n);
    return [NSData dataWithBytes:&bign length:8];
}

static NSData* dataFromIntegers(NSUInteger a, NSUInteger b, NSUInteger c, NSUInteger d) {
    NSMutableData* data = [NSMutableData dataWithLength:32];
    int64_t biga  = NSSwapHostLongLongToBig((unsigned long long) a);
    int64_t bigb  = NSSwapHostLongLongToBig((unsigned long long) b);
    int64_t bigc  = NSSwapHostLongLongToBig((unsigned long long) c);
    int64_t bigd  = NSSwapHostLongLongToBig((unsigned long long) d);
    [data replaceBytesInRange:NSMakeRange(0, 8) withBytes:&biga];
    [data replaceBytesInRange:NSMakeRange(8, 8) withBytes:&bigb];
    [data replaceBytesInRange:NSMakeRange(16, 8) withBytes:&bigc];
    [data replaceBytesInRange:NSMakeRange(24, 8) withBytes:&bigd];
    return data;
}

static NSUInteger integerFromData(NSData* data) {
    long long bign;
    [data getBytes:&bign range:NSMakeRange(0, 8)];
    long long n = NSSwapBigLongLongToHost(bign);
    return (NSUInteger) n;
}

@interface GTWAOF_Tests : XCTestCase {
    GTWAOFDirectFile* _aof;
}

@end

@implementation GTWAOF_Tests

- (void)setUp {
    [super setUp];
    // Put setup code here. This method is called before the invocation of each test method in the class.
    const char* filename    = "db/test.db";
    _aof    = [[GTWAOFDirectFile alloc] initWithFilename:@(filename)];
}

- (void)tearDown {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    unlink([_aof.filename UTF8String]);
    [super tearDown];
}

- (void)test_createLeaf {
    NSMutableArray* numbers = [NSMutableArray array];
    const int total_keys    = 204;
    for (int j = 0; j < total_keys; j++) {
        uint64_t value;
        uint32_t* pair  = (uint32_t*) &value;
        pair[0]     = rand();
        pair[1]     = rand();
        [numbers addObject:@(value)];
    }
    [numbers sortUsingSelector:@selector(compare:)];
    [_aof updateWithBlock:^BOOL(GTWAOFUpdateContext *ctx) {
        NSArray* pageNumbers    = [numbers copy];
        NSMutableArray* keys    = [NSMutableArray array];
        NSMutableArray* vals    = [NSMutableArray array];
        for (NSNumber* number in pageNumbers) {
            NSUInteger value    = [number unsignedIntegerValue];
            //            NSLog(@"adding value -> %lld", (long long)value);
            NSData* keyData     = dataFromIntegers(1, 2, 3, value);
            [keys addObject:keyData];
            NSData* object   = [NSData dataWithBytes:"\x00\x00\x00\x00\x00\x00\x00\xFF" length:8];
            [vals addObject:object];
        }
        GTWAOFBTreeNode* leaf  = [[GTWMutableAOFBTreeNode alloc] initLeafWithParent:nil isRoot:YES keySize:32 valueSize:8 keys:keys objects:vals updateContext:ctx];
        XCTAssertNotNil(leaf, @"B+ Tree leaf node created");
        return YES;
    }];
}

- (void)test_createInternal {
    [_aof updateWithBlock:^BOOL(GTWAOFUpdateContext *ctx) {
        NSArray* rootKeys    = @[dataFromIntegers(0,0,0,1), dataFromIntegers(0,0,0,2), dataFromIntegers(0,0,0,3)];
        NSArray* rootValues  = @[@(11), @(22), @(33), @(44)];
        GTWAOFBTreeNode* root   = [[GTWMutableAOFBTreeNode alloc] initInternalWithParent:nil isRoot:YES keySize:32 valueSize:8 keys:rootKeys pageIDs:rootValues updateContext:ctx];
        XCTAssertNotNil(root, @"B+ Tree root node created");
        return YES;
    }];
}

- (void)test_createOverfullInternal {
    [_aof updateWithBlock:^BOOL(GTWAOFUpdateContext *ctx) {
        NSMutableArray* rootKeys    = [NSMutableArray array];
        NSMutableArray* rootValues  = [NSMutableArray array];
        const int total_keys    = 500;
        for (int j = 0; j < total_keys; j++) {
            uint64_t value;
            uint32_t* pair  = (uint32_t*) &value;
            pair[0]     = rand();
            pair[1]     = rand();
            if (j < (total_keys-1)) {
                [rootKeys addObject:dataFromIntegers(0, 0, 0, value)];
            }
            [rootValues addObject:@(value)];
        }
        GTWAOFBTreeNode* root   = [[GTWMutableAOFBTreeNode alloc] initInternalWithParent:nil isRoot:YES keySize:32 valueSize:8 keys:rootKeys pageIDs:rootValues updateContext:ctx];
        XCTAssertNil(root, @"Overfull B+ Tree root node creation returns nil");
        return YES;
    }];
}

- (void)test_createOverfullLeaf {
    NSMutableArray* numbers = [NSMutableArray array];
    const int total_keys    = 500;
    for (int j = 0; j < total_keys; j++) {
        uint64_t value;
        uint32_t* pair  = (uint32_t*) &value;
        pair[0]     = rand();
        pair[1]     = rand();
        [numbers addObject:@(value)];
    }
    [numbers sortUsingSelector:@selector(compare:)];
    [_aof updateWithBlock:^BOOL(GTWAOFUpdateContext *ctx) {
        NSArray* pageNumbers    = [numbers copy];
        NSMutableArray* keys    = [NSMutableArray array];
        NSMutableArray* vals    = [NSMutableArray array];
        for (NSNumber* number in pageNumbers) {
            NSUInteger value    = [number unsignedIntegerValue];
            //            NSLog(@"adding value -> %lld", (long long)value);
            NSData* keyData     = dataFromIntegers(1, 2, 3, value);
            [keys addObject:keyData];
            NSData* object   = [NSData dataWithBytes:"\x00\x00\x00\x00\x00\x00\x00\xFF" length:8];
            [vals addObject:object];
        }
        GTWAOFBTreeNode* leaf  = [[GTWMutableAOFBTreeNode alloc] initLeafWithParent:nil isRoot:YES keySize:32 valueSize:8 keys:keys objects:vals updateContext:ctx];
        XCTAssertNil(leaf, @"Overfull B+ Tree leaf node creation returns nil");
        return YES;
    }];
}

- (void)test_createBTree {
//    XCTFail(@"No implementation for \"%s\"", __PRETTY_FUNCTION__);
    NSMutableArray* numbers = [NSMutableArray array];
    const int total_keys    = 500;
    const int page_size     = 100;
    for (int j = 0; j < total_keys; j++) {
        uint64_t value;
        uint32_t* pair  = (uint32_t*) &value;
        pair[0]     = rand();
        pair[1]     = rand();
        [numbers addObject:@(value)];
    }
    [numbers sortUsingSelector:@selector(compare:)];
    
    [_aof updateWithBlock:^BOOL(GTWAOFUpdateContext *ctx) {
        NSMutableArray* pages   = [NSMutableArray array];
        NSUInteger leaf_page    = 0;
        while ([numbers count]) {
            NSRange range           = NSMakeRange(0, page_size);
            NSArray* pageNumbers    = [numbers subarrayWithRange:range];
            [numbers removeObjectsInRange:range];
            NSMutableArray* keys    = [NSMutableArray array];
            NSMutableArray* vals    = [NSMutableArray array];
            for (NSNumber* number in pageNumbers) {
                NSUInteger value    = [number unsignedIntegerValue];
//                NSLog(@"adding value -> %lld", (long long)value);
                NSData* keyData     = dataFromIntegers(1, 2, 3, value);
                [keys addObject:keyData];
                NSData* object   = [NSData dataWithBytes:"\x00\x00\x00\x00\x00\x00\x00\xFF" length:8];
                [vals addObject:object];
            }
            GTWAOFBTreeNode* leaf  = [[GTWMutableAOFBTreeNode alloc] initLeafWithParent:nil isRoot:YES keySize:32 valueSize:8 keys:keys objects:vals updateContext:ctx];
            XCTAssertNotNil(leaf, @"B+ Tree leaf node created");
            [pages addObject:leaf];
            leaf_page++;
        }
        
        NSMutableArray* rootKeys    = [NSMutableArray array];
        NSMutableArray* rootValues  = [NSMutableArray array];
        for (NSInteger i = 0; i < [pages count]; i++) {
            GTWAOFBTreeNode* child  = pages[i];
            NSInteger pageID    = child.pageID;
            NSData* key         = [child maxKey];
            if (i < ([pages count]-1)) {
                [rootKeys addObject:key];
            }
            [rootValues addObject:@(pageID)];
        }
        
        GTWAOFBTreeNode* root   = [[GTWMutableAOFBTreeNode alloc] initInternalWithParent:nil isRoot:YES keySize:32 valueSize:8 keys:rootKeys pageIDs:rootValues updateContext:ctx];
        XCTAssertNotNil(root, @"B+ Tree root node created");
        return YES;
    }];
}

- (void)test_btreeDataSizes {
    const NSUInteger keySize = 2;
    const NSUInteger valSize = 3;
    NSMutableArray* numbers = [NSMutableArray array];
    const NSUInteger total_keys    = 1632;
    const NSUInteger start  = 0;
    for (int j = 0; j < total_keys; j++) {
        [numbers addObject:@(j)];
    }
    __block NSInteger pageID    = -1;
    [_aof updateWithBlock:^BOOL(GTWAOFUpdateContext *ctx) {
        NSArray* pageNumbers    = [numbers copy];
        NSMutableArray* keys    = [NSMutableArray array];
        NSMutableArray* vals    = [NSMutableArray array];
        for (NSNumber* number in pageNumbers) {
            NSUInteger value    = [number unsignedIntegerValue];
            //            NSLog(@"adding value -> %lld", (long long)value);
            NSData* keyIntData  = dataFromInteger(value);
            NSData* keyData     = [keyIntData subdataWithRange:NSMakeRange(6, 2)];
            [keys addObject:keyData];
            NSData* object   = [NSData dataWithBytes:"\x00\x00\xFF" length:3];
            [vals addObject:object];
        }
        GTWAOFBTreeNode* leaf  = [[GTWMutableAOFBTreeNode alloc] initLeafWithParent:nil isRoot:YES keySize:keySize valueSize:valSize keys:keys objects:vals updateContext:ctx];
        XCTAssertNotNil(leaf, @"B+ Tree leaf node created with data sizes {%d, %d}", (int)keySize, (int)valSize);
        if (leaf) {
            pageID  = leaf.pageID;
            return YES;
        }
        return NO;
    }];
    
    if (pageID >= 0) {
        GTWAOFBTreeNode* node   = [GTWAOFBTreeNode nodeWithPageID:pageID parent:nil fromAOF:_aof];
        XCTAssertNotNil(node, @"Retrieved leaf node from AOF");
        NSMutableIndexSet* set = [[NSMutableIndexSet alloc] init];
        __block NSUInteger count    = 0;
        [node enumerateKeysAndObjectsUsingBlock:^(NSData *key, NSData *obj, BOOL *stop) {
            XCTAssertEqual([key length], keySize, @"Expected key size");
            XCTAssertEqual([obj length], valSize, @"Expected value size");
//            NSLog(@"[%d] %@ -> %@", (int)count, key, obj);
            NSMutableData* k    = [NSMutableData dataWithLength:8];
            [k replaceBytesInRange:NSMakeRange(6, 2) withBytes:key.bytes];
            NSUInteger value    = integerFromData(k);
            [set addIndex:value];
            count++;
        }];
        __block NSInteger rangeCount    = 0;
        [set enumerateRangesUsingBlock:^(NSRange range, BOOL *stop) {
            rangeCount++;
            XCTAssertEqual(range.location, start, @"Contiguous range starts at expected value");
            XCTAssertEqual(range.length, total_keys, @"Contiguous range has expected length");
        }];
        XCTAssertEqual(rangeCount, (NSInteger)1, @"Contiguous range of custom-sized key data");
        XCTAssertEqual(count, (NSUInteger)total_keys, @"Expected pair count in leaf node");
    }
}

- (void)test_btreeZeroLengthValues {
    const NSUInteger keySize = 2;
    const NSUInteger valSize = 0;
    NSMutableArray* numbers = [NSMutableArray array];
    const NSUInteger total_keys    = 1000;
    const NSUInteger start  = 0;
    for (int j = 0; j < total_keys; j++) {
        [numbers addObject:@(j)];
    }
    __block NSInteger pageID    = -1;
    [_aof updateWithBlock:^BOOL(GTWAOFUpdateContext *ctx) {
        NSArray* pageNumbers    = [numbers copy];
        NSMutableArray* keys    = [NSMutableArray array];
        NSMutableArray* vals    = [NSMutableArray array];
        for (NSNumber* number in pageNumbers) {
            NSUInteger value    = [number unsignedIntegerValue];
            //            NSLog(@"adding value -> %lld", (long long)value);
            NSData* keyIntData  = dataFromInteger(value);
            NSData* keyData     = [keyIntData subdataWithRange:NSMakeRange(6, 2)];
            [keys addObject:keyData];
            NSData* object   = [NSData data];
            [vals addObject:object];
        }
        GTWAOFBTreeNode* leaf  = [[GTWMutableAOFBTreeNode alloc] initLeafWithParent:nil isRoot:YES keySize:keySize valueSize:valSize keys:keys objects:vals updateContext:ctx];
        XCTAssertNotNil(leaf, @"B+ Tree leaf node created with data sizes {%d, %d}", (int)keySize, (int)valSize);
        if (leaf) {
            pageID  = leaf.pageID;
            return YES;
        }
        return NO;
    }];
    
    if (pageID >= 0) {
        GTWAOFBTreeNode* node   = [GTWAOFBTreeNode nodeWithPageID:pageID parent:nil fromAOF:_aof];
        XCTAssertNotNil(node, @"Retrieved leaf node from AOF");
        NSMutableIndexSet* set = [[NSMutableIndexSet alloc] init];
        __block NSUInteger count    = 0;
        [node enumerateKeysAndObjectsUsingBlock:^(NSData *key, NSData *obj, BOOL *stop) {
            XCTAssertEqual([key length], keySize, @"Expected key size");
            XCTAssertEqual([obj length], valSize, @"Expected value size");
//            NSLog(@"[%d] %@ -> %@", (int)count, key, obj);
            NSMutableData* k    = [NSMutableData dataWithLength:8];
            [k replaceBytesInRange:NSMakeRange(6, 2) withBytes:key.bytes];
            NSUInteger value    = integerFromData(k);
            [set addIndex:value];
            count++;
        }];
        __block NSInteger rangeCount    = 0;
        [set enumerateRangesUsingBlock:^(NSRange range, BOOL *stop) {
            rangeCount++;
            XCTAssertEqual(range.location, start, @"Contiguous range starts at expected value");
            XCTAssertEqual(range.length, total_keys, @"Contiguous range has expected length");
        }];
        XCTAssertEqual(rangeCount, (NSInteger)1, @"Contiguous range of custom-sized key data");
        XCTAssertEqual(count, (NSUInteger)total_keys, @"Expected pair count in leaf node");
    }
}

@end
