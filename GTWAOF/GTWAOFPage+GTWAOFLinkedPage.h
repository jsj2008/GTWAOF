//
//  GTWAOFPage+GTWAOFLinkedPage.h
//  GTWAOF
//
//  Created by Gregory Williams on 12/9/13.
//  Copyright (c) 2013 Gregory Todd Williams. All rights reserved.
//

#import "GTWAOFPage.h"

@interface GTWAOFPage (GTWAOFLinkedPage)

/**
 4  cookie          [RDCT]
 4  padding
 8  timestamp       (seconds since epoch)
 8  prev_page_id
 */

- (NSDate*) lastModified;
- (NSInteger) previousPageID;

@end
