//
//  GKPageSmoothView.m
//  GKPageScrollViewObjc
//
//  Created by QuintGao on 2020/5/4.
//  Copyright © 2020 QuintGao. All rights reserved.
//

#import "GKPageSmoothView.h"

static NSString *const GKPageSmoothViewCellID = @"smoothViewCell";

@interface GKPageSmoothCollectionView : UICollectionView<UIGestureRecognizerDelegate>

@property (nonatomic, weak) UIView *headerContainerView; // 用于gr delegate方法判断

@end

@implementation GKPageSmoothCollectionView

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    // 只响应cell内的滑动手势, 不响应点击在header的手势
    // 这样滑动cell可以翻页, 但header部分可以保持不变
    CGPoint point = [touch locationInView:self.headerContainerView];
    if (CGRectContainsPoint(self.headerContainerView.bounds, point)) {
        return NO;
    }
    return YES;
}

@end

@interface GKPageSmoothView()<UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout, UIGestureRecognizerDelegate>

@property (nonatomic, weak) id<GKPageSmoothViewDataSource> dataSource;
@property (nonatomic, strong) GKPageSmoothCollectionView  *listCollectionView;
@property (nonatomic, strong) NSMutableDictionary <NSNumber *, id<GKPageSmoothListViewDelegate>> *listDict;
@property (nonatomic, strong) NSMutableDictionary <NSNumber *, UIView *> *listHeaderDict; // 保存各内容的listHeader, 它是内容scrollview的subview, headerContainerView的superview

@property (nonatomic, assign) GKPageSmoothHoverType hoverType;

@property (nonatomic, strong) UIView *headerContainerView;
@property (nonatomic, weak) UIView *headerView;
@property (nonatomic, weak) UIView *segmentedView;
@property (nonatomic, weak) UIScrollView *currentListScrollView; // 当前内容scrollview

@property (nonatomic, strong) UIView *bottomContainerView;

@property (nonatomic, assign) BOOL syncListContentOffsetEnabled;
@property (nonatomic, assign) CGFloat currentHeaderContainerViewY; // headerContainerView作为self的subview时的y值, 用于横向滚动时记录header的位置, 帮助实现悬浮效果

@property (nonatomic, assign) CGFloat headerContainerHeight; // headerHeight+segmentedHeight
@property (nonatomic, assign) CGFloat headerHeight;
@property (nonatomic, assign) CGFloat segmentedHeight;
@property (nonatomic, assign) CGFloat currentListInitializeContentOffsetY; // 内容scrollView初始化时的contentOffset位置,

@property (nonatomic, assign) BOOL      isLoaded; // ???: xxx已加载. 不加载collectionView不显示内容

@property (nonatomic, strong) UIPanGestureRecognizer *panGesture; // 加在bottomContainerView的手势

@property (nonatomic, weak) UIScrollView *scrollView; // panGesture手势所在的内容scrollview
@property (nonatomic, assign) BOOL       isDragScrollView; // panGesture手势是否在内容scrollview上, NO表示在bottomContainerView(即segment上)
@property (nonatomic, assign) CGFloat    lastTransitionY; // panGesture手势在bottomContainerView的CGPoint的y
@property (nonatomic, assign) BOOL       isOnTop; // 通过拖拽开始向上滑动或已经滑动到吸顶

@property (nonatomic, assign) CGFloat    currentListPanBeganContentOffsetY; // pan gr开始时内容scrollView的contentOffsetY
@property (nonatomic, assign) BOOL       originBounces;
@property (nonatomic, assign) BOOL       originShowsVerticalScrollIndicator;

@property (nonatomic, assign) BOOL       isScroll; // collectionView正在滚动(翻页)

@end

@implementation GKPageSmoothView

- (instancetype)initWithDataSource:(id<GKPageSmoothViewDataSource>)dataSource {
    if (self = [super initWithFrame:CGRectZero]) {
        self.dataSource = dataSource;
        _listDict = [NSMutableDictionary dictionary];
        _listHeaderDict = [NSMutableDictionary dictionary];
        _ceilPointHeight = 0;
        
        [self addSubview:self.listCollectionView];
        [self addSubview:self.headerContainerView];
        [self refreshHeaderView];
    }
    return self;
}

- (void)dealloc {
    for (id<GKPageSmoothListViewDelegate> listItem in self.listDict.allValues) {
        [listItem.listScrollView removeObserver:self forKeyPath:@"contentOffset"];
        [listItem.listScrollView removeObserver:self forKeyPath:@"contentSize"];
    }
    
    [self.headerView removeFromSuperview];
    [self.segmentedView removeFromSuperview];
    self.listCollectionView.dataSource = nil;
    self.listCollectionView.delegate = nil;
}

- (void)layoutSubviews {
    // 临界点触发layoutSubviews方法, 看不到哪里调用
    [super layoutSubviews];
    
    if (self.isMainScrollDisabled) {
        // header不滑动, 设collectionView和子vc的frame
        CGRect frame = self.frame;
        frame.origin.y = self.headerContainerHeight;
        frame.size.height -= self.headerContainerHeight;
        [self refreshListFrame:frame];
        self.listCollectionView.frame = frame;
    } else {
        if (self.listCollectionView.superview == self) {
            // segment非吸顶, collectionView在self(view)
            [self refreshListFrame:self.bounds];
            self.listCollectionView.frame = self.bounds;
        } else {
            // segment吸顶, collectionView在bottomContainerView
            CGRect frame = self.listCollectionView.frame;
            frame.origin.y = self.segmentedHeight;
            frame.size.height = self.bottomContainerView.frame.size.height - self.segmentedHeight;
            [self refreshListFrame:frame];
            self.listCollectionView.frame = frame;
        }
    }
}

// 更新子vc的高度
- (void)refreshListFrame:(CGRect)frame {
    for (id<GKPageSmoothListViewDelegate> list in self.listDict.allValues) {
        CGRect f = list.listView.frame;
        if (f.size.height != frame.size.height) {
            f.size.height = frame.size.height;
            list.listView.frame = f;
            [self.listCollectionView reloadData];
        }
    }
}

// 获取header和segment的高度, 做相关的界面和布局的修改
- (void)refreshHeaderView {
    [self loadHeaderAndSegmentedView]; // 确定header和segment高度
    
    // CGPageSmoothView有了size之后做和headerContainerHeight相关的初始化和布局
    // 如果用vc做, 可以在viewDidLoad调用, 或者用自动布局
    __weak __typeof(self) weakSelf = self;
    [self refreshWidthCompletion:^(CGSize size) {
        // headerContainerView.height = headerContainerHeight
        __strong __typeof(weakSelf) self = weakSelf;
        CGRect frame = self.headerContainerView.frame;
        if (CGRectEqualToRect(frame, CGRectZero)) {
            frame = CGRectMake(0, 0, size.width, self.headerContainerHeight);
        } else {
            frame.size.height = self.headerContainerHeight;
        }
        self.headerContainerView.frame = frame;
        
        // layout headerView & segmentedView
        self.headerView.frame = CGRectMake(0, 0, size.width, self.headerHeight);
        self.segmentedView.frame = CGRectMake(0, self.headerHeight, size.width, self.segmentedHeight);
        
        // headerContainerHeight确定后, 添加为内容vc的contentInset, 实现连续滚动效果
        if (!self.isMainScrollDisabled) {
            // header不滚动不用添加
            for (id<GKPageSmoothListViewDelegate> list in self.listDict.allValues) {
                list.listScrollView.contentInset = UIEdgeInsetsMake(self.headerContainerHeight, 0, 0, 0);
            }
        }
        
        if (self.isBottomHover) {
            // 吸底状态, bottomContainerView内显示segment, 注意修改的y和height的值
            self.bottomContainerView.frame = CGRectMake(0, size.height - self.segmentedHeight, size.width, size.height - self.ceilPointHeight);
            
            if (self.headerHeight > size.height) {
                self.segmentedView.frame = CGRectMake(0, 0, size.width, self.segmentedHeight);
                // 此时headerContainerView失去segment, 但没有显示到segment的位置, 所以看不出来
                [self.bottomContainerView addSubview:self.segmentedView];
            }
        }
    }];
}

- (void)reloadData {
    self.currentListScrollView = nil;
    self.currentIndex = self.defaultSelectedIndex;
    self.syncListContentOffsetEnabled = NO;
    self.currentHeaderContainerViewY = 0;
    self.isLoaded = YES; // useless
    
    [self.listHeaderDict removeAllObjects];
    
    for (id<GKPageSmoothListViewDelegate> list in self.listDict.allValues) {
        [list.listScrollView removeObserver:self forKeyPath:@"contentOffset"];
        [list.listScrollView removeObserver:self forKeyPath:@"contentSize"];
        [list.listView removeFromSuperview];
    }
    [_listDict removeAllObjects];
    
    // collectionView翻页到currentIndex
    __weak __typeof(self) weakSelf = self;
    [self refreshWidthCompletion:^(CGSize size) {
        __strong __typeof(weakSelf) self = weakSelf;
        [self.listCollectionView setContentOffset:CGPointMake(size.width * self.currentIndex, 0) animated:NO];
        [self.listCollectionView reloadData];
    }];
}

- (void)scrollToOriginalPoint {
    [self.currentListScrollView setContentOffset:CGPointMake(0, -self.headerContainerHeight) animated:YES]; // 滑动到最上面, 包括contentInset的top, 即headerContainerHeight的距离
}

- (void)scrollToCriticalPoint {
    // contentOffsetY = 0, 滑动到不包含header的位置
    // 保留segment, 向上滑一段距离, -segmentedHeight
    // 保留header保留高度, 再向上滑一段距离露出这部分, -ceilPointHeight
    // 所以临界点的 y = -(segmentedHeight+ceilPointHeight)
    [self.currentListScrollView setContentOffset:CGPointMake(0, -(self.segmentedHeight+self.ceilPointHeight)) animated:YES];
}

- (void)showingOnTop {
    if (self.bottomContainerView.isHidden) return;
    [self dragBegan];
    [self dragShowing];
}

- (void)showingOnBottom {
    if (self.bottomContainerView.isHidden) return;
    [self dragDismiss];
}

- (void)setBottomHover:(BOOL)bottomHover {
    _bottomHover = bottomHover;
    
    if (bottomHover) {
        // 吸底添加bottomContainerView, segment放在里面
        __weak __typeof(self) weakSelf = self;
        [self refreshWidthCompletion:^(CGSize size) {
            __strong __typeof(weakSelf) self = weakSelf;
            // y: 吸底位置
            // height: 滑上去之后能达到的高度, 即superview高度-保留高度
            self.bottomContainerView.frame = CGRectMake(0, size.height - self.segmentedHeight, size.width, size.height - self.ceilPointHeight);
            [self addSubview:self.bottomContainerView];
            
            if (self.headerHeight > size.height) {
                self.segmentedView.frame = CGRectMake(0, 0, size.width, self.segmentedHeight);
                [self.bottomContainerView addSubview:self.segmentedView];
            }
        }];
    } else {
        // 非吸底不添加bottomContainerView
        [self.bottomContainerView removeFromSuperview];
    }
}

- (void)setAllowDragBottom:(BOOL)allowDragBottom {
    _allowDragBottom = allowDragBottom;
    
    if (self.bottomHover) {
        if (allowDragBottom) {
            [self.bottomContainerView addGestureRecognizer:self.panGesture];
        } else {
            [self.bottomContainerView removeGestureRecognizer:self.panGesture];
        }
    }
}

#pragma mark - UICollectionViewDataSource

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView {
    return self.isLoaded ? 1 : 0;
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return [self.dataSource numberOfListsInSmoothView:self];
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    UICollectionViewCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:GKPageSmoothViewCellID forIndexPath:indexPath];
    id<GKPageSmoothListViewDelegate> list = self.listDict[@(indexPath.item)];
    if (list == nil) {
        list = [self.dataSource smoothView:self initListAtIndex:indexPath.item];
        _listDict[@(indexPath.item)] = list;
        // 触发list.view的加载/初始化
        [list.listView setNeedsLayout];
        
        UIScrollView *listScrollView = list.listScrollView;
        // 禁用tableview的自适应高度
        if ([listScrollView isKindOfClass:[UITableView class]]) {
            ((UITableView *)listScrollView).estimatedRowHeight = 0;
            ((UITableView *)listScrollView).estimatedSectionHeaderHeight = 0;
            ((UITableView *)listScrollView).estimatedSectionFooterHeight = 0;
        }
        
        // 关闭自动调整contentInset, 自己控制
        if (@available(iOS 11.0, *)) {
            listScrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
        }
        
        // header可滚动时, 添加header作为内容scrollview的contentInset
        if (!self.isMainScrollDisabled) {
            if (!self.isOnTop) {
                listScrollView.contentInset = UIEdgeInsetsMake(self.headerContainerHeight, 0, 0, 0);
                // ???: currentListInitializeContentOffsetY
                self.currentListInitializeContentOffsetY = -listScrollView.contentInset.top + MIN(-self.currentHeaderContainerViewY, (self.headerHeight - self.ceilPointHeight)); // 初始值是-listScrollView.contentInset.top, 因为self.currentHeaderContainerViewY为0, MIN那部分为0
                [self setScrollView:listScrollView offset:CGPointMake(0, self.currentListInitializeContentOffsetY)];
            }
            
            // 在contentInset的位置添加subview
            UIView *listHeader = [[UIView alloc] initWithFrame:CGRectMake(0, -self.headerContainerHeight, self.bounds.size.width, self.headerContainerHeight)];
            [listScrollView addSubview:listHeader];
            
            // 非吸顶状态(也非开始吸顶动作的状态)添加headerContainerView
            if (!self.isOnTop && self.headerContainerView.superview == nil) {
                [listHeader addSubview:self.headerContainerView];
            }
            self.listHeaderDict[@(indexPath.item)] = listHeader;
        }
        
        // kvo监听内容scrollview
        [listScrollView addObserver:self forKeyPath:@"contentOffset" options:NSKeyValueObservingOptionNew context:nil];
        [listScrollView addObserver:self forKeyPath:@"contentSize" options:NSKeyValueObservingOptionNew context:nil];
        
        // bug fix #69 修复首次进入时可能出现的headerView无法下拉的问题
        [listScrollView setContentOffset:listScrollView.contentOffset];
    }
    
    // 对当前内容scrollsToTop
    for (id<GKPageSmoothListViewDelegate> listItem in self.listDict.allValues) {
        listItem.listScrollView.scrollsToTop = (listItem == list);
    }
    
    // 添加内容vc.view到cell, 形成一个可连续滚动的结构
    UIView *listView = list.listView;
    if (listView != nil && listView.superview != cell.contentView) {
        for (UIView *view in cell.contentView.subviews) {
            [view removeFromSuperview];
        }
        listView.frame = cell.contentView.bounds;
        [cell.contentView addSubview:listView];
    }
    return cell;
}

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)collectionViewLayout sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    for (id<GKPageSmoothListViewDelegate> list in self.listDict.allValues) {
        // 同时设置内容frame
        list.listView.frame = (CGRect){{0, 0}, self.listCollectionView.bounds.size};
    }
    return self.listCollectionView.bounds.size;
}

- (void)collectionView:(UICollectionView *)collectionView willDisplayCell:(UICollectionViewCell *)cell forItemAtIndexPath:(NSIndexPath *)indexPath {
    [self listDidAppear:indexPath.item];
}

- (void)collectionView:(UICollectionView *)collectionView didEndDisplayingCell:(UICollectionViewCell *)cell forItemAtIndexPath:(NSIndexPath *)indexPath {
    [self listDidDisappear:indexPath.item];
}

// 以下UIScrollViewDelegate方法, collectionView横向滚动(翻页)时触发
- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
    // 横向滚动关闭gr. scrollView是collectionView
    self.panGesture.enabled = NO;
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    if ([self.delegate respondsToSelector:@selector(smoothView:scrollViewDidScroll:)]) {
        [self.delegate smoothView:self scrollViewDidScroll:scrollView];
    }
    
    CGFloat indexPercent = scrollView.contentOffset.x/scrollView.bounds.size.width;
    NSInteger index = floor(indexPercent);
    self.isScroll = YES;
    
    if (!self.isMainScrollDisabled) {
        if (!self.isOnTop) {
            UIScrollView *listScrollView = self.listDict[@(index)].listScrollView;
            if (index != self.currentIndex && indexPercent - index == 0 && !(scrollView.isDragging || scrollView.isDecelerating) && listScrollView.contentOffset.y <= -(self.segmentedHeight + self.ceilPointHeight)) {
                // 达到翻页条件, 执行翻页
                // -(segmentedHeight+ceilPointHeight) 是临界点y值, contentOffsetY小于临界值说明未吸顶
                [self horizontalScrollDidEndAtIndex:index];
            } else {
                // 左右滚动的时候，把headerContainerView添加到self，达到悬浮的效果
                // 即翻页过程中, 记录headerContainerView当前的y值并移出contentInset
                if (self.headerContainerView.superview != self) {
                    CGRect frame = self.headerContainerView.frame;
                    frame.origin.y = self.currentHeaderContainerViewY;
                    self.headerContainerView.frame = frame;
                    [self addSubview:self.headerContainerView];
                }
            }
        }
    }
    
    if (index != self.currentIndex) {
        self.currentIndex = index;
    }
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate {
    if (self.isMainScrollDisabled) return;
    if (!decelerate) {
        NSInteger index = scrollView.contentOffset.x / scrollView.bounds.size.width;
        [self horizontalScrollDidEndAtIndex:index];
    }
    self.panGesture.enabled = YES;
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
    if (self.isMainScrollDisabled) return;
    NSInteger index = scrollView.contentOffset.x / scrollView.bounds.size.width;
    [self horizontalScrollDidEndAtIndex:index];
    self.panGesture.enabled = YES;
}

- (void)scrollViewDidEndScrollingAnimation:(UIScrollView *)scrollView {
    // 修复快速闪烁问题
    NSInteger index = scrollView.contentOffset.x / scrollView.bounds.size.width;
    self.currentIndex = index;
    self.currentListScrollView = self.listDict[@(index)].listScrollView;
    self.isScroll = NO;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!self.isScroll && self.headerContainerView.superview == self) {
            [self horizontalScrollDidEndAtIndex:index];
        }
    });
}

#pragma mark - KVO
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context {
    if ([keyPath isEqualToString:@"contentOffset"]) {
        UIScrollView *scrollView = (UIScrollView *)object;
        if (scrollView != nil) {
            [self listScrollViewDidScroll:scrollView];
        }
    } else if ([keyPath isEqualToString:@"contentSize"]) {
        UIScrollView *scrollView = (UIScrollView *)object;
        if (scrollView != nil) {
            // minContentSizeHeight是内容要撑满self的最小高度
            CGFloat minContentSizeHeight = self.bounds.size.height - self.segmentedHeight - self.ceilPointHeight;
            CGFloat contentH = scrollView.contentSize.height;
            if (minContentSizeHeight > contentH && self.isHoldUpScrollView) {
                // 如果内容不足一屏, 且要撑起内容, 就重设contentSize
                scrollView.contentSize = CGSizeMake(scrollView.contentSize.width, minContentSizeHeight);
                // 新的scrollView第一次加载的时候重置contentOffset
                if (self.currentListScrollView != nil && scrollView != self.currentListScrollView) {
                    scrollView.contentOffset = CGPointMake(0, self.currentListInitializeContentOffsetY); // ???: currentListInitializeContentOffsetY
                }
            } else {
                // 内容足够, 或内容不足但不撑起来
                BOOL shouldReset = YES;
                for (id<GKPageSmoothListViewDelegate> list in self.listDict.allValues) {
                    if (list.listScrollView == scrollView && [list respondsToSelector:@selector(listScrollViewShouldReset)]) {
                        shouldReset = [list listScrollViewShouldReset];
                    }
                }
                
                // 不足一屏, 且需要重置, 就滚动到最顶端
                if (minContentSizeHeight > contentH && shouldReset) {
                    [scrollView setContentOffset:CGPointMake(scrollView.contentOffset.x, -self.headerContainerHeight) animated:NO];
                    [self listScrollViewDidScroll:scrollView];
                }
            }
        }
    } else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

#pragma mark - Gesture
- (void)handlePanGesture:(UIPanGestureRecognizer *)panGesture {
    if (panGesture.state == UIGestureRecognizerStateBegan) {
        if ([self.delegate respondsToSelector:@selector(smoothViewDragBegan:)]) {
            [self.delegate smoothViewDragBegan:self];
        }
        [self dragBegan];
        
        // 记录scrollView的某些属性
        self.originBounces = self.scrollView.bounces;
        self.originShowsVerticalScrollIndicator = self.scrollView.showsVerticalScrollIndicator;
        
        // bug fix #47，当UIScrollView向下滚动的时候，向下拖拽完成手势操作导致的错乱问题
        if (self.currentListScrollView.isDecelerating) {
            [self.currentListScrollView setContentOffset:self.currentListScrollView.contentOffset animated:NO];
        }
    }
    
    // gr在bottomContainerView的坐标
    CGPoint translation = [panGesture translationInView:self.bottomContainerView];
    if (self.isDragScrollView) {
        [self allowScrolling:self.scrollView];
        // 当UIScrollView在最顶部时，处理视图的滑动
        if (self.scrollView.contentOffset.y <= 0) {
            if (translation.y > 0) { // 向下拖拽
                [self forbidScrolling:self.scrollView];
                self.isDragScrollView = NO;
                
                CGRect frame = self.bottomContainerView.frame;
                frame.origin.y += translation.y;
                self.bottomContainerView.frame = frame;
                
                if (!self.isAllowDragScroll) {
                    self.scrollView.panGestureRecognizer.enabled = NO;
                    self.scrollView.panGestureRecognizer.enabled = YES;
                }
            }
        }
    } else {
        CGFloat offsetY = self.scrollView.contentOffset.y;
        CGFloat ceilPointY = self.ceilPointHeight;
        
        if (offsetY <= 0) {
            [self forbidScrolling:self.scrollView];
            if (translation.y > 0) { // 向下拖拽
                CGRect frame = self.bottomContainerView.frame;
                frame.origin.y += translation.y;
                self.bottomContainerView.frame = frame;
            } else if (translation.y < 0 && self.bottomContainerView.frame.origin.y > ceilPointY) { // 向上拖拽
                CGRect frame = self.bottomContainerView.frame;
                frame.origin.y = MAX((self.bottomContainerView.frame.origin.y + translation.y), ceilPointY);
                self.bottomContainerView.frame = frame;
            }
        }else {
            if (translation.y < 0 && self.bottomContainerView.frame.origin.y > ceilPointY) {
                CGRect frame = self.bottomContainerView.frame;
                frame.origin.y = MAX((self.bottomContainerView.frame.origin.y + translation.y), ceilPointY);
                self.bottomContainerView.frame = frame;
            }
            
            if (self.bottomContainerView.frame.origin.y > ceilPointY) {
                [self forbidScrolling:self.scrollView];
            }else {
                [self allowScrolling:self.scrollView];
            }
        }
    }
    
    if (panGesture.state == UIGestureRecognizerStateEnded) {
        CGPoint velocity = [panGesture velocityInView:self.bottomContainerView];
        if (velocity.y < 0) { // 上滑
            if (fabs(self.lastTransitionY) > 5 && self.isDragScrollView == NO) {
                [self dragShowing];
            }else {
                if (self.bottomContainerView.frame.origin.y > (self.ceilPointHeight + self.bottomContainerView.frame.size.height / 2)) {
                    [self dragDismiss];
                }else {
                    [self dragShowing];
                }
            }
        }else { // 下滑
            if (fabs(self.lastTransitionY) > 5 && self.isDragScrollView == NO && !self.scrollView.isDecelerating) {
                [self dragDismiss];
            }else {
                if (self.bottomContainerView.frame.origin.y > (self.ceilPointHeight + self.bottomContainerView.frame.size.height / 2)) {
                    [self dragDismiss];
                }else {
                    [self dragShowing];
                }
            }
        }
        
        [self allowScrolling:self.scrollView];
        self.isDragScrollView = NO;
        self.scrollView = nil;
    }
    
    [panGesture setTranslation:CGPointZero inView:self.bottomContainerView];
    self.lastTransitionY = translation.y;
}

#pragma mark - UIGestureRecognizerDelegate
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    if (gestureRecognizer == self.panGesture) {
        UIView *touchView = touch.view;
        while (touchView != nil) {
            if (touchView == self.currentListScrollView) {
                self.scrollView = (UIScrollView *)touchView;
                self.isDragScrollView = YES;
                break;
            } else if (touchView == self.bottomContainerView) { // segment
                self.isDragScrollView = NO;
                break;
            }
            touchView = (UIView *)[touchView nextResponder];
        }
    }
    return YES;
}

- (BOOL)gestureRecognizerShouldBegin:(UIPanGestureRecognizer *)gestureRecognizer {
    // 左右滑动时禁止上下滑动
    CGPoint transition = [gestureRecognizer translationInView:gestureRecognizer.view];
    if (transition.x != 0) return NO;
    return YES;
}

- (BOOL)gestureRecognizer:(UIPanGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    if (gestureRecognizer == self.panGesture) {
        if (otherGestureRecognizer == self.scrollView.panGestureRecognizer) {
            return YES;
        }
    }
    return NO;
}

#pragma mark - Private Methods

// kvo内容的scrollView的contentOffset
- (void)listScrollViewDidScroll:(UIScrollView *)scrollView {
    NSLog(@"%@", NSStringFromCGPoint(scrollView.contentOffset));
    // header不滚动, 不存在吸顶吸底, header单独存在, 和翻页部分无关, 不需要处理内容滚动
    if (self.isMainScrollDisabled) {
        if ([self.delegate respondsToSelector:@selector(smoothView:listScrollViewDidScroll:contentOffset:)]) {
            [self.delegate smoothView:self listScrollViewDidScroll:scrollView contentOffset:scrollView.contentOffset];
        }
        return;
    }
    
    // 翻页时不处理内容滚动
    // 似乎只有第一次翻页时会触发
    if (self.listCollectionView.isDragging ||
        self.listCollectionView.isDecelerating) {
        return;
    }
    
    if (self.isOnTop) { // 在顶部时无需处理headerView
        // 取消scrollView下滑时的弹性效果
        // buf fix #47，iOS12及以下系统isDragging会出现不准确的情况，所以这里改为用isTracking判断
        if (self.isAllowDragScroll && (scrollView.isTracking || scrollView.isDecelerating)) {
            if (scrollView.contentOffset.y < 0) {
                [self setScrollView:scrollView offset:CGPointZero];
            }
        }
        
        if ([self.delegate respondsToSelector:@selector(smoothView:listScrollViewDidScroll:contentOffset:)]) {
            [self.delegate smoothView:self listScrollViewDidScroll:scrollView contentOffset:scrollView.contentOffset];
        }
    } else { // 不在顶部，通过列表scrollView滑动确定悬浮位置
        NSInteger listIndex = [self listIndexForListScrollView:scrollView];
        if (listIndex != self.currentIndex) return;
        self.currentListScrollView = scrollView;
        
        // scrollView.contentOffset.y是内容的contentOffset
        // contentOffsetY是转换为headerContainerView的contentOffset
        // (当!isOnTop时, scrollView.contentOffset.y是一个负值, 表示内容的contentInset露出了一部分.
        //  它加上headerContainerHeight表示从headerContainerView的整个高度减去已露出部分,
        //  等于headerContainerView已滚动的部分, 所以从headerContainerView的角度看,
        //  相当于headerContainerView的contentOffset.)
        CGFloat contentOffsetY = scrollView.contentOffset.y + self.headerContainerHeight;
        // headerHeight-ceilPointHeight为header可滚动的高度
        if (contentOffsetY < (self.headerHeight - self.ceilPointHeight)) {
            // 在可滚动范围内, 没有吸顶, 是否吸底待确认
            self.hoverType = GKPageSmoothHoverTypeNone;
            self.syncListContentOffsetEnabled = YES; // ???: 有必要?调试看结果
            // 滑动一部分, headerContainerView相对自己的原点的偏移量是contentOffsetY
            // 此时如果发生横向移动(翻页), headerContainerView放入self, 它的y就是-contentOffsetY
            self.currentHeaderContainerViewY = -contentOffsetY;
            
            // 同步各内容scrollView的contentOffset
            // 此时headerContainerView还是cell的contentInset, cell本身的内容还未露出或只出现一部分
            // 所以都保持当前scrollView的contentOffset, 翻页后headerContainerView还在同一位置
            for (id<GKPageSmoothListViewDelegate> list in self.listDict.allValues) {
                if (list.listScrollView != scrollView) {
                    [list.listScrollView setContentOffset:scrollView.contentOffset animated:NO];
                }
            }
            
            // headerContainerView放回listHeader
            UIView *listHeader = [self listHeaderForListScrollView:scrollView];
            if (self.headerContainerView.superview != listHeader) {
                CGRect frame = self.headerContainerView.frame;
                frame.origin.y = 0;
                self.headerContainerView.frame = frame;
                [listHeader addSubview:self.headerContainerView];
            }
            
            // 内部(内容?)控制滚动条, 且header有保留高度时, 隐藏内容scrollview的滚动条
            if (self.isControlVerticalIndicator && self.ceilPointHeight != 0) {
                self.currentListScrollView.showsVerticalScrollIndicator = NO;
            }
            
            if (self.isBottomHover) {
                // 有吸底效果, 检查在满足条件时吸底
                if (contentOffsetY < (self.headerContainerHeight - self.frame.size.height)) {
                    // 吸底:
                    // headerContainerHeight-self.frame.size.height是headerContainerView在屏幕之外的部分
                    // contentOffsetY小于它的值, 表示屏幕之外那段距离还没滑动完, 所以仍然是吸底状态
                    self.hoverType = GKPageSmoothHoverTypeBottom;
                    // 添加bottomContainerView
                    if (self.segmentedView.superview != self.bottomContainerView) {
                        self.bottomContainerView.hidden = NO;
                        CGRect frame = self.segmentedView.frame;
                        frame.origin.y = 0;
                        self.segmentedView.frame = frame;
                        [self.bottomContainerView addSubview:self.segmentedView];
                    }
                } else {
                    // 超出这段距离, segment已经被拉起来, 未吸底
                    // 隐藏bottomContainerView, segment要放在headerContainerView
                    if (self.segmentedView.superview != self.headerContainerView) {
                        self.bottomContainerView.hidden = YES;
                        CGRect frame = self.segmentedView.frame;
                        frame.origin.y = self.headerHeight;
                        self.segmentedView.frame = frame;
                        [self.headerContainerView addSubview:self.segmentedView];
                    }
                }
            }
        } else {
            // 吸顶
            // 滚动已经超过header保留的距离(ceilPointHeight)
            self.hoverType = GKPageSmoothHoverTypeTop;
            // self添加headerContainerView, 把segment部分固定在顶部
            if (self.headerContainerView.superview != self) {
                CGRect frame = self.headerContainerView.frame;
                frame.origin.y = - (self.headerHeight - self.ceilPointHeight);
                self.headerContainerView.frame = frame;
                [self addSubview:self.headerContainerView];
            }
            
            // 吸顶状态下显示内容scrollview的滚动条
            if (self.isControlVerticalIndicator) {
                self.currentListScrollView.showsVerticalScrollIndicator = YES;
            }
            
            // 吸顶后, 同步内容页的contentOffset
            // 此时headerContainerView在self, 它的y是一个负值, 等于自身高度减去保留高度
            // 所以currentHeaderContainerViewY = -(headerHeight-ceilPointHeight)
            if (self.syncListContentOffsetEnabled) {
                self.syncListContentOffsetEnabled = NO;
                self.currentHeaderContainerViewY = -(self.headerHeight - self.ceilPointHeight);
                // set其他内容scrollview的contentOffset, 翻页后能处于正确位置
                // 它们的contentOffset应该是把segment和保留高度露出来, 所以y=-(segmentedHeight+ceilPointHeight)
                for (id<GKPageSmoothListViewDelegate> listItem in self.listDict.allValues) {
                    if (listItem.listScrollView != scrollView) {
                        [listItem.listScrollView setContentOffset:CGPointMake(0, -(self.segmentedHeight + self.ceilPointHeight)) animated:NO];
                    }
                }
            }
        }
        
        // 传给委托横向+纵向位置
        CGPoint contentOffset = CGPointMake(scrollView.contentOffset.x, contentOffsetY);
        if ([self.delegate respondsToSelector:@selector(smoothView:listScrollViewDidScroll:contentOffset:)]) {
            [self.delegate smoothView:self listScrollViewDidScroll:scrollView contentOffset:contentOffset];
        }
    }
}

// 获取headerView, segmentedView; 确定headerHeight, segmentedHeight, headerContainerHeight
- (void)loadHeaderAndSegmentedView {
    self.headerView = [self.dataSource headerViewInSmoothView:self];
    self.segmentedView = [self.dataSource segmentedViewInSmoothView:self];
    [self.headerContainerView addSubview:self.headerView];
    [self.headerContainerView addSubview:self.segmentedView];
    
    self.headerHeight = self.headerView.bounds.size.height;
    self.segmentedHeight = self.segmentedView.bounds.size.height;
    self.headerContainerHeight = self.headerHeight + self.segmentedHeight;
}

// 获取self.bounds.size, 如果没有就延迟再执行
- (void)refreshWidthCompletion:(void(^)(CGSize size))completion {
    if (self.bounds.size.width == 0) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1f * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            !completion ? : completion(self.bounds.size);
        });
    } else {
        !completion ? : completion(self.bounds.size);
    }
}

// 滚动停止时在index位置
- (void)horizontalScrollDidEndAtIndex:(NSInteger)index {
    // set currentIndex & currentListScrollView
    self.currentIndex = index;
    UIView *listHeader = self.listHeaderDict[@(index)];
    UIScrollView *listScrollView = self.listDict[@(index)].listScrollView;
    self.currentListScrollView = listScrollView;
    
    // 已吸顶或在执行吸顶操作的过程中, 什么都不用做, 直接返回
    if (self.isOnTop) return;
    
    // 有listHeader, 且未达到吸顶的临界点, 说明在滑动过程中把headerContainerView临时放入self来实现悬浮效果
    // 或者至少headerContainerView还在上一个内容vc的listHeader
    // 所以滚动结束后把headerContainerView添加到当前内容vc的listHeader
    if (listHeader != nil && listScrollView.contentOffset.y <= -(self.segmentedHeight + self.ceilPointHeight)) {
        // 修改scrollsToTop的值, 只有当前内容vc响应scrollsToTop
        for (id<GKPageSmoothListViewDelegate> listItem in self.listDict.allValues) {
            listItem.listScrollView.scrollsToTop = (listItem.listScrollView == listScrollView);
        }
        
        // headerContainerView添加到当前内容vc的listHeader
        CGRect frame = self.headerContainerView.frame;
        frame.origin.y = 0;
        self.headerContainerView.frame = frame;
        if (self.headerContainerView.superview != listHeader) {
            [listHeader addSubview:self.headerContainerView];
        }
        
        // 内容不足一屏, 且设置项为不撑起来, 就滚动到最顶端, 显示header, 且触发内容滚动的回调
        CGFloat minContentSizeHeight = self.bounds.size.height - self.segmentedHeight - self.ceilPointHeight;
        if (minContentSizeHeight > listScrollView.contentSize.height && !self.isHoldUpScrollView) {
            [listScrollView setContentOffset:CGPointMake(listScrollView.contentOffset.x, -self.headerContainerHeight) animated:NO];
            [self listScrollViewDidScroll:listScrollView];
        }
    }
}

- (UIView *)listHeaderForListScrollView:(UIScrollView *)scrollView {
    for (NSNumber *index in self.listDict) {
        if (self.listDict[index].listScrollView == scrollView) {
            return self.listHeaderDict[index];
        }
    }
    return nil;
}

- (NSInteger)listIndexForListScrollView:(UIScrollView *)scrollView {
    for (NSNumber *index in self.listDict) {
        if (self.listDict[index].listScrollView == scrollView) {
            return index.integerValue;
        }
    }
    return 0;
}

- (void)listDidAppear:(NSInteger)index {
    NSUInteger count = [self.dataSource numberOfListsInSmoothView:self];
    if (count <= 0 || index >= count) return;
    
    id<GKPageSmoothListViewDelegate> list = self.listDict[@(index)];
    if (list && [list respondsToSelector:@selector(listViewDidAppear)]) {
        [list listViewDidAppear];
    }
}

- (void)listDidDisappear:(NSInteger)index {
    NSUInteger count = [self.dataSource numberOfListsInSmoothView:self];
    if (count <= 0 || index >= count) return;
    
    id<GKPageSmoothListViewDelegate> list = self.listDict[@(index)];
    if (list && [list respondsToSelector:@selector(listViewDidDisappear)]) {
        [list listViewDidDisappear];
    }
}

// 为scrollView还原之前记录的属性
- (void)allowScrolling:(UIScrollView *)scrollView {
    scrollView.bounces = self.originBounces;
    scrollView.showsVerticalScrollIndicator = self.originShowsVerticalScrollIndicator;
}

- (void)forbidScrolling:(UIScrollView *)scrollView {
    [self setScrollView:scrollView offset:CGPointZero];
    scrollView.bounces = NO;
    scrollView.showsVerticalScrollIndicator = NO;
}

- (void)dragBegan {
    self.isOnTop = YES; // 开始滑动到吸顶, 吸顶后也保持这个状态
    [self setupShowingLayout];
}

- (void)dragDismiss {
    [UIView animateWithDuration:0.25 animations:^{
        CGRect frame = self.bottomContainerView.frame;
        frame.origin.y = self.frame.size.height - self.segmentedHeight;
        self.bottomContainerView.frame = frame;
    } completion:^(BOOL finished) {
        [self setupDismissLayout];
        
        self.isOnTop = NO;
        if ([self.delegate respondsToSelector:@selector(smoothViewDragEnded:isOnTop:)]) {
            [self.delegate smoothViewDragEnded:self isOnTop:self.isOnTop];
        }
    }];
}

- (void)dragShowing {
    [UIView animateWithDuration:0.25 animations:^{
        CGRect frame = self.bottomContainerView.frame;
        frame.origin.y = self.ceilPointHeight;
        self.bottomContainerView.frame = frame;
    } completion:^(BOOL finished) {
        if ([self.delegate respondsToSelector:@selector(smoothViewDragEnded:isOnTop:)]) {
            [self.delegate smoothViewDragEnded:self isOnTop:self.isOnTop];
        }
    }];
}

// 开始拖拽滑动到吸顶时做初始布局
- (void)setupShowingLayout {
    // 将headerContainerView添加到self
    if (self.headerContainerView.superview != self) {
        CGRect frame = self.headerContainerView.frame;
        // currentListScrollView.contentOffset.y+headerContainerHeight
        // 是header高度加内容已滚动高度. ???但为什么要设置frame?headerContainerView应该还在cell上?
        frame.origin.y = -(self.currentListScrollView.contentOffset.y + self.headerContainerHeight);
        self.headerContainerView.frame = frame;
        [self insertSubview:self.headerContainerView belowSubview:self.bottomContainerView];
    }
    
    // 将listCollectionView添加到bottomContainerView
    if (self.listCollectionView.superview != self.bottomContainerView) {
        CGRect frame = self.listCollectionView.frame;
        frame.origin.y = self.segmentedHeight;
        frame.size.height = self.bottomContainerView.frame.size.height - self.segmentedHeight;
        self.listCollectionView.frame = frame;
        [self.bottomContainerView addSubview:self.listCollectionView];
        self->_listCollectionView.headerContainerView = nil;
        
        // 记录当前列表的滑动位置
        self.currentListPanBeganContentOffsetY = self.currentListScrollView.contentOffset.y;
        
        // 内容scrollView的contentInset清零
        // ???: why
        for (id<GKPageSmoothListViewDelegate> list in self.listDict.allValues) {
            list.listScrollView.contentInset = UIEdgeInsetsZero;
            [self setScrollView:list.listScrollView offset:CGPointZero];
            
            CGRect frame = list.listView.frame;
            frame.size = self.listCollectionView.bounds.size;
            list.listView.frame = frame;
        }
    }
}

// 拖拽滑动还原时的布局
- (void)setupDismissLayout {
    // headerContainerView添加到当前内容scrollView的listHeader
    UIView *listHeader = [self listHeaderForListScrollView:self.currentListScrollView];
    if (self.headerContainerView.superview != listHeader) {
        CGRect frame = self.headerContainerView.frame;
        frame.origin.y = 0;
        self.headerContainerView.frame = frame;
        [listHeader addSubview:self.headerContainerView];
    }
    
    // collectionView添加到self, 设置frame, 在bottomContainerView下面准备露出来
    if (self.listCollectionView.superview != self) {
        self.listCollectionView.frame = self.bounds;
        [self insertSubview:self.listCollectionView belowSubview:self.bottomContainerView];
        self->_listCollectionView.headerContainerView = self.headerContainerView;
        
        // 设置内容scrollView的contentInset, contentOffset归零, 设置内容frame
        for (id<GKPageSmoothListViewDelegate> list in self.listDict.allValues) {
            list.listScrollView.contentInset = UIEdgeInsetsMake(self.headerContainerHeight, 0, 0, 0);
            [self setScrollView:list.listScrollView offset:CGPointZero];
            
            CGRect frame = list.listView.frame;
            frame.size = self.listCollectionView.bounds.size;
            list.listView.frame = frame;
        }
        
        // 当前内容scrollView滚动到吸顶之前的位置
        [self setScrollView:self.currentListScrollView offset:CGPointMake(0, self.currentListPanBeganContentOffsetY)];
    }
}

- (void)setScrollView:(UIScrollView *)scrollView offset:(CGPoint)offset {
    if (!CGPointEqualToPoint(scrollView.contentOffset, offset)) {
        scrollView.contentOffset = offset;
    }
}

#pragma mark - Getter
- (UICollectionView *)listCollectionView {
    if (!_listCollectionView) {
        UICollectionViewFlowLayout *layout = [UICollectionViewFlowLayout new];
        layout.scrollDirection = UICollectionViewScrollDirectionHorizontal;
        layout.minimumLineSpacing = 0;
        layout.minimumInteritemSpacing = 0;
        _listCollectionView = [[GKPageSmoothCollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
        _listCollectionView.dataSource = self;
        _listCollectionView.delegate = self;
        _listCollectionView.pagingEnabled = YES;
        _listCollectionView.bounces = NO;
        _listCollectionView.showsHorizontalScrollIndicator = NO;
        _listCollectionView.scrollsToTop = NO;
        [_listCollectionView registerClass:[UICollectionViewCell class] forCellWithReuseIdentifier:GKPageSmoothViewCellID];
        if (@available(iOS 11.0, *)) {
            _listCollectionView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
        }
        if (@available(iOS 10.0, *)) {
            _listCollectionView.prefetchingEnabled = NO;
        }
        _listCollectionView.headerContainerView = self.headerContainerView;
    }
    return _listCollectionView;
}

- (UIView *)headerContainerView {
    if (!_headerContainerView) {
        _headerContainerView = [UIView new];
    }
    return _headerContainerView;
}

- (UIView *)bottomContainerView {
    if (!_bottomContainerView) {
        _bottomContainerView = [UIView new];
        _bottomContainerView.backgroundColor = UIColor.whiteColor;
    }
    return _bottomContainerView;
}

- (UIPanGestureRecognizer *)panGesture {
    if (!_panGesture) {
        _panGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePanGesture:)];
        _panGesture.delegate = self;
    }
    return _panGesture;
}

@end
