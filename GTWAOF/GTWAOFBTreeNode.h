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

#define BTREE_INTERNAL_NODE_COOKIE "BPTI"
#define BTREE_LEAF_NODE_COOKIE "BPTL"

typedef NS_ENUM(NSInteger, GTWAOFBTreeNodeType) {
    GTWAOFBTreeInternalNodeType,
    GTWAOFBTreeLeafNodeType
};

typedef NS_OPTIONS(NSInteger, GTWAOFBTreeNodeFlags) {
    GTWAOFBTreeRoot
};

@interface GTWAOFBTreeNode : NSObject {
    id<GTWAOF> _aof;
    GTWAOFPage* _page;
    NSInteger _parentID;
    NSArray* _keys;
    NSArray* _objects;
    NSArray* _pageIDs;
}

@property (readonly) GTWAOFBTreeNodeFlags flags;
@property (readonly) NSInteger keySize;
@property (readonly) NSInteger valSize;
@property (readonly) NSInteger maxInternalPageKeys;
@property (readonly) NSInteger maxLeafPageKeys;

@property (readonly) GTWAOFBTreeNodeType type;

- (GTWAOFBTreeNode*) initWithPageID:(NSInteger)pageID parentID:(NSInteger)parentID fromAOF:(id<GTWAOF>)aof;
- (GTWAOFBTreeNode*) initWithPage:(GTWAOFPage*)page parentID:(NSInteger)parentID fromAOF:(id<GTWAOF>)aof;
- (NSInteger) pageID;
- (NSDate*) lastModified;
- (NSUInteger) count;
- (NSArray*) allKeys;
- (NSArray*) childrenPageIDs;
- (NSData*) maxKey;
- (NSData*) minKey;
- (void)enumerateKeysAndPageIDsUsingBlock:(void (^)(NSData* key, NSInteger pageID, BOOL *stop))block;
- (void)enumerateKeysAndObjectsUsingBlock:(void (^)(NSData* key, NSData* obj, BOOL *stop))block;
- (GTWAOFBTreeNode*) childForKey:(NSData*)key;
- (BOOL) verify;

@end

@interface GTWMutableAOFBTreeNode : GTWAOFBTreeNode

- (GTWMutableAOFBTreeNode*) initInternalWithParentID: (NSInteger) parentID keySize:(NSInteger)keySize valueSize:(NSInteger)valSize keys:(NSArray*)keys pageIDs:(NSArray*)objects updateContext:(GTWAOFUpdateContext*) ctx;
- (GTWMutableAOFBTreeNode*) initLeafWithParentID: (NSInteger) parentID keySize:(NSInteger)keySize valueSize:(NSInteger)valSize keys:(NSArray*)keys objects:(NSArray*)objects updateContext:(GTWAOFUpdateContext*) ctx;

@end
