//
//  GTWAOFBTree.h
//  GTWAOF
//
//  Created by Gregory Williams on 12/19/13.
//  Copyright (c) 2013 Gregory Todd Williams. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "GTWAOFBTreeNode.h"

@interface GTWAOFBTree : NSObject {
    id<GTWAOF> _aof;
    GTWAOFBTreeNode* _root;
}

- (GTWAOFBTree*) initWithRootPageID:(NSInteger)pageID fromAOF:(id<GTWAOF>)aof;
- (GTWAOFBTree*) initWithRootPage:(GTWAOFPage*)page fromAOF:(id<GTWAOF>)aof;

- (GTWAOFBTreeNode*) lcaNodeForKeysWithPrefix:(NSData*)prefix;
- (void)enumerateKeysAndObjectsUsingBlock:(void (^)(NSData* key, NSData* obj, BOOL *stop))block;
- (void)enumerateKeysAndObjectsMatchingPrefix:(NSData*)prefix usingBlock:(void (^)(NSData* key, NSData* obj, BOOL *stop))block;

@end

@interface GTWMutableAOFBTree : GTWAOFBTree

/**
 - create new root node from old root node (adding one new child pageID)
 - split root node into two new internal nodes (adding one new and replacing one old child pageIDs) and create new root node
 - create new internal node from old internal node (adding one new child pageID)
 - split internal node into two new internal nodes (adding one new and replacing one old child pageIDs)
 - create new leaf node from old leaf node (adding one new object value)
 
 trivial case where root is a leaf:
 - split root node into two new leaf nodes (adding one new object value) and create new root node
 
 */

- (GTWMutableAOFBTree*) initEmptyBTreeWithKeySize:(NSInteger)keySize valueSize:(NSInteger)valSize updateContext:(GTWAOFUpdateContext*) ctx;
- (GTWMutableAOFBTree*) insertValue:(NSData*)value forKey:(NSData*)key;
- (GTWMutableAOFBTree*) removeValueForKey:(NSData*)key;


@end
