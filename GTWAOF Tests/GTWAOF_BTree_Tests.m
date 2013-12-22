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

@interface GTWAOF_BTree_Tests : XCTestCase

@end

@implementation GTWAOF_BTree_Tests {
    GTWAOFDirectFile* _aof;
}

- (void)setUp {
    [super setUp];
    // Put setup code here. This method is called before the invocation of each test method in the class.
    const char* filename    = "test.db";
    _aof    = [[GTWAOFDirectFile alloc] initWithFilename:@(filename)];
}

- (void)tearDown {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    unlink([_aof.filename UTF8String]);
    [super tearDown];
}

- (void)testExample
{
//    XCTFail(@"No implementation for \"%s\"", __PRETTY_FUNCTION__);
}

@end
