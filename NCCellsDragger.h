//
//  NCCellsDragger.h
//  TableViewDragging
//
//  Created by Volkov Dmitry on 6/26/13.
//  Copyright (c) 2013 Volkov Dmitry. All rights reserved.
//

#import <Foundation/Foundation.h>

@class NCCellsDragger;

@protocol NCCellsDraggerDelegate <NSObject>

//@required

@optional

- (void) cellsDragger:(NCCellsDragger*) dragger willMoveCellAtIndexPath:(NSIndexPath*) fromIndexPath toIndexPath:(NSIndexPath*) toIndexPath;

- (void) cellsDragger:(NCCellsDragger*) dragger didMoveCellAtIndexPath:(NSIndexPath*) fromIndexPath toIndexPath:(NSIndexPath*) toIndexPath;
- (BOOL) cellsDragger:(NCCellsDragger*) dragger canMoveCellAtIndexPath:(NSIndexPath*) indexPath;
- (BOOL) cellsDragger:(NCCellsDragger*) dragger canMoveCellAtIndexPath:(NSIndexPath*) fromIndexPath toIndexPath:(NSIndexPath*) toIndexPath;

- (void) cellsDragger:(NCCellsDragger*) dragger willBeginDraggingCellAtIndexPath:(NSIndexPath*) indexPath;
- (void) cellsDragger:(NCCellsDragger*) dragger didBeginDraggingCellAtIndexPath:(NSIndexPath*) indexPath;
- (void) cellsDragger:(NCCellsDragger*) dragger willEndDraggingCellAtIndexPath:(NSIndexPath*) indexPath;
- (void) cellsDragger:(NCCellsDragger*) dragger didEndDraggingCellAtIndexPath:(NSIndexPath*) indexPath;

@end

@interface NCCellsDragger : NSObject

@property(nonatomic, readonly) UITableView* tableView;
@property(nonatomic, weak) id<NCCellsDraggerDelegate> delegate;

- (instancetype) initWithTableView:(UITableView*) tableView;
- (instancetype) initWithTableView:(UITableView*) tableView delegate:(id<NCCellsDraggerDelegate>) delegate;

- (void) removeFromCurrentTableView;

@end
