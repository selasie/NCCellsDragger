//
//  NCCellsDragger.m
//  TableViewDragging
//
//  Created by Volkov Dmitry on 6/26/13.
//  Copyright (c) 2013 Volkov Dmitry. All rights reserved.
//

#import "NCCellsDragger.h"
#import <objc/runtime.h>

static float kScrollingInset = 50.;
static float kScrollingFPS = 1. / 30.;
static float kScrollingPerTick = 5.;
NSString* kDraggingDirectionKey = @"DraggingDirection";


typedef NS_ENUM(NSUInteger, NCDraggingDirection)
{
    NCDraggingDirectionUp,
    NCDraggingDirectionDown,
    NCDraggingDirectionUndefined
};

#pragma mark - UITableView associated NCCellsDragger

//store associated CellsDragger inside UITableView
static void* kCellsDraggerKey = &kCellsDraggerKey;

@interface UITableView (NCCellsDraggerContaining)

@property(nonatomic,strong) NCCellsDragger* cellsDragger;

@end

@implementation UITableView (NCCellsDraggerContaining)

- (void) setCellsDragger:(NCCellsDragger *)cellsDragger
{
    objc_setAssociatedObject(self, kCellsDraggerKey, cellsDragger, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (NCCellsDragger*) cellsDragger
{
    return objc_getAssociatedObject(self, kCellsDraggerKey);
}

@end

#pragma mark - UITableViewCell content rasterizing

@interface UITableViewCell (ContentRasterization)

- (UIImage*) rasterizedContent;

@end

@implementation UITableViewCell (ContentRasterization)

- (UIImage*) rasterizedContent
{
    CGSize size = self.bounds.size;
    UIGraphicsBeginImageContextWithOptions(size, self.isOpaque, 0);
    [self.layer renderInContext:UIGraphicsGetCurrentContext()];
    UIImage* rasterizedContent = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return rasterizedContent;
}

@end


#pragma mark - NCCellsDragger implementation


@interface NCCellsDragger ()<UIGestureRecognizerDelegate>
{
    UIPanGestureRecognizer* _panGestureRecognizer;
    UILongPressGestureRecognizer* _longPressGestureRecognizer;
    __weak UITableView* _tableView;//declare tableView as weak
    NSTimer* _scrollingTimer;
}

@property(nonatomic, strong) UIView* currentView;
@property(nonatomic) CGPoint currentCenter;
@property(nonatomic, strong) NSIndexPath* draggedCellIndexPath;
@property(nonatomic, strong) UITableViewCell* draggedCell;//track current cell to restore its hidden property when items are reordered
@property(nonatomic) CGPoint previousCenter;
@property(nonatomic, strong) NSIndexPath* lastSwappedIndexPath;
@property(nonatomic) NCDraggingDirection lastDraggingDirection;
@property(nonatomic) CGPoint lastPanTranslation;

@end

@implementation NCCellsDragger

- (void) dealloc
{
    [self removeFromCurrentTableView];
}

- (instancetype) initWithTableView:(UITableView*) tableView delegate:(id<NCCellsDraggerDelegate>) delegate
{
    self = [super init];
    self.delegate = delegate;
    _tableView = tableView;
    _tableView.cellsDragger = self;
    _isEnabled = YES;
    [self setup];
    return self;
}

- (instancetype) initWithTableView:(UITableView*) tableView
{
    return [self initWithTableView:tableView delegate:nil];
}

- (void) removeFromCurrentTableView
{
    [self cleanup];
    _tableView.cellsDragger = nil;
    [_tableView removeGestureRecognizer:_longPressGestureRecognizer];
    [_tableView removeGestureRecognizer:_panGestureRecognizer];
}

- (void) setup
{
    _longPressGestureRecognizer = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPressRecognizer:)];
    _longPressGestureRecognizer.minimumPressDuration = 0.2;
    _longPressGestureRecognizer.delegate = self;
    _longPressGestureRecognizer.delaysTouchesBegan = YES;
    _panGestureRecognizer = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePanRecognizer:)];
    _panGestureRecognizer.delegate = self;
    
    [_tableView addGestureRecognizer:_longPressGestureRecognizer];
    [_tableView addGestureRecognizer:_panGestureRecognizer];
    
}

- (void) setIsEnabled:(BOOL)isEnabled
{
    _isEnabled = isEnabled;
    _longPressGestureRecognizer.enabled = _isEnabled;
    _panGestureRecognizer.enabled = _isEnabled;
}

- (void) updateCells
{
    NSIndexPath* newIndexPath = [_tableView indexPathForRowAtPoint:self.currentView.center];
    NSIndexPath* previousIndexPath = self.draggedCellIndexPath;
    
    BOOL canMove = YES;
    
    if([self.delegate respondsToSelector:@selector(cellsDragger:canMoveCellAtIndexPath:toIndexPath:)])
    {
        canMove = [self.delegate cellsDragger:self canMoveCellAtIndexPath:previousIndexPath toIndexPath:newIndexPath];
    }
    
    if(!canMove || (newIndexPath==nil || [newIndexPath isEqual:previousIndexPath]))
    {
        return;
    }
    
    if(self.previousCenter.y - self.currentView.center.y>=0)
    {
        if(self.lastDraggingDirection==NCDraggingDirectionUndefined)
        {
            self.lastDraggingDirection=NCDraggingDirectionUp;
        }
        
        if([self.lastSwappedIndexPath isEqual:newIndexPath])
        {
            if(self.lastDraggingDirection==NCDraggingDirectionDown)
            {
                self.lastDraggingDirection=NCDraggingDirectionUp;
            }
            else if(self.lastDraggingDirection==NCDraggingDirectionUp)
            {
                return;
            }
        }
    }
    else if(self.previousCenter.y - self.currentView.center.y<=0)
    {
        if(self.lastDraggingDirection==NCDraggingDirectionUndefined)
        {
            self.lastDraggingDirection=NCDraggingDirectionDown;
        }
        
        if([self.lastSwappedIndexPath isEqual:newIndexPath])
        {
            if(self.lastDraggingDirection==NCDraggingDirectionUp)
            {
                self.lastDraggingDirection=NCDraggingDirectionDown;
            }
            else if(self.lastDraggingDirection==NCDraggingDirectionDown)
            {
                return;
            }
        }
    }
    
    
    
    self.draggedCellIndexPath = newIndexPath;
    self.lastSwappedIndexPath = previousIndexPath;
    
    if([self.delegate respondsToSelector:@selector(cellsDragger:willMoveCellAtIndexPath:toIndexPath:)])
    {
        [self.delegate cellsDragger:self willMoveCellAtIndexPath:previousIndexPath toIndexPath:newIndexPath];
    }
    
    [_tableView moveRowAtIndexPath:previousIndexPath toIndexPath:newIndexPath];
    if([self.delegate respondsToSelector:@selector(cellsDragger:didMoveCellAtIndexPath:toIndexPath:)])
    {
        [self.delegate cellsDragger:self didMoveCellAtIndexPath:previousIndexPath toIndexPath:newIndexPath];
    }
}

- (void) stopTimer
{
    [_scrollingTimer invalidate];
    _scrollingTimer = nil;
}

- (void)setupScrollTimerInDirection:(NCDraggingDirection)direction {
    if (_scrollingTimer.isValid) {
        NCDraggingDirection oldDirection = [_scrollingTimer.userInfo[kDraggingDirectionKey] integerValue];
        
        if (direction == oldDirection) {
            return;
        }
    }
    
    [self stopTimer];
    
    _scrollingTimer = [NSTimer scheduledTimerWithTimeInterval:kScrollingFPS
                                                       target:self
                                                     selector:@selector(handleScroll:)
                                                     userInfo:@{ kDraggingDirectionKey : @(direction) }
                                                      repeats:YES];
}

- (void)handleScroll:(NSTimer *)timer {
    NCDraggingDirection direction = (NCDraggingDirection)[timer.userInfo[kDraggingDirectionKey] integerValue];
    if (direction == NCDraggingDirectionUndefined) {
        return;
    }
    
    CGSize frameSize = _tableView.bounds.size;
    CGSize contentSize = _tableView.contentSize;
    CGPoint contentOffset = _tableView.contentOffset;
    CGFloat distance = kScrollingPerTick;
    CGPoint translation = CGPointZero;
    
    switch(direction) {
        case NCDraggingDirectionUp: {
            distance = -distance;
            CGFloat minY = 0.0f;
            
            if ((contentOffset.y + distance) <= minY) {
                distance = -contentOffset.y;
            }
            
            translation = CGPointMake(0.0f, distance);
        } break;
        case NCDraggingDirectionDown: {
            CGFloat maxY = MAX(contentSize.height, frameSize.height) - frameSize.height;
            
            if ((contentOffset.y + distance) >= maxY) {
                distance = maxY - contentOffset.y;
            }
            
            translation = CGPointMake(0.0f, distance);
        } break;
        default: {
            // Do nothing...
        } break;
    }
    
    self.currentCenter = CGPointMake(self.currentCenter.x + translation.x, self.currentCenter.y + translation.y);//LXS_CGPointAdd(self.currentViewCenter, translation);
    self.currentView.center = CGPointMake(self.currentCenter.x + _lastPanTranslation.x, self.currentCenter.y +_lastPanTranslation.y);//LXS_CGPointAdd(self.currentViewCenter, self.panTranslationInCollectionView);
    _tableView.contentOffset = CGPointMake(contentOffset.x + translation.x, contentOffset.y + translation.y);//LXS_CGPointAdd(contentOffset, translation);
}

- (void) animateCurrentViewToIndexPath:(NSIndexPath*) indexPath completionBlock:(void(^)(void)) completionBlock
{
    [self.currentView.superview bringSubviewToFront:self.currentView];
    CGRect cellRect = [_tableView rectForRowAtIndexPath:indexPath];
    
    CABasicAnimation* opacityAnimation = [CABasicAnimation animationWithKeyPath:@"shadowOpacity"];
    opacityAnimation.fromValue = @1;
    opacityAnimation.toValue = @0;
    opacityAnimation.duration = 0.25;
    [self.currentView.layer addAnimation:opacityAnimation forKey:nil];
    self.currentView.layer.shadowOpacity = 0;
    
    [UIView animateWithDuration:0.25 animations:^{
        
        self.currentView.transform = CGAffineTransformIdentity;
        self.currentView.center = CGPointMake(CGRectGetMidX(cellRect), CGRectGetMidY(cellRect));
        
    } completion:^(BOOL finished) {
        
        if(completionBlock)
        {
            completionBlock();
        }
        
    }];
}

- (void) cleanup
{
    [self stopTimer];
    self.lastSwappedIndexPath = nil;
    self.draggedCellIndexPath = nil;
    self.draggedCell = nil;
    self.previousCenter = CGPointZero;
    self.currentCenter = CGPointZero;
    [self.currentView removeFromSuperview];
    self.currentView = nil;
    
}

- (void) handleLongPressRecognizer:(UILongPressGestureRecognizer*) longPressRecoginzer
{
    switch (longPressRecoginzer.state) {
            
        case UIGestureRecognizerStateBegan:
        {
            self.lastDraggingDirection = NCDraggingDirectionUndefined;
            self.lastSwappedIndexPath = nil;
            self.previousCenter = CGPointZero;
            self.draggedCellIndexPath = nil;
            self.draggedCell = nil;
            self.currentCenter = CGPointZero;
            NSIndexPath* draggedIndexPath = [_tableView indexPathForRowAtPoint:[longPressRecoginzer locationInView:_tableView]];
            
            if([self.delegate respondsToSelector:@selector(cellsDragger:canMoveCellAtIndexPath:)])
            {
                if(![self.delegate cellsDragger:self canMoveCellAtIndexPath:draggedIndexPath])
                {
                    return;
                }
            }
            
            if([self.delegate respondsToSelector:@selector(cellsDragger:willBeginDraggingCellAtIndexPath:)])
            {
                [self.delegate cellsDragger:self willBeginDraggingCellAtIndexPath:draggedIndexPath];
            }
            
            self.draggedCellIndexPath = draggedIndexPath;
            
            UITableViewCell* cell = [_tableView cellForRowAtIndexPath:draggedIndexPath];
            self.draggedCell = cell;
            
            self.currentCenter = cell.center;
            self.currentView = [[UIView alloc] initWithFrame:cell.frame];
            
            UIImageView* contentImageView = [[UIImageView alloc] initWithImage:[cell rasterizedContent]];
            contentImageView.frame = self.currentView.bounds;
            contentImageView.userInteractionEnabled = YES;
            [self.currentView addSubview:contentImageView];
            self.currentView.center = self.currentCenter;
            self.currentView.layer.masksToBounds = NO;
            self.currentView.layer.shadowColor = [UIColor blackColor].CGColor;
            self.currentView.layer.shadowOffset = CGSizeZero;
            
            [_tableView addSubview:self.currentView];
            
            CABasicAnimation* opacityAnimation = [CABasicAnimation animationWithKeyPath:@"shadowOpacity"];
            opacityAnimation.fromValue = @0;
            opacityAnimation.toValue = @1.0;
            opacityAnimation.duration = 0.25;
            [self.currentView.layer addAnimation:opacityAnimation forKey:nil];
            self.currentView.layer.shadowOpacity = 1.0;
            
            [UIView animateWithDuration:0.25 animations:^{
                self.currentView.transform = CGAffineTransformMakeScale(1.02, 1.02);
            } completion:^(BOOL finished) {
                
                if([self.delegate respondsToSelector:@selector(cellsDragger:didBeginDraggingCellAtIndexPath:)])
                {
                    [self.delegate cellsDragger:self didBeginDraggingCellAtIndexPath:draggedIndexPath];
                }
                
            }];
            
            cell.hidden = YES;
        }
            break;
        case UIGestureRecognizerStateEnded:
        {
            NSIndexPath* draggedPath = self.draggedCellIndexPath;
            
            if([self.delegate respondsToSelector:@selector(cellsDragger:willEndDraggingCellAtIndexPath:)])
            {
                [self.delegate cellsDragger:self willEndDraggingCellAtIndexPath:draggedPath];
            }
            
            [self animateCurrentViewToIndexPath:self.draggedCellIndexPath completionBlock:^{
                self.draggedCell.hidden = NO;
                [self cleanup];
                
                if([self.delegate respondsToSelector:@selector(cellsDragger:didEndDraggingCellAtIndexPath:)])
                {
                    [self.delegate cellsDragger:self didEndDraggingCellAtIndexPath:draggedPath];
                }
                
            }];
            //self.draggedCell.hidden = NO;
            //[self cleanup];
        }
            break;
            
        default:
            break;
    }
}

- (void) handlePanRecognizer:(UIPanGestureRecognizer*) panRecognizer
{
    CGPoint translation = CGPointZero;
    switch (panRecognizer.state) {
        case UIGestureRecognizerStateBegan:
        case UIGestureRecognizerStateChanged:
        {
            //self.lastDraggingDirection = NCDraggingDirectionUndefined;
            self.previousCenter = self.currentView.center;
            translation = [panRecognizer translationInView:panRecognizer.view];
            translation.x = 0;
            self.lastPanTranslation = translation;
            CGPoint currentCenter = self.currentCenter;
            currentCenter.x += translation.x;
            currentCenter.y += translation.y;
            self.currentView.center = currentCenter;
            [self updateCells];
            
            if (currentCenter.y < (CGRectGetMinY(_tableView.bounds) + kScrollingInset)) {
                [self setupScrollTimerInDirection:NCDraggingDirectionUp];
            } else {
                if (currentCenter.y > (CGRectGetMaxY(_tableView.bounds) - kScrollingInset)) {
                    [self setupScrollTimerInDirection:NCDraggingDirectionDown];
                } else {
                    [self stopTimer];
                }
            }
            
        }
            break;
        case UIGestureRecognizerStateEnded:
        {
            //            [self animateCurrentViewToIndexPath:self.draggedCellIndexPath completionBlock:^{
            //                [self cleanup];
            //                self.draggedCell.hidden = NO;
            //            }];
            //[self cleanup];
        }
            break;
        default:
            break;
    }
    
    
}

#pragma mark - UIGestureRecognizer delegate methods

- (BOOL) gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer
{
    if(gestureRecognizer==_longPressGestureRecognizer)
    {
        return !_tableView.isDragging;
    }
    else if(gestureRecognizer==_panGestureRecognizer)
    {
        return self.draggedCellIndexPath!=nil;
    }
    return YES;
}

- (BOOL) gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer
{
    if((gestureRecognizer==_panGestureRecognizer && otherGestureRecognizer==_longPressGestureRecognizer) ||
       (gestureRecognizer==_longPressGestureRecognizer && otherGestureRecognizer==_panGestureRecognizer))
    {
        return YES;
    }
    return NO;
}

@end
