//
//  GTWAOFPlugin.m
//  GTWAOF
//
//  Created by Gregory Williams on 12/29/13.
//  Copyright (c) 2013 Gregory Todd Williams. All rights reserved.
//

#import "GTWAOFPlugin.h"

@implementation GTWAOFPlugin

+ (unsigned)interfaceVersion {
    return 0;
}

+ (NSSet*) implementedProtocols {
    return [NSSet set];
}

+ (NSDictionary*) classesImplementingProtocols {
    NSSet* qset     = [GTWAOFQuadStore implementedProtocols];
    NSSet* mqset    = [GTWMutableAOFQuadStore implementedProtocols];
    return @{
             (id)[GTWAOFQuadStore class]: qset,
             (id)[GTWMutableAOFQuadStore class]: mqset
             };
}

@end
