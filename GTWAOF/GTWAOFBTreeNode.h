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

typedef NS_OPTIONS(uint32_t, GTWAOFBTreeNodeFlags) {
    GTWAOFBTreeRoot = 1
};

@interface GTWAOFBTreeNode : NSObject<GTWAOFBackedObject> {
    NSArray* _keys;
    NSArray* _objects;
    NSArray* _pageIDs;
    NSUInteger _subTreeCount;
    NSUInteger _itemCount;
    NSUInteger _keySize, _valSize;
}

@property (readwrite) id<GTWAOF,GTWMutableAOF> aof;
@property (readwrite) GTWAOFPage* page;
@property (readwrite) NSInteger flags;
@property (readwrite) NSInteger keySize;
@property (readwrite) NSInteger valSize;
@property (readonly) NSInteger maxInternalPageKeys;
@property (readonly) NSInteger maxLeafPageKeys;

@property (readwrite) GTWAOFBTreeNode* parent;
@property (readwrite) GTWAOFBTreeNodeType type;

+ (NSInteger) maxInternalPageKeysForKeySize:(NSInteger)keySize;
+ (NSInteger) maxLeafPageKeysForKeySize:(NSInteger)keySize valueSize:(NSInteger)valSize;

+ (GTWAOFBTreeNode*) nodeWithPageID:(NSInteger)pageID parent:(GTWAOFBTreeNode*)parent fromAOF:(id<GTWAOF>)aof;
- (GTWAOFBTreeNode*) initWithPageID:(NSInteger)pageID parent:(GTWAOFBTreeNode*)parent fromAOF:(id<GTWAOF>)aof;
- (GTWAOFBTreeNode*) initWithPage:(GTWAOFPage*)page parent:(GTWAOFBTreeNode*)parent fromAOF:(id<GTWAOF>)aof;
- (NSInteger) pageID;
- (NSDate*) lastModified;
- (instancetype) parent;
- (BOOL) isRoot;
- (BOOL) isFull;
- (BOOL) isMinimum;
- (NSInteger) minInternalPageKeys;
- (NSInteger) minLeafPageKeys;
- (NSUInteger) nodeItemCount;
- (NSUInteger) subTreeItemCount;
- (NSArray*) allKeys;
- (NSArray*) allObjects;
- (NSArray*) allPairs;
- (NSArray*) childrenPageIDs;
- (NSData*) objectForKey:(NSData*)key;
- (NSData*) maxKey;
- (NSData*) minKey;
- (void)enumerateKeysAndPageIDsUsingBlock:(void (^)(NSData* key, NSInteger pageID, BOOL *stop))block;
- (void)enumerateKeysAndObjectsUsingBlock:(void (^)(NSData* key, NSData* obj, BOOL *stop))block;
- (void)enumerateKeysAndObjectsInRange:(NSRange) range usingBlock:(void (^)(NSData* key, NSData* obj, BOOL *stop))block;
- (GTWAOFBTreeNode*) childForKey:(NSData*)key;
- (GTWAOFBTreeNode*) fullestSibling;
- (BOOL) verify;
- (NSString*) longDescription;

@end

@interface GTWMutableAOFBTreeNode : GTWAOFBTreeNode

- (GTWMutableAOFBTreeNode*) initInternalWithParent:(GTWAOFBTreeNode*)parent isRoot:(BOOL)root keySize:(NSInteger)keySize valueSize:(NSInteger)valSize keys:(NSArray*)keys pageIDs:(NSArray*)objects updateContext:(GTWAOFUpdateContext*) ctx;
- (GTWMutableAOFBTreeNode*) initLeafWithParent:(GTWAOFBTreeNode*)parent isRoot:(BOOL)root keySize:(NSInteger)keySize valueSize:(NSInteger)valSize keys:(NSArray*)keys objects:(NSArray*)objects updateContext:(GTWAOFUpdateContext*) ctx;
+ (GTWMutableAOFBTreeNode*) rewriteInternalNode:(GTWAOFBTreeNode*)node replacingChild:(GTWAOFBTreeNode*)oldNode withNewNode:(GTWAOFBTreeNode*)newNode updateContext:(GTWAOFUpdateContext*) ctx;
+ (GTWMutableAOFBTreeNode*) rewriteInternalNode:(GTWAOFBTreeNode*)node replacingChildren:(NSArray*)oldchildren withNewNode:(GTWAOFBTreeNode*)newNode updateContext:(GTWAOFUpdateContext*) ctx;
+ (GTWMutableAOFBTreeNode*) rewriteLeafNode:(GTWAOFBTreeNode*)node addingObject:(NSData*)object forKey:(NSData*)key updateContext:(GTWAOFUpdateContext*) ctx;
+ (GTWMutableAOFBTreeNode*) rewriteLeafNode:(GTWAOFBTreeNode*)node replacingObject:(NSData*)object forKey:(NSData*)key updateContext:(GTWAOFUpdateContext*) ctx;
+ (NSArray*) splitLeafNode:(GTWAOFBTreeNode*)node addingObject:(NSData*)object forKey:(NSData*)key updateContext:(GTWAOFUpdateContext*) ctx;
+ (NSArray*) splitOrReplaceInternalNode:(GTWAOFBTreeNode*)node replacingChildID:(NSInteger)oldID withNewNodes:(NSArray*)newNodes updateContext:(GTWAOFUpdateContext*) ctx;

+ (GTWMutableAOFBTreeNode*) rewriteLeafNode:(GTWAOFBTreeNode*)node removingObjectForKey:(NSData*)key updateContext:(GTWAOFUpdateContext*) ctx;

@end
