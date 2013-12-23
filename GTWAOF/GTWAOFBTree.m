//
//  GTWAOFBTree.m
//  GTWAOF
//
//  Created by Gregory Williams on 12/19/13.
//  Copyright (c) 2013 Gregory Todd Williams. All rights reserved.
//

#import "GTWAOFBTree.h"
#import "NSData+GTWCompare.h"

static const NSInteger keySize  = 32;
static const NSInteger valSize  = 8;

@implementation GTWAOFBTree

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
//            NSLog(@"found b+ tree child node %@", child);
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

@end


@implementation GTWMutableAOFBTree

- (GTWMutableAOFBTree*) initEmptyBTreeWithKeySize:(NSInteger)keySize valueSize:(NSInteger)valSize updateContext:(GTWAOFUpdateContext*) ctx {
    if (self = [super init]) {
        _root   = [[GTWMutableAOFBTreeNode alloc] initInternalWithParent:nil keySize:keySize valueSize:valSize keys:@[] pageIDs:@[] updateContext:ctx];
    }
    return self;
}

- (BOOL) insertValue:(NSData*)value forKey:(NSData*)key updateContext:(GTWAOFUpdateContext*) ctx {
    // TODO: implement
    
    GTWAOFBTreeNode* leaf   = [self leafNodeForKey:key];
    if (!leaf.isFull) {
        GTWAOFBTreeNode* oldnode    = leaf;
        GTWAOFBTreeNode* newnode    = [GTWMutableAOFBTreeNode rewriteLeafNode:oldnode addingObject:value forKey:key updateContext:ctx];
        while (![newnode isRoot]) {
            GTWAOFBTreeNode* oldparent  = newnode.parent;
            GTWAOFBTreeNode* newparent  = [GTWMutableAOFBTreeNode rewriteInternalNode:oldparent replacingChildID:oldnode.pageID withNewNode:newnode updateContext:ctx];
            newnode = newparent;
            oldnode = oldparent;
        }
        
        _root   = newnode;
    }
    
    
    /*
     Find leaf for value
     If leaf is not full
        create new node with the old leaf data and the new element
        rewrite path to root with new pointers
     else
        create two new nodes, and distribute leaf data and new element between them
        if parent is not full
            replace leaf pointer in parent with two new node pointers
            done
        else
            recurse, splitting parent
        end
     end
     
     if root needs a split, create a new root
     */
    
    
    
    
    
    return NO;
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

