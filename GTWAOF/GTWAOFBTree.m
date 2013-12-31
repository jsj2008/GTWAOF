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
    assert(aof);
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
    assert(aof);
    if (self = [self init]) {
        _aof        = aof;
        _root       = [GTWAOFBTreeNode nodeWithPageID:pageID parent:nil fromAOF:aof];
    }
    return self;
}

- (GTWAOFBTree*) initWithRootPage:(GTWAOFPage*)page fromAOF:(id<GTWAOF>)aof {
    assert(aof);
    if (self = [self init]) {
        _aof    = aof;
        _root       = [[GTWAOFBTreeNode alloc] initWithPage:page parent:nil fromAOF:aof];
    }
    return self;
}

- (NSString*) pageType {
    return @"BTRE";
}

- (NSInteger) pageID {
    return [self.root pageID];
}

- (NSInteger) keySize {
    return [self.root keySize];
}

- (NSInteger) valSize {
    return [self.root valSize];
}

- (GTWAOFBTreeNode*) root {
    return _root;
}

- (id<GTWAOF>) aof {
    return _aof;
}

- (void) setAof:(id<GTWAOF>)aof {
    assert(aof);
    _aof    = aof;
}

- (GTWAOFBTreeNode*) leafNodeForKey:(NSData*)key {
    GTWAOFBTreeNode* node   = _root;
    while (node.type == GTWAOFBTreeInternalNodeType) {
        GTWAOFBTreeNode* newnode    = [node childForKey:key];
        newnode.parent              = node;
        node                        = newnode;
    }
    return node;
}

- (NSInteger) count {
    __block NSInteger count = 0;
//    NSLog(@"> count");
    [self enumerateKeysAndObjectsUsingBlock:^(NSData *key, NSData *obj, BOOL *stop) {
        count++;
    }];
//    NSLog(@"< count");
    return count;
}

- (GTWAOFBTreeNode*) lcaNodeForKeysWithPrefix:(NSData*)prefix {
    assert(_aof);
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
                GTWAOFBTreeNode* sibling  = [GTWAOFBTreeNode nodeWithPageID:childPageID parent:node fromAOF:_aof];
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

- (NSData*) objectForKey:(NSData*)key {
    assert(_aof);
    __block NSData* data;
    [self enumerateKeysAndObjectsMatchingPrefix:key usingBlock:^(NSData *k, NSData *obj, BOOL *stop) {
        if ([key isEqual:k]) {
            data    = obj;
            *stop   = YES;
        }
    }];
    return data;
}

- (void)enumerateKeysAndObjectsMatchingPrefix:(NSData*)prefix usingBlock:(void (^)(NSData*, NSData*, BOOL*))block {
    assert(_aof);
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
                    GTWAOFBTreeNode* child  = [GTWAOFBTreeNode nodeWithPageID:pageID parent:lca fromAOF:_aof];
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
    [GTWAOFBTree enumerateKeysAndObjectsForNode:node aof:_root.aof usingBlock:block];
}

+ (void)enumerateKeysAndObjectsForNode:(GTWAOFBTreeNode*)node aof:(id<GTWAOF>)aof usingBlock:(void (^)(NSData*, NSData*, BOOL*))block {
    if (node.type == GTWAOFBTreeLeafNodeType) {
//        NSLog(@"-> enumerating leaf %@", node);
        [node enumerateKeysAndObjectsUsingBlock:block];
    } else {
//        NSLog(@"-> enumerating internal %@", node);
        [node enumerateKeysAndPageIDsUsingBlock:^(NSData *key, NSInteger pageID, BOOL *stop) {
            GTWAOFBTreeNode* child  = [GTWAOFBTreeNode nodeWithPageID:pageID parent:node fromAOF:aof];
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

static GTWAOFBTreeNode* copy_btree ( id<GTWAOF> aof, GTWAOFUpdateContext* ctx, GTWAOFBTreeNode* node ) {
    if (node.type == GTWAOFBTreeInternalNodeType) {
        NSArray* keys   = [node allKeys];
        NSArray* ids    = [node childrenPageIDs];
        NSMutableArray* childrenIDs = [NSMutableArray array];
        NSMutableArray* children    = [NSMutableArray array];
        for (NSNumber* number in ids) {
            GTWAOFBTreeNode* child  = [GTWAOFBTreeNode nodeWithPageID:[number integerValue] parent:node fromAOF:aof];
            GTWAOFBTreeNode* newchild   = copy_btree(aof, ctx, child);
            [childrenIDs addObject:@(newchild.pageID)];
            [children addObject:newchild];
        }
        GTWAOFBTreeNode* newnode    = [[GTWMutableAOFBTreeNode alloc] initInternalWithParent:node.parent isRoot:(node.parent?YES:NO) keySize:node.keySize valueSize:node.valSize keys:keys pageIDs:childrenIDs updateContext:ctx];
        for (GTWAOFBTreeNode* child in children) {
            [child setParent:newnode];
        }
        return newnode;
    } else {
        NSArray* keys   = [node allKeys];
        NSArray* vals   = [node allObjects];
        return [[GTWMutableAOFBTreeNode alloc] initLeafWithParent:node isRoot:(node?YES:NO) keySize:node.keySize valueSize:node.valSize keys:keys objects:vals updateContext:ctx];
    }
}

- (GTWAOFBTree*) rewriteWithUpdateContext:(GTWAOFUpdateContext*) ctx {
    GTWAOFBTreeNode* newroot    = copy_btree(_aof, ctx, _root);
    GTWAOFBTree* b  = [[GTWAOFBTree alloc] initWithRootPage:newroot.page fromAOF:ctx];
    [ctx registerPageObject:b];
    return b;
}

@end


@implementation GTWMutableAOFBTree

- (GTWMutableAOFBTree*) initFindingBTreeInAOF:(id<GTWAOF>)aof {
    assert(aof);
    if (self = [self init]) {
        self.aof    = aof;
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
            [self.aof updateWithBlock:^BOOL(GTWAOFUpdateContext *ctx) {
                root   = [[GTWMutableAOFBTreeNode alloc] initLeafWithParent:nil isRoot:YES keySize:32 valueSize:0 keys:@[] objects:@[] updateContext:ctx];
                return YES;
            }];
            _root   = root;
        }
    }
    return self;
}

- (GTWMutableAOFBTree*) initEmptyBTreeWithKeySize:(NSInteger)keySize valueSize:(NSInteger)valSize updateContext:(GTWAOFUpdateContext*) ctx {
    assert(ctx);
    if (self = [super init]) {
        self.aof    = ctx;
        [ctx registerPageObject:self];
        _root   = [[GTWMutableAOFBTreeNode alloc] initLeafWithParent:nil isRoot:YES keySize:keySize valueSize:valSize keys:@[] objects:@[] updateContext:ctx];
//        _root   = [[GTWMutableAOFBTreeNode alloc] initInternalWithParent:nil keySize:keySize valueSize:valSize keys:@[] pageIDs:@[] updateContext:ctx];
    }
    return self;
}

- (NSArray*) nodeArraysWithEnumerator:(NSEnumerator*)enumerator withMininumCount:(NSInteger)minCount maximumCount:(NSInteger)maxCount {
    NSArray* items          = [enumerator allObjects];
    NSMutableArray* data    = [NSMutableArray array];
    NSMutableArray* array   = [NSMutableArray array];
    for (id item in items) {
        [data addObject:item];
        if ([data count] >= maxCount) {
            [array addObject:data];
            data    = [NSMutableArray array];
        }
    }
    if ([data count]) {
        [array addObject:data];
        data    = [NSMutableArray array];
    }
    
    if ([array count] > 1) {
        NSArray* lastLeaf   = [array lastObject];
        if ([lastLeaf count] < minCount) {
            [array removeLastObject];
            NSArray* penultimateLeaf    = [array lastObject];
            [array removeLastObject];
            // Redistribute data between last two leaves
            NSMutableArray* pairs   = [NSMutableArray arrayWithArray:penultimateLeaf];
            [pairs addObjectsFromArray:lastLeaf];
            
            NSInteger count = [pairs count];
            NSInteger mid   = count/2;
            NSRange lrange  = NSMakeRange(0, mid);
            NSRange rrange  = NSMakeRange(mid, count-mid);
            
            NSArray* lpairs = [pairs subarrayWithRange:lrange];
            NSArray* rpairs = [pairs subarrayWithRange:rrange];
            
            [array addObject:lpairs];
            [array addObject:rpairs];
        }
    }
    return array;
}

- (GTWMutableAOFBTree*) initBTreeWithKeySize:(NSInteger)keySize valueSize:(NSInteger)valSize pairEnumerator:(NSEnumerator*)enumerator updateContext:(GTWAOFUpdateContext*) ctx {
    NSInteger fillLeaf  = [GTWAOFBTreeNode maxLeafPageKeysForKeySize:keySize valueSize:valSize];
    NSInteger minLeaf   = fillLeaf/2;
    NSInteger fillInt   = [GTWAOFBTreeNode maxInternalPageKeysForKeySize:keySize];
    NSInteger minInt    = fillInt/2;
//    NSLog(@"internal pages: %lld", (long long)fillInt);
//    NSLog(@"leaf pages: %lld", (long long)fillLeaf);
    
    NSArray* array  = [self nodeArraysWithEnumerator:enumerator withMininumCount:minLeaf maximumCount:fillLeaf];
    if ([array count]) {
        NSMutableArray* pages   = [NSMutableArray array];
        NSInteger i;
        BOOL root = ([array count] == 1) ? YES : NO;
        for (i = 0; i < [array count]; i++) {
            NSArray* leaf   = array[i];
            NSMutableArray* keys    = [NSMutableArray array];
            NSMutableArray* vals    = [NSMutableArray array];
            for (NSArray* pair in leaf) {
                [keys addObject:pair[0]];
                [vals addObject:pair[1]];
            }
            GTWMutableAOFBTreeNode* node    = [[GTWMutableAOFBTreeNode alloc] initLeafWithParent:nil isRoot:root keySize:keySize valueSize:valSize keys:keys objects:vals updateContext:ctx];
            NSLog(@"Leaf node (root=%d) %lld: %lld data pairs", root, (long long)node.pageID, (long long)[node count]);
            [pages addObject:node];
        }
        
        while ([pages count] > 1) {
            array   = [self nodeArraysWithEnumerator:[pages objectEnumerator] withMininumCount:minInt maximumCount:fillInt];
            pages   = [NSMutableArray array];
            BOOL root = ([array count] == 1) ? YES : NO;
            for (NSArray* leaf in array) {
                NSMutableArray* keys    = [NSMutableArray array];
                NSMutableArray* vals    = [NSMutableArray array];
                for (i = 0; i < [leaf count]; i++) {
                    GTWMutableAOFBTreeNode* child   = leaf[i];
                    NSData* maxKey  = [child maxKey];
                    NSInteger pageID    = child.pageID;
                    [keys addObject:maxKey];
                    [vals addObject:@(pageID)];
                }
                [keys removeLastObject];
                GTWMutableAOFBTreeNode* node    = [[GTWMutableAOFBTreeNode alloc] initInternalWithParent:nil isRoot:root keySize:keySize valueSize:valSize keys:keys pageIDs:vals updateContext:ctx];
                NSLog(@"Internal node (root=%d) %lld: %lld children", root, (long long)node.pageID, (long long)[[node childrenPageIDs] count]);
                [pages addObject:node];
                NSLog(@"-------");
            }
        }
        return pages[0];
    } else {
        return [self initEmptyBTreeWithKeySize:keySize valueSize:valSize updateContext:ctx];
    }
}

- (GTWAOFBTreeNode*) rewriteToRootFromNewNode:(GTWAOFBTreeNode*)newnode replacingOldNode:(GTWAOFBTreeNode*)oldnode updateContext:(GTWAOFUpdateContext*)ctx {
    assert(ctx);
    assert(newnode);
//    NSLog(@"rewriting to root from node %@", newnode);
    while (![newnode isRoot]) {
//        NSLog(@"-> rewrite loop");
        GTWAOFBTreeNode* oldparent  = oldnode.parent;
        assert(oldparent);
        GTWAOFBTreeNode* newparent  = [GTWMutableAOFBTreeNode rewriteInternalNode:oldparent replacingChildID:oldnode.pageID withNewNode:newnode updateContext:ctx];
        newnode.parent  = newparent;
        newnode = newparent;
        oldnode = oldparent;
        assert(newnode);
        assert(oldnode);
    }
//    NSLog(@"new root: %@", newnode);
    return newnode;
}

- (BOOL) insertValue:(NSData*)value forKey:(NSData*)key updateContext:(GTWAOFUpdateContext*)ctx {
//    NSLog(@"insertValue: -------------------------------- root: %@", _root);
#if DEBUG
    NSInteger count = [self count];
#endif
    GTWAOFBTreeNode* leaf   = [self leafNodeForKey:key];
    NSData* object  = [leaf objectForKey:key];
    if (object) {
//        NSLog(@"duplicate insert attempted: %@ -> %@", key, value);
        return NO;
    }
    
    
    if (!leaf.isFull) {
//        NSLog(@"leaf can hold new entry: %@", leaf);
        NSInteger leafcount = [leaf count];
        GTWAOFBTreeNode* newnode    = [GTWMutableAOFBTreeNode rewriteLeafNode:leaf addingObject:value forKey:key updateContext:ctx];
        assert((leafcount+1) == [newnode count]);
//        NSLog(@"going to rewrite:\n\tfrom: %@\n\troot: %@", newnode, _root);
        _root   = [self rewriteToRootFromNewNode:newnode replacingOldNode:leaf updateContext:ctx];
    } else {
//        NSLog(@"leaf is full; need to split: %@", leaf);
        GTWAOFBTreeNode* splitnode    = leaf;
        NSArray* pair   = [GTWMutableAOFBTreeNode splitLeafNode:splitnode addingObject:value forKey:key updateContext:ctx];
//        NSLog(@"split leaf: %@", pair);
        while (![splitnode isRoot]) {
            GTWAOFBTreeNode* oldparent = splitnode.parent;
            NSArray* parentpair     = [GTWMutableAOFBTreeNode splitOrReplaceInternalNode:oldparent replacingChildID:splitnode.pageID withNewNodes:pair updateContext:ctx];
            if ([parentpair count] == 1) {
                // the parent had room for the new pages. rewrite to root and return.
//                NSLog(@"the parent had room for the new pages. rewrite to root and return");
                GTWAOFBTreeNode* newnode = parentpair[0];
                GTWAOFBTreeNode* oldnode = oldparent;
                _root       = [self rewriteToRootFromNewNode:newnode replacingOldNode:oldnode updateContext:ctx];
                return YES;
            } else {
//                NSLog(@"the parent does NOT have room for the new pages. split it, too");
                splitnode   = oldparent;
                pair        = parentpair;
            }
        }
        // splitting the root
//        NSLog(@"splitting the root");
        GTWAOFBTreeNode* lhs    = pair[0];
        GTWAOFBTreeNode* rhs    = pair[1];
        NSArray* rootKeys       = @[[lhs maxKey]];
        NSArray* rootPageIDs    = @[@(lhs.pageID), @(rhs.pageID)];
//        NSLog(@"%@ %@", rootKeys, rootPageIDs);
        _root   = [[GTWMutableAOFBTreeNode alloc] initInternalWithParent:nil isRoot:YES keySize:splitnode.keySize valueSize:splitnode.valSize keys:rootKeys pageIDs:rootPageIDs updateContext:ctx];
//        NSLog(@"new root: %@", _root);
    }

#if DEBUG
    NSInteger newcount = [self count];
    if ((count+1) != newcount) {
        NSLog(@"BTree insertValue:forKey: has bad count after insert %lld with starting count %lld", (long long)newcount, (long long)count);
        assert(0);
    }
#endif

    return YES;
}

- (BOOL) removeValueForKey:(NSData*)key updateContext:(GTWAOFUpdateContext*) ctx {
    GTWAOFBTreeNode* leaf   = [self leafNodeForKey:key];
    NSData* value   = [leaf objectForKey:key];
    if (!value)
        return NO;
    if (!leaf.isMinimum) {
        NSLog(@"Leaf won't underflow (%lld pairs); removing...", (long long)[leaf count]);
        GTWAOFBTreeNode* newnode    = [GTWMutableAOFBTreeNode rewriteLeafNode:leaf removingObjectForKey:key updateContext:ctx];
        _root   = [self rewriteToRootFromNewNode:newnode replacingOldNode:leaf updateContext:ctx];
    } else if (leaf.isRoot) {
        NSLog(@"Leaf would underflow (%lld pairs), but it is the root; special case removing...", (long long)[leaf count]);
        GTWAOFBTreeNode* newnode    = [GTWMutableAOFBTreeNode rewriteLeafNode:leaf removingObjectForKey:key updateContext:ctx];
        _root   = [self rewriteToRootFromNewNode:newnode replacingOldNode:leaf updateContext:ctx];
    } else {
        NSLog(@"Leaf would underflow (%lld pairs); trying to combine with sibling", (long long)[leaf count]);
        // find a sibling
        GTWAOFBTreeNode* sibling    = [leaf fullestSibling];
        NSLog(@"fullest sibling: %@", sibling);
        NSInteger combined  = [leaf count] + [sibling count];
        if (combined >= [leaf minLeafPageKeys]) {
            // if the sibling and this node have enough pairs to not underflow, redistribute the pairs, write a new leaf node from the siblings' data, rewrite the parent, and rewrite the path from the parent to the root
            NSLog(@"-> can combine with sibling (%lld total pairs)", (long long)combined);
            NSMutableArray* array   = [NSMutableArray array];
            NSMutableArray* keys    = [NSMutableArray array];
            if ([leaf.maxKey gtw_compare:sibling.maxKey] == NSOrderedAscending) {
                [array addObjectsFromArray:[leaf allObjects]];
                [keys addObjectsFromArray:[leaf allKeys]];
                [array addObjectsFromArray:[sibling allObjects]];
                [keys addObjectsFromArray:[sibling allKeys]];
            } else {
                [array addObjectsFromArray:[sibling allObjects]];
                [keys addObjectsFromArray:[sibling allKeys]];
                [array addObjectsFromArray:[leaf allObjects]];
                [keys addObjectsFromArray:[leaf allKeys]];
            }

            NSInteger keycount      = [keys count];
            for (NSInteger i = 0; i < keycount; i++) {
                if ([keys[i] gtw_compare:key] == NSOrderedSame) {
                    [keys removeObjectAtIndex:i];
                    [array removeObjectAtIndex:i];
                    break;
                }
            }
            
            GTWAOFBTreeNode* newleaf    = [[GTWMutableAOFBTreeNode alloc] initLeafWithParent:leaf.parent isRoot:NO keySize:leaf.keySize valueSize:leaf.valSize keys:keys objects:array updateContext:ctx];
            GTWAOFBTreeNode* oldparent  = leaf.parent;
            if (!oldparent.isMinimum) {
                GTWAOFBTreeNode* newparent  = [GTWMutableAOFBTreeNode rewriteInternalNode:oldparent replacingChildren:@[leaf, sibling] withNewNode:newleaf updateContext:ctx];
                _root       = [self rewriteToRootFromNewNode:newparent replacingOldNode:oldparent updateContext:ctx];
            } else if (oldparent.isRoot) {
                NSLog(@"parent would underflow, but it is the root; special case removing...");
                GTWAOFBTreeNode* newparent  = [GTWMutableAOFBTreeNode rewriteInternalNode:oldparent replacingChildren:@[leaf, sibling] withNewNode:newleaf updateContext:ctx];
                _root       = newparent;
            } else {
                NSLog(@"parent would underflow: %@", oldparent);
                assert(0);
            }
        } else {
            NSLog(@"-> cannot combine with sibling (%lld total pairs)", (long long)combined);
            assert(0);
        }
        
        
        // else (the sibling and this node are both minimal)
            // mergenode = merge the siblings
            // mergeparent = parent of siblings
//    LOOP:
            // if mergeparent is minimal AND mergeparent is NOT root
                // find a parentsibling of mergeparent
                // if the parentsibling and mergeparent have enough children to not underflow, redistribute the children, rewrite the grandparent, and rewrite the path from the grandparent to the root
                // else (the mergeparent and parentsibling are both minimal)
                    // mergeparent = parent of mergeparent
                    // mergenode = merge mergeparent and parentsibling
                    // goto LOOP
                // end
            // else
                // replace siblings in mergeparent with mergenode
                // rewrite the path from rewritten mergeparent to root
            // end
        // end
        
        return YES;
        assert(0);
        
        GTWAOFBTreeNode* mergenode    = leaf;
        
        
        
        NSArray* pair   = [GTWMutableAOFBTreeNode splitLeafNode:mergenode addingObject:value forKey:key updateContext:ctx];
        //        NSLog(@"split leaf: %@", pair);
        while (![mergenode isRoot]) {
            GTWAOFBTreeNode* oldparent = mergenode.parent;
            NSArray* parentpair     = [GTWMutableAOFBTreeNode splitOrReplaceInternalNode:oldparent replacingChildID:mergenode.pageID withNewNodes:pair updateContext:ctx];
            if ([parentpair count] == 1) {
                // the parent had room for the new pages. rewrite to root and return.
                GTWAOFBTreeNode* newnode = parentpair[0];
                GTWAOFBTreeNode* oldnode = oldparent;
                _root       = [self rewriteToRootFromNewNode:newnode replacingOldNode:oldnode updateContext:ctx];
                return YES;
            } else {
                mergenode   = oldparent;
                pair        = parentpair;
            }
        }
        // splitting the root
        GTWAOFBTreeNode* lhs    = pair[0];
        GTWAOFBTreeNode* rhs    = pair[1];
        NSArray* rootKeys       = @[[lhs maxKey]];
        NSArray* rootPageIDs    = @[@(lhs.pageID), @(rhs.pageID)];
        _root   = [[GTWMutableAOFBTreeNode alloc] initInternalWithParent:nil isRoot:YES keySize:mergenode.keySize valueSize:mergenode.valSize keys:rootKeys pageIDs:rootPageIDs updateContext:ctx];
    }
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

