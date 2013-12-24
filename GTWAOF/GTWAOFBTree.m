//
//  GTWAOFBTree.m
//  GTWAOF
//
//  Created by Gregory Williams on 12/19/13.
//  Copyright (c) 2013 Gregory Todd Williams. All rights reserved.
//

#import "GTWAOFBTree.h"
#import "NSData+GTWCompare.h"
#import "GTWAOFUpdateContext.h"

static const NSInteger keySize  = 32;
static const NSInteger valSize  = 8;

@implementation GTWAOFBTree

- (GTWAOFBTree*) initFindingBTreeInAOF:(id<GTWAOF>)aof {
    if (self = [self init]) {
        _aof    = aof;
        _root   = nil;
        NSInteger pageID;
        NSInteger pageCount = [aof pageCount];
        for (pageID = pageCount-1; pageID >= 0; pageID--) {
            //            NSLog(@"Checking block %lu for dictionary head", pageID);
            GTWAOFPage* p   = [aof readPage:pageID];
            NSData* data    = p.data;
            char cookie[5] = { 0,0,0,0,0 };
            [data getBytes:cookie length:4];
            if (!strncmp(cookie, BTREE_INTERNAL_NODE_COOKIE, 4) || !strncmp(cookie, BTREE_LEAF_NODE_COOKIE, 4)) {
                _root   = [[GTWAOFBTreeNode alloc] initWithPage:p parent:nil fromAOF:aof];
                break;
            }
        }
        
        if (!_root) {
            NSLog(@"Failed to find a B+ Tree page in AOF file");
            return nil;
        }
    }
    return self;
}

- (GTWAOFBTree*) initWithRootPageID:(NSInteger)pageID fromAOF:(id<GTWAOF>)aof {
    if (self = [self init]) {
        _aof        = aof;
        _root       = [[GTWAOFBTreeNode alloc] initWithPageID:pageID parent:nil fromAOF:aof];
    }
    return self;
}

- (GTWAOFBTree*) initWithRootPage:(GTWAOFPage*)page fromAOF:(id<GTWAOF>)aof {
    if (self = [self init]) {
        _aof    = aof;
        _root       = [[GTWAOFBTreeNode alloc] initWithPage:page parent:nil fromAOF:aof];
    }
    return self;
}

- (GTWAOFBTreeNode*) root {
    return _root;
}

- (GTWAOFBTreeNode*) leafNodeForKey:(NSData*)key {
    GTWAOFBTreeNode* node   = _root;
    while (node.type == GTWAOFBTreeInternalNodeType) {
        node    = [node childForKey:key];
    }
    return node;
}

- (GTWAOFBTreeNode*) lcaNodeForKeysWithPrefix:(NSData*)prefix {
    GTWAOFBTreeNode* node   = _root;
//    NSLog(@"looking for lca of prefix %@", prefix);
    while (node.type == GTWAOFBTreeInternalNodeType) {
//        NSLog(@"checking page %llu", (unsigned long long)node.pageID);
        // node is an internal node. look for the first key which is <= the prefix
        NSArray* keys   = [node allKeys];
        NSInteger i;
        NSInteger foundAtIndex  = -1;
        NSInteger count = [keys count];
        for (i = 0; i < count; i++) {
            NSData* key = keys[i];
            NSComparisonResult r    = [prefix gtw_compare:key];
//            NSLog(@"%@ <=> %@ => %d", prefix, key, (int)r);
            if (r == NSOrderedAscending || r == NSOrderedSame) {
//                NSLog(@"child[%d] should contain keys matching prefix", (int)i);
                // key should be in this page
                foundAtIndex    = i;
                break;
            } else {
//                NSLog(@"child[%d] has too-low a maxKey; try the next child", (int)i);
            }
        }
        
        if (foundAtIndex >= 0) {
//            NSLog(@"child[%d] is the left-most that can contain keys matching the prefix", (int)foundAtIndex);
            // we found the right-most child that can contain keys matching the prefix.
            // now check to see if there is a right-sibling that could also contain keys matching the prefix
            // if so, then this is the LCA.
            // if not, then recurse to the child
            NSData* childMaxKey = keys[foundAtIndex];
            if ([childMaxKey gtw_hasPrefix:prefix]) {
                NSInteger siblingIndex  = foundAtIndex+1;
                NSArray* childrenIDs    = [node childrenPageIDs];
                NSNumber* number        = childrenIDs[siblingIndex];
                NSInteger childPageID   = [number integerValue];
                GTWAOFBTreeNode* sibling  = [[GTWAOFBTreeNode alloc] initWithPageID:childPageID parent:node fromAOF:_aof];
                NSData* siblingMinKey   = [sibling minKey];
    //            NSLog(@"sibling node has min-key: %@", siblingMinKey);
                if ([siblingMinKey gtw_hasPrefix:prefix]) {
    //                NSLog(@"... but right-sibling contains matching keys. parent (page %d) must be the LCA", (int)node.pageID);
                    return node;
                } else {
    //                NSLog(@"... right-sibling doesn't match prefix.");
                    node    = [node childForKey:prefix];
                }
            } else {
                node    = [node childForKey:prefix];
            }
//            } else {
//                NSComparisonResult r    = [prefix gtw_compare:siblingMinKey];
//                NSLog(@"%@ <=> %@ => %d", prefix, siblingMinKey, (int)r);
//                if (r == NSOrderedDescending) {
//                    NSLog(@"... right-sibling doesn't match prefix.");
//                    node    = sibling;
//                } else {
//                    NSLog(@"... but right-sibling also can contain matching keys. parent (page %d) must be the LCA", (int)node.pageID);
//                    return node;
//                }
//            }
        } else {
            // default to the max-page
//            NSLog(@"default to the max-page");
            node    = [node childForKey:prefix];
        }
    }
//    NSLog(@"reached leaf node: %@", node);
    return node;
}

- (void)enumerateKeysAndObjectsMatchingPrefix:(NSData*)prefix usingBlock:(void (^)(NSData*, NSData*, BOOL*))block {
    @autoreleasepool {
        GTWAOFBTreeNode* lca    = [self lcaNodeForKeysWithPrefix:prefix];
        if (lca) {
            if (lca.type == GTWAOFBTreeLeafNodeType) {
                __block BOOL seenMatchingKey = NO;
                [GTWAOFBTree enumerateKeysAndObjectsForNode:lca aof:_aof usingBlock:^(NSData *key, NSData *obj, BOOL *stop) {
                    if ([key gtw_hasPrefix:prefix]) {
                        seenMatchingKey = YES;
                        BOOL localStop   = NO;
                        block(key, obj, &localStop);
                        if (localStop)
                            *stop   = YES;
                    } else {
                        if (seenMatchingKey) {
//                            NSLog(@"stopped seeing matching keys");
                            *stop   = YES;
                        }
                    }
                }];
            } else {
                NSArray* keys       = [lca allKeys];
                NSArray* pageIDs    = [lca childrenPageIDs];
                NSInteger startOffset   = 0;
                for (startOffset = 0; startOffset < [keys count]; startOffset++) {
                    NSData* key = keys[startOffset];
                    if ([key gtw_hasPrefix:prefix]) {
                        break;
                    }
                }
                NSInteger offset;
                for (offset = startOffset; offset < [pageIDs count]; offset++) {
                    NSNumber* number    = pageIDs[offset];
                    NSInteger pageID    = [number integerValue];
                    GTWAOFBTreeNode* child  = [[GTWAOFBTreeNode alloc] initWithPageID:pageID parent:lca fromAOF:_aof];
                    __block BOOL seenMatchingKey    = NO;
                    __block BOOL localStop          = NO;
                    [GTWAOFBTree enumerateKeysAndObjectsForNode:child aof:_aof usingBlock:^(NSData *key, NSData *obj, BOOL *stop) {
                        if ([key gtw_hasPrefix:prefix]) {
                            seenMatchingKey = YES;
                            block(key, obj, &localStop);
                            if (localStop)
                                *stop   = YES;
                        } else {
                            if (seenMatchingKey) {
//                                NSLog(@"stopped seeing matching keys");
                                localStop   = YES;
                                *stop       = YES;
                            }
                        }
                    }];
                    if (localStop)
                        break;
                }
            }
        }
    }
}

- (void)enumerateKeysAndObjectsUsingBlock:(void (^)(NSData*, NSData*, BOOL*))block {
    GTWAOFBTreeNode* node   = _root;
    [GTWAOFBTree enumerateKeysAndObjectsForNode:node aof:_aof usingBlock:block];
}

+ (void)enumerateKeysAndObjectsForNode:(GTWAOFBTreeNode*)node aof:(id<GTWAOF>)aof usingBlock:(void (^)(NSData*, NSData*, BOOL*))block {
    if (node.type == GTWAOFBTreeLeafNodeType) {
        [node enumerateKeysAndObjectsUsingBlock:block];
    } else {
        [node enumerateKeysAndPageIDsUsingBlock:^(NSData *key, NSInteger pageID, BOOL *stop) {
            GTWAOFBTreeNode* child  = [[GTWAOFBTreeNode alloc] initWithPageID:pageID parent:node fromAOF:aof];
            NSLog(@"found b+ tree child node %@", child);
            __block BOOL localStop  = NO;
            [GTWAOFBTree enumerateKeysAndObjectsForNode:child aof:aof usingBlock:^(NSData *key, NSData *obj, BOOL *stop2) {
                block(key,obj,&localStop);
                if (localStop)
                    *stop2   = YES;
            }];
            if (localStop)
                *stop   = YES;
        }];
    }
}

static GTWAOFBTreeNode* copy_btree ( id<GTWAOF> aof, GTWAOFUpdateContext* ctx, GTWAOFBTreeNode* node ) {
    if (node.type == GTWAOFBTreeInternalNodeType) {
        NSArray* keys   = [node allKeys];
        NSArray* ids    = [node childrenPageIDs];
        NSMutableArray* childrenIDs = [NSMutableArray array];
        NSMutableArray* children    = [NSMutableArray array];
        for (NSNumber* number in ids) {
            GTWAOFBTreeNode* child  = [[GTWAOFBTreeNode alloc] initWithPageID:[number integerValue] parent:node fromAOF:aof];
            GTWAOFBTreeNode* newchild   = copy_btree(aof, ctx, child);
            [childrenIDs addObject:@(newchild.pageID)];
            [children addObject:newchild];
        }
        GTWAOFBTreeNode* newnode    = [[GTWMutableAOFBTreeNode alloc] initInternalWithParent:node.parent keySize:node.keySize valueSize:node.valSize keys:keys pageIDs:childrenIDs updateContext:ctx];
        for (GTWAOFBTreeNode* child in children) {
            [child setParent:newnode];
        }
        return newnode;
    } else {
        NSArray* keys   = [node allKeys];
        NSArray* vals   = [node allObjects];
        return [[GTWMutableAOFBTreeNode alloc] initLeafWithParent:node keySize:node.keySize valueSize:node.valSize keys:keys objects:vals updateContext:ctx];
    }
}

- (GTWAOFBTree*) rewriteWithUpdateContext:(GTWAOFUpdateContext*) ctx {
    GTWAOFBTreeNode* newroot    = copy_btree(_aof, ctx, _root);
    return [[GTWAOFBTree alloc] initWithRootPage:newroot.page fromAOF:ctx];
}

@end


@implementation GTWMutableAOFBTree

- (GTWMutableAOFBTree*) initFindingBTreeInAOF:(id<GTWAOF>)aof {
    if (self = [self init]) {
        _aof    = aof;
        _root   = nil;
        NSInteger pageID;
        NSInteger pageCount = [aof pageCount];
        for (pageID = pageCount-1; pageID >= 0; pageID--) {
            //            NSLog(@"Checking block %lu for dictionary head", pageID);
            GTWAOFPage* p   = [aof readPage:pageID];
            NSData* data    = p.data;
            char cookie[5] = { 0,0,0,0,0 };
            [data getBytes:cookie length:4];
            if (!strncmp(cookie, BTREE_INTERNAL_NODE_COOKIE, 4) || !strncmp(cookie, BTREE_LEAF_NODE_COOKIE, 4)) {
                _root   = [[GTWAOFBTreeNode alloc] initWithPage:p parent:nil fromAOF:aof];
                break;
            }
        }
        
        if (!_root) {
            __block GTWMutableAOFBTreeNode* root;
            [_aof updateWithBlock:^BOOL(GTWAOFUpdateContext *ctx) {
                root   = [[GTWMutableAOFBTreeNode alloc] initLeafWithParent:nil keySize:32 valueSize:0 keys:@[] objects:@[] updateContext:ctx];
                return YES;
            }];
            _root   = root;
        }
    }
    return self;
}

- (GTWMutableAOFBTree*) initEmptyBTreeWithKeySize:(NSInteger)keySize valueSize:(NSInteger)valSize updateContext:(GTWAOFUpdateContext*) ctx {
    if (self = [super init]) {
        _root   = [[GTWMutableAOFBTreeNode alloc] initInternalWithParent:nil keySize:keySize valueSize:valSize keys:@[] pageIDs:@[] updateContext:ctx];
    }
    return self;
}

- (GTWAOFBTreeNode*) rewriteToRootFromNewNode:(GTWAOFBTreeNode*)newnode replacingOldNode:(GTWAOFBTreeNode*)oldnode updateContext:(GTWAOFUpdateContext*)ctx {
    NSLog(@"rewriting to root from node %@", newnode);
    while (![newnode isRoot]) {
        GTWAOFBTreeNode* oldparent  = newnode.parent;
        GTWAOFBTreeNode* newparent  = [GTWMutableAOFBTreeNode rewriteInternalNode:oldparent replacingChildID:oldnode.pageID withNewNode:newnode updateContext:ctx];
        newnode = newparent;
        oldnode = oldparent;
    }
    return newnode;
}

- (BOOL) insertValue:(NSData*)value forKey:(NSData*)key updateContext:(GTWAOFUpdateContext*)ctx {
    GTWAOFBTreeNode* leaf   = [self leafNodeForKey:key];
    if (!leaf.isFull) {
        NSLog(@"leaf can hold new entry: %@", leaf);
        GTWAOFBTreeNode* newnode    = [GTWMutableAOFBTreeNode rewriteLeafNode:leaf addingObject:value forKey:key updateContext:ctx];
        _root   = [self rewriteToRootFromNewNode:newnode replacingOldNode:leaf updateContext:ctx];
    } else {
        NSLog(@"leaf is full; need to split: %@", leaf);
        GTWAOFBTreeNode* splitnode    = leaf;
        NSArray* pair   = [GTWMutableAOFBTreeNode splitLeafNode:splitnode addingObject:value forKey:key updateContext:ctx];
        NSLog(@"split leaf: %@", pair);
        while (![splitnode isRoot]) {
            GTWAOFBTreeNode* oldparent = splitnode.parent;
            NSArray* parentpair     = [GTWMutableAOFBTreeNode splitOrReplaceInternalNode:oldparent replacingChildID:splitnode.pageID withNewNodes:pair updateContext:ctx];
            if ([parentpair count] == 1) {
                // the parent had room for the new pages. rewrite to root and return.
                GTWAOFBTreeNode* newnode = parentpair[0];
                GTWAOFBTreeNode* oldnode = oldparent;
                _root       = [self rewriteToRootFromNewNode:newnode replacingOldNode:oldnode updateContext:ctx];
                return YES;
            } else {
                splitnode   = oldparent;
                pair        = parentpair;
            }
        }
        // splitting the root
        GTWAOFBTreeNode* lhs    = pair[0];
        GTWAOFBTreeNode* rhs    = pair[1];
        NSArray* rootKeys       = @[[lhs maxKey]];
        NSArray* rootPageIDs    = @[@(lhs.pageID), @(rhs.pageID)];
        _root   = [[GTWMutableAOFBTreeNode alloc] initInternalWithParent:nil keySize:splitnode.keySize valueSize:splitnode.valSize keys:rootKeys pageIDs:rootPageIDs updateContext:ctx];
        
    }
    
    return YES;
}

- (BOOL) removeValueForKey:(NSData*)key updateContext:(GTWAOFUpdateContext*) ctx {
    // TODO: implement
    return NO;
}


@end



/**
 - create new root node from old root node (adding one new child pageID)
 - split root node into two new internal nodes (adding one new and replacing one old child pageIDs) and create new root node
 - create new internal node from old internal node (adding one new child pageID)
 - split internal node into two new internal nodes (adding one new and replacing one old child pageIDs)
 - create new leaf node from old leaf node (adding one new object value)
 
 trivial case where root is a leaf:
 - split root node into two new leaf nodes (adding one new object value) and create new root node
 
 */

