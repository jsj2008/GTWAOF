//
//  GTWAOFBTree.m
//  GTWAOF
//
//  Created by Gregory Williams on 12/19/13.
//  Copyright (c) 2013 Gregory Todd Williams. All rights reserved.
//

#import "GTWAOFBTree.h"

static const NSInteger keySize  = 32;
static const NSInteger valSize  = 8;

@implementation GTWAOFBTree

- (GTWAOFBTree*) initWithRootPageID:(NSInteger)pageID fromAOF:(id<GTWAOF>)aof {
    if (self = [self init]) {
        _aof        = aof;
        _root       = [[GTWAOFBTreeNode alloc] initWithPageID:pageID parentID:-1 keySize:keySize valueSize:valSize fromAOF:aof];
    }
    return self;
}

- (GTWAOFBTree*) initWithRootPage:(GTWAOFPage*)page fromAOF:(id<GTWAOF>)aof {
    if (self = [self init]) {
        _aof    = aof;
        _root       = [[GTWAOFBTreeNode alloc] initWithPage:page parentID:-1 keySize:keySize valueSize:valSize fromAOF:aof];
    }
    return self;
}

- (void)enumerateKeysAndObjectsUsingBlock:(void (^)(NSData* key, NSData* obj, BOOL *stop))block {
    GTWAOFBTreeNode* node   = _root;
    [GTWAOFBTree enumerateKeysAndObjectsForNode:node aof:_aof usingBlock:block];
}

+ (void)enumerateKeysAndObjectsForNode:(GTWAOFBTreeNode*)node aof:(id<GTWAOF>)aof usingBlock:(void (^)(NSData* key, NSData* obj, BOOL *stop))block {
    if (node.type == GTWAOFBTreeLeafNodeType) {
        [node enumerateKeysAndObjectsUsingBlock:^(NSData *key, NSData *obj, BOOL *stop) {
            block(key, obj, stop);
        }];
    } else {
        [node enumerateKeysAndPageIDsUsingBlock:^(NSData *key, NSInteger pageID, BOOL *stop) {
            GTWAOFBTreeNode* child  = [[GTWAOFBTreeNode alloc] initWithPageID:pageID parentID:node.pageID keySize:keySize valueSize:valSize fromAOF:aof];
            NSLog(@"found b+ tree child node %@", child);
            [GTWAOFBTree enumerateKeysAndObjectsForNode:child aof:aof usingBlock:block];
        }];
    }
}

@end

