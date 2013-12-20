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
- (void)enumerateKeysAndObjectsUsingBlock:(void (^)(NSData* key, NSData* obj, BOOL *stop))block;

@end

@interface GTWMutableAOFBTree : GTWAOFBTree

@end
