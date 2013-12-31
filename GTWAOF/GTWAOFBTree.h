//
//  GTWAOFBTree.h
//  GTWAOF
//
//  Created by Gregory Williams on 12/19/13.
//  Copyright (c) 2013 Gregory Todd Williams. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "GTWAOFBTreeNode.h"

@interface GTWAOFBTree : NSObject<GTWAOFBackedObject> {
    GTWAOFBTreeNode* _root;
    id<GTWAOF> _aof;
}

@property (retain,readwrite) id<GTWAOF> aof;

- (GTWAOFBTree*) initFindingBTreeInAOF:(id<GTWAOF>)aof;
- (GTWAOFBTree*) initWithRootPageID:(NSInteger)pageID fromAOF:(id<GTWAOF>)aof;
- (GTWAOFBTree*) initWithRootPage:(GTWAOFPage*)page fromAOF:(id<GTWAOF>)aof;

- (NSInteger) keySize;
- (NSInteger) valSize;
- (NSInteger) count;
- (GTWAOFBTreeNode*) root;
- (GTWAOFBTreeNode*) leafNodeForKey:(NSData*)key;
- (GTWAOFBTreeNode*) lcaNodeForKeysWithPrefix:(NSData*)prefix;
- (void)enumerateKeysAndObjectsUsingBlock:(void (^)(NSData* key, NSData* obj, BOOL *stop))block;
- (void)enumerateKeysAndObjectsMatchingPrefix:(NSData*)prefix usingBlock:(void (^)(NSData* key, NSData* obj, BOOL *stop))block;
- (NSData*) objectForKey:(NSData*)key;
- (GTWAOFBTree*) rewriteWithUpdateContext:(GTWAOFUpdateContext*) ctx;

@end

@interface GTWMutableAOFBTree : GTWAOFBTree

- (GTWMutableAOFBTree*) initEmptyBTreeWithKeySize:(NSInteger)keySize valueSize:(NSInteger)valSize updateContext:(GTWAOFUpdateContext*) ctx;
- (GTWMutableAOFBTree*) initBTreeWithKeySize:(NSInteger)keySize valueSize:(NSInteger)valSize pairEnumerator:(NSEnumerator*)enumerator updateContext:(GTWAOFUpdateContext*) ctx;
- (BOOL) insertValue:(NSData*)value forKey:(NSData*)key updateContext:(GTWAOFUpdateContext*) ctx;
- (BOOL) removeValueForKey:(NSData*)key updateContext:(GTWAOFUpdateContext*) ctx;

@end
