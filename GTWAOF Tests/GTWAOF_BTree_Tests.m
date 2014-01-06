//
//  GTWAOF_BTree_Tests.m
//  GTWAOF
//
//  Created by Gregory Williams on 12/21/13.
//  Copyright (c) 2013 Gregory Todd Williams. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "GTWAOFBTreeNode.h"
#import "GTWAOFBTree.h"
#import "GTWAOFDirectFile.h"
#import "GTWAOFMemory.h"
#import "NSData+GTWCompare.h"

@interface GTWAOF_BTree_Tests : XCTestCase {
    id<GTWAOF,GTWMutableAOF> _aof;
    GTWMutableAOFBTree* _btree;
}

@end

@implementation GTWAOF_BTree_Tests

- (void)setUp {
    [super setUp];
    // Put setup code here. This method is called before the invocation of each test method in the class.
    _aof    = [[GTWAOFMemory alloc] init];
    [_aof updateWithBlock:^BOOL(GTWAOFUpdateContext *ctx) {
        _btree  = [[GTWMutableAOFBTree alloc] initEmptyBTreeWithKeySize:8 valueSize:8 updateContext:ctx];
        return YES;
    }];
}

- (void)tearDown {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    [super tearDown];
}

- (void)testBTreeInsert {
    XCTAssert(_btree, @"BTree object");
    XCTAssert([_btree count] == 0, @"Empty BTree size");
    [self insertDoublesRange:NSMakeRange(1, 1)];
    XCTAssert([_btree count] == 1, @"BTree size %lld == 1", (long long)[_btree count]);
    NSMutableIndexSet* keyset = [NSMutableIndexSet indexSet];
    NSMutableIndexSet* valset = [NSMutableIndexSet indexSet];
    [_btree enumerateKeysAndObjectsUsingBlock:^(NSData *key, NSData *obj, BOOL *stop) {
        NSInteger k = [key gtw_integerFromBigLongLong];
        NSInteger v = [obj gtw_integerFromBigLongLong];
        [keyset addIndex:k];
        [valset addIndex:v];
    }];
    NSInteger firstkey  = [keyset firstIndex];
    NSInteger lastkey   = [keyset lastIndex];
    XCTAssert(firstkey == 1, @"First set key");
    XCTAssert(lastkey == 1, @"Last set key");
    
    NSInteger firstval  = [valset firstIndex];
    NSInteger lastval   = [valset lastIndex];
    XCTAssert(firstval == 2, @"First set value %lld", (long long)firstval);
    XCTAssert(lastval == 2, @"Last set value %lld", (long long)lastval);
}

- (void)testBTreeInsert2 {
    XCTAssert(_btree, @"BTree object");
    XCTAssert([_btree count] == 0, @"Empty BTree size");
    const int count = 3;
    [self insertDoublesRange:NSMakeRange(0, count)];
    XCTAssert([_btree count] == count, @"BTree size %lld == %d", (long long)[_btree count], count);
    NSMutableIndexSet* keyset = [NSMutableIndexSet indexSet];
    NSMutableIndexSet* valset = [NSMutableIndexSet indexSet];
    [_btree enumerateKeysAndObjectsUsingBlock:^(NSData *key, NSData *obj, BOOL *stop) {
        NSInteger k = [key gtw_integerFromBigLongLong];
        NSInteger v = [obj gtw_integerFromBigLongLong];
        [keyset addIndex:k];
        [valset addIndex:v];
    }];
    NSInteger firstkey  = [keyset firstIndex];
    NSInteger lastkey   = [keyset lastIndex];
    XCTAssert(firstkey == 0, @"First set key");
    XCTAssert(lastkey == count-1, @"Last set key");
    
    NSInteger firstval  = [valset firstIndex];
    NSInteger lastval   = [valset lastIndex];
    XCTAssert(firstval == 0, @"First set value %lld", (long long)firstval);
    XCTAssert(lastval == 2*(count-1), @"Last set value %lld", (long long)lastval);
}

- (void)testBTreeInsertDuplicate {
    XCTAssert(_btree, @"BTree object");
    XCTAssert([_btree count] == 0, @"Empty BTree size");
    int count   = 1;
    [self insertDoublesRange:NSMakeRange(0, count)];
    [self insertDoublesRange:NSMakeRange(0, count)];
    XCTAssert([_btree count] == count, @"BTree size %lld == %d", (long long)[_btree count], count);
    NSMutableIndexSet* keyset = [NSMutableIndexSet indexSet];
    NSMutableIndexSet* valset = [NSMutableIndexSet indexSet];
    [_btree enumerateKeysAndObjectsUsingBlock:^(NSData *key, NSData *obj, BOOL *stop) {
        NSInteger k = [key gtw_integerFromBigLongLong];
        NSInteger v = [obj gtw_integerFromBigLongLong];
        [keyset addIndex:k];
        [valset addIndex:v];
    }];
    NSInteger firstkey  = [keyset firstIndex];
    NSInteger lastkey   = [keyset lastIndex];
    XCTAssert(firstkey == 0, @"First set key");
    XCTAssert(lastkey == count-1, @"Last set key");
    
    NSInteger firstval  = [valset firstIndex];
    NSInteger lastval   = [valset lastIndex];
    XCTAssert(firstval == 0, @"First set value %lld", (long long)firstval);
    XCTAssert(lastval == 2*(count-1), @"Last set value %lld", (long long)lastval);
}

- (void)testBTreeInsert511 {
    XCTAssert(_btree, @"BTree object");
    XCTAssert([_btree count] == 0, @"Empty BTree size");
    int count   = 511;
    [self insertDoublesRange:NSMakeRange(0, count)];
    XCTAssert([_btree count] == count, @"BTree size %lld == %d", (long long)[_btree count], count);
    NSMutableIndexSet* keyset = [NSMutableIndexSet indexSet];
    NSMutableIndexSet* valset = [NSMutableIndexSet indexSet];
    [_btree enumerateKeysAndObjectsUsingBlock:^(NSData *key, NSData *obj, BOOL *stop) {
        NSInteger k = [key gtw_integerFromBigLongLong];
        NSInteger v = [obj gtw_integerFromBigLongLong];
        [keyset addIndex:k];
        [valset addIndex:v];
    }];
    NSInteger firstkey  = [keyset firstIndex];
    NSInteger lastkey   = [keyset lastIndex];
    XCTAssert(firstkey == 0, @"First set key");
    XCTAssert(lastkey == count-1, @"Last set key");
    
    NSInteger firstval  = [valset firstIndex];
    NSInteger lastval   = [valset lastIndex];
    XCTAssert(firstval == 0, @"First set value %lld", (long long)firstval);
    XCTAssert(lastval == 2*(count-1), @"Last set value %lld", (long long)lastval);
}

- (void)testBTreeInsertN {
    XCTAssert(_btree, @"BTree object");
    XCTAssert([_btree count] == 0, @"Empty BTree size");
    int count   = 8000;
//    for (count = 511; count < 2000; count++) {
        [self insertDoublesRange:NSMakeRange(0, count)];
        XCTAssert([_btree count] == count, @"BTree size %lld == %d", (long long)[_btree count], count);
        NSMutableIndexSet* keyset = [NSMutableIndexSet indexSet];
        NSMutableIndexSet* valset = [NSMutableIndexSet indexSet];
        [_btree enumerateKeysAndObjectsUsingBlock:^(NSData *key, NSData *obj, BOOL *stop) {
            NSInteger k = [key gtw_integerFromBigLongLong];
            NSInteger v = [obj gtw_integerFromBigLongLong];
            [keyset addIndex:k];
            [valset addIndex:v];
        }];
        NSInteger firstkey  = [keyset firstIndex];
        NSInteger lastkey   = [keyset lastIndex];
        XCTAssert(firstkey == 0, @"First set key");
        XCTAssert(lastkey == count-1, @"Last set key");
        
        NSInteger firstval  = [valset firstIndex];
        NSInteger lastval   = [valset lastIndex];
        XCTAssert(firstval == 0, @"First set value %lld", (long long)firstval);
        XCTAssert(lastval == 2*(count-1), @"Last set value %lld", (long long)lastval);
//    }
}



- (void) insertDoublesRange:(NSRange)range {
    [_aof updateWithBlock:^BOOL(GTWAOFUpdateContext *ctx) {
        for (NSInteger k = range.location; k < (range.location+range.length); k++) {
            [_btree insertValue:[NSData gtw_bigLongLongDataWithInteger:k*2] forKey:[NSData gtw_bigLongLongDataWithInteger:k] updateContext:ctx];
        }
        return YES;
    }];
}

@end
