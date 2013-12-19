//
//  GTWAOFBTreeNode.h
//  GTWAOF
//
//  Created by Gregory Williams on 12/18/13.
//  Copyright (c) 2013 Gregory Todd Williams. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "GTWAOF.h"
#import "GTWAOFPage.h"

#define BTREE_ROOT_NODE_COOKIE "BPTR"
#define BTREE_INTERNAL_NODE_COOKIE "BPTI"
#define BTREE_LEAF_NODE_COOKIE "BPTL"

typedef NS_ENUM(NSInteger, GTWAOFBTreeNodeType) {
    GTWAOFBTreeRootNodeType,
    GTWAOFBTreeInternalNodeType,
    GTWAOFBTreeLeafNodeType
};

@interface GTWAOFBTreeNode : NSObject {
    id<GTWAOF> _aof;
    GTWAOFPage* _page;
    NSInteger _parentID;
    NSArray* _keys;
    NSArray* _objects;
    NSArray* _pageIDs;
}

@property (readonly) GTWAOFBTreeNodeType type;

- (GTWAOFBTreeNode*) initWithPageID:(NSInteger)pageID parentID:(NSInteger)parentID fromAOF:(id<GTWAOF>)aof;
- (GTWAOFBTreeNode*) initWithPage:(GTWAOFPage*)page parentID:(NSInteger)parentID fromAOF:(id<GTWAOF>)aof;
- (NSInteger) pageID;
- (NSDate*) lastModified;
- (NSUInteger) count;
- (NSArray*) allKeys;
- (NSData*) maxKey;
- (NSData*) minKey;
- (void)enumerateKeysAndPageIDsUsingBlock:(void (^)(NSData* key, NSInteger pageID, BOOL *stop))block;
- (void)enumerateKeysAndObjectsUsingBlock:(void (^)(NSData* key, NSData* obj, BOOL *stop))block;
- (GTWAOFBTreeNode*) childForKey:(NSData*)key;
- (BOOL) verify;

@end

@interface GTWMutableAOFBTreeNode : GTWAOFBTreeNode

- (GTWMutableAOFBTreeNode*) initInternalWithParentID: (NSInteger) parentID keys:(NSArray*)keys pageIDs:(NSArray*)objects updateContext:(GTWAOFUpdateContext*) ctx;
- (GTWMutableAOFBTreeNode*) initLeafWithParentID: (NSInteger) parentID keys:(NSArray*)keys objects:(NSArray*)objects updateContext:(GTWAOFUpdateContext*) ctx;

/**
 - create new root node from old root node (adding one new child pageID)
 - split root node into two new internal nodes (adding one new and replacing one old child pageIDs) and create new root node
 - create new internal node from old internal node (adding one new child pageID)
 - split internal node into two new internal nodes (adding one new and replacing one old child pageIDs)
 - create new leaf node from old leaf node (adding one new object value)
 
 trivial case where root is a leaf:
 - split root node into two new leaf nodes (adding one new object value) and create new root node
 
 */

@end
