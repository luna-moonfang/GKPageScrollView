//
//  TBViewController.m
//  ObjcExample
//
//  Created by 董恭甫 on 2022/3/30.
//

#import "TBViewController.h"
#import <GKNavigationBar/GKNavigationBar.h>

static void *listScrollView2Context = &listScrollView2Context;

@protocol TBPageSmoothListViewDelegate <NSObject>

- (UIView *)listView;
- (UIScrollView *)listScrollView;

@optional
// 对应collectionView willDisplayCell/didEndDisplayCell
- (void)listViewDidAppear;
- (void)listViewDidDisappear;

@end

@protocol TBPageSmoothViewDataSource <NSObject>

/// 返回页面的headerView视图
/// @param smoothView smoothView
- (UIView *)headerViewInSmoothView:(id/*GKPageSmoothView **/)smoothView;

/// 返回需要悬浮的分段视图
/// @param smoothView smoothView
- (UIView *)segmentedViewInSmoothView:(id/*GKPageSmoothView **/)smoothView;

/// 返回列表个数
/// @param smoothView smoothView
- (NSInteger)numberOfListsInSmoothView:(id/*GKPageSmoothView **/)smoothView;

/// 根据index初始化一个列表实例，列表需实现`GKPageSmoothListViewDelegate`代理
/// @param smoothView smoothView
/// @param index 列表索引
- (id<TBPageSmoothListViewDelegate>)smoothView:(id/*GKPageSmoothView **/)smoothView initListAtIndex:(NSInteger)index;

@end

@protocol TBPageSmoothViewDelegate <NSObject>

@optional
/// 列表容器滑动代理
/// @param smoothView smoothView
/// @param scrollView containerScrollView
- (void)smoothView:(id/*GKPageSmoothView **/)smoothView scrollViewDidScroll:(UIScrollView *)scrollView; // page滑动, 横向

/// 当前列表滑动代理
/// @param smoothView smoothView
/// @param scrollView 当前的列表scrollView
/// @param contentOffset 转换后的contentOffset
- (void)smoothView:(id/*GKPageSmoothView **/)smoothView listScrollViewDidScroll:(UIScrollView *)scrollView contentOffset:(CGPoint)contentOffset; // 内容滑动, 纵向, contentOffset带横向信息

/// 开始拖拽代理
/// @param smoothView smoothView
- (void)smoothViewDragBegan:(id/*GKPageSmoothView **/)smoothView; // 拖拽底部section/page

/// 结束拖拽代理
/// @param smoothView smoothView
/// @param isOnTop 是否通过拖拽滑动到顶部
- (void)smoothViewDragEnded:(id/*GKPageSmoothView **/)smoothView isOnTop:(BOOL)isOnTop; // 拖拽底部section/page

@end

#pragma mark -

@interface TBContentViewController : UITableViewController <TBPageSmoothListViewDelegate>

@end

@implementation TBContentViewController

- (void)viewDidLoad {
    [super viewDidLoad];
        
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"cell"];
}

#pragma mark - UITableViewDataSource & UITableViewDelegate

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return 40;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"cell" forIndexPath:indexPath];
    cell.textLabel.text = [NSString stringWithFormat:@"第%zd行", indexPath.row + 1];
    return cell;
}

#pragma mark - TBPageSmoothListViewDelegate

- (UIView *)listView {
    return self.view;
}

- (UIScrollView *)listScrollView {
    return self.tableView;
}

@end

#pragma mark -

@interface TBCollectionView : UICollectionView <UIGestureRecognizerDelegate>

@property (nonatomic, weak) UIView *headerContainerView; // 用于gr delegate方法判断

@end

@implementation TBCollectionView

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

#pragma mark -

@interface TBViewController () <UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout, JXCategoryViewDelegate, TBPageSmoothViewDataSource, TBPageSmoothViewDelegate>

@property (nonatomic, strong) NSMutableDictionary<NSNumber *, id<TBPageSmoothListViewDelegate>> *listDict;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, UIView *> *listHeaderDict;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, UIView *> *listFooterDict;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, id<TBPageSmoothListViewDelegate>> *listDict2;

@property (nonatomic, strong) UIView *titleView;

@property (nonatomic, strong) UIImageView *headerView;
@property (nonatomic, strong) JXCategorySubTitleView *categoryView;
@property (nonatomic, strong) JXCategoryIndicatorAlignmentLineView *lineView;
@property (nonatomic, strong) TBCollectionView *listCollectionView;
@property (nonatomic, strong) UIView *headerContainerView;
@property (nonatomic, strong) UIView *bottomContainerView;

// 第二组page结构
@property (nonatomic, strong) JXCategorySubTitleView *categoryView2;
@property (nonatomic, strong) JXCategoryIndicatorAlignmentLineView *lineView2;
@property (nonatomic, strong) TBCollectionView *listCollectionView2;

@property (nonatomic, assign) CGFloat headerContainerHeight; // headerHeight + segmentedHeight
@property (nonatomic, assign) CGFloat bottomContainerHeight;
@property (nonatomic, assign) CGFloat headerHeight;
@property (nonatomic, assign) CGFloat segmentedHeight;
@property (nonatomic, assign) CGFloat ceilPointHeight; // 吸顶时顶部保留的高度
@property (nonatomic, assign) CGFloat currentListInitializeContentOffsetY; // 内容scrollView初始化时的contentOffset位置, 可能需要滚动露出header部分
@property (nonatomic, assign) CGFloat currentHeaderContainerViewY; // headerContainerView作为self的subview时的y值, 用于横向滚动时记录header的位置, 帮助实现悬浮效果

@property (nonatomic, assign) CGFloat currentListInitializeContentOffsetY2;

@property (nonatomic, assign) NSInteger currentIndex;
@property (nonatomic, weak) UIScrollView *currentListScrollView;

@property (nonatomic, assign) NSInteger currentIndex2;
@property (nonatomic, weak) UIScrollView *currentListScrollView2;

@property (nonatomic, assign) BOOL bottomHover;

@end

@implementation TBViewController

- (instancetype)init {
    self = [super init];
    if (self) {
        _listDict = [NSMutableDictionary dictionary];
        _listDict2 = [NSMutableDictionary dictionary];
        _listHeaderDict = [NSMutableDictionary dictionary];
        _listFooterDict = [NSMutableDictionary dictionary];
        _ceilPointHeight = GK_STATUSBAR_NAVBAR_HEIGHT;
        _bottomHover = YES;
        
        _currentIndex = 0;
        _currentIndex2 = 0;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    self.gk_statusBarStyle = UIStatusBarStyleLightContent;
    self.gk_navBarAlpha = 0;
    self.gk_navBackgroundColor = GKColorRGB(123, 106, 89);
    self.gk_navTitle = @"个股";
    self.gk_navTitleColor = UIColor.whiteColor;
    
    self.edgesForExtendedLayout = UIRectEdgeNone;
    
    [self.headerContainerView addSubview:self.headerView];
    [self.headerContainerView addSubview:self.categoryView];
    
    [self.view addSubview:self.listCollectionView];
    // layout
    [self.listCollectionView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.edges.equalTo(self.view);
    }];
    
    self.categoryView.contentScrollView = self.listCollectionView;
    
    // height
    self.headerHeight = self.headerView.bounds.size.height;
    self.segmentedHeight = self.categoryView.bounds.size.height;
    self.headerContainerHeight = self.headerHeight + self.segmentedHeight;
    
    // layout headerContainerView
    CGSize size = self.view.bounds.size;
    self.headerView.frame = CGRectMake(0, 0, size.width, self.headerHeight);
    self.categoryView.frame = CGRectMake(0, self.headerHeight, size.width, self.segmentedHeight);
    
    // 启用吸底, 创建bottomContainerView
    if (self.bottomHover) {
        self.bottomContainerHeight = size.height - self.ceilPointHeight;
        
        self.bottomContainerView.frame = CGRectMake(0, size.height - self.segmentedHeight, size.width, size.height - self.ceilPointHeight);
        [self.view addSubview:self.bottomContainerView];
        
        self.categoryView2.frame = CGRectMake(0, 0, size.width, self.segmentedHeight);
        self.listCollectionView2.frame = CGRectMake(0, self.segmentedHeight, size.width, size.height - self.ceilPointHeight - self.segmentedHeight);
        
        [self.bottomContainerView addSubview:self.categoryView2];
        [self.bottomContainerView addSubview:self.listCollectionView2];
        
        self.categoryView2.contentScrollView = self.listCollectionView2;
    }
}

- (void)dealloc {
    for (id<TBPageSmoothListViewDelegate> listItem in self.listDict.allValues) {
        [listItem.listScrollView removeObserver:self forKeyPath:@"contentOffset"];
        [listItem.listScrollView removeObserver:self forKeyPath:@"contentSize"];
    }
}

- (void)viewSafeAreaInsetsDidChange {
    [super viewSafeAreaInsetsDidChange];
    
    CGRect rect = self.bottomContainerView.frame;
    rect.origin.y -= self.view.safeAreaInsets.bottom;
    self.bottomContainerView.frame = rect;
}

#pragma mark - UIScrollViewDelegate

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    // delegate
    if ([self respondsToSelector:@selector(smoothView:scrollViewDidScroll:)]) {
        [self smoothView:nil scrollViewDidScroll:scrollView];
    }
    
    CGFloat indexPercent = scrollView.contentOffset.x/scrollView.bounds.size.width;
    NSInteger index = floor(indexPercent);
    
    UIScrollView *listScrollView = self.listDict[@(index)].listScrollView;
    if (index != self.currentIndex &&
        indexPercent - index == 0 &&
        !(scrollView.isDragging || scrollView.isDecelerating) &&
        listScrollView.contentOffset.y <= -(self.segmentedHeight + self.ceilPointHeight)) {
        // 达到翻页条件, 执行翻页
        // -(segmentedHeight+ceilPointHeight) 是临界点y值, contentOffsetY小于临界值说明未吸顶
        [self horizontalScrollDidEndAtIndex:index];
    } else {
        // 翻页过程中, headerContainerView添加到self.view，达到悬浮的效果, 需要同步y值
        if (self.headerContainerView.superview != self.view) {
            CGRect frame = self.headerContainerView.frame;
            frame.origin.y = self.currentHeaderContainerViewY;
            self.headerContainerView.frame = frame;
            [self.view addSubview:self.headerContainerView];
        }
    }
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
    NSLog(@"scrollViewWillBeginDragging");
}

- (void)scrollViewWillEndDragging:(UIScrollView *)scrollView withVelocity:(CGPoint)velocity targetContentOffset:(inout CGPoint *)targetContentOffset {
    NSLog(@"scrollViewWillEndDragging");
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate {
    NSLog(@"scrollViewDidEndDragging");
}

- (void)scrollViewWillBeginDecelerating:(UIScrollView *)scrollView {
    NSLog(@"scrollViewWillBeginDecelerating");
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
    NSLog(@"scrollViewDidEndDecelerating");
    
    NSInteger index = scrollView.contentOffset.x / scrollView.bounds.size.width;
    [self horizontalScrollDidEndAtIndex:index];
//    self.panGesture.enabled = YES;
}

- (void)scrollViewDidEndScrollingAnimation:(UIScrollView *)scrollView {
    NSLog(@"scrollViewDidEndScrollingAnimation");
}

//- (BOOL)scrollViewShouldScrollToTop:(UIScrollView *)scrollView {}

//- (void)scrollViewDidScrollToTop:(UIScrollView *)scrollView {}

//- (void)scrollViewDidChangeAdjustedContentInset:(UIScrollView *)scrollView {}

#pragma mark - UICollectionViewDataSource

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return [self numberOfListsInSmoothView:collectionView];
}

- (__kindof UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    UICollectionViewCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"cellId" forIndexPath:indexPath];
    NSMutableDictionary *listDict = (collectionView == self.listCollectionView) ? self.listDict : self.listDict2;
    id<TBPageSmoothListViewDelegate> list = listDict[@(indexPath.item)];
    if (list == nil) {
        // init list
        list = [self smoothView:self initListAtIndex:indexPath.item];
        listDict[@(indexPath.item)] = list;
        
        // 触发list.view的加载/初始化
        [list.listView setNeedsLayout];
        [list.listView layoutIfNeeded];
        
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
        
        if (collectionView == self.listCollectionView) {
            // headerContainerView as contentInset
            listScrollView.contentInset = UIEdgeInsetsMake(self.headerContainerHeight, 0, self.bottomContainerHeight, 0);
            // 滚动到header的某个位置
            self.currentListInitializeContentOffsetY = -listScrollView.contentInset.top + MIN(-self.currentHeaderContainerViewY, (self.headerHeight - self.ceilPointHeight));
            [self setScrollView:listScrollView offset:CGPointMake(0, self.currentListInitializeContentOffsetY)];
            
            // 在contentInset的位置添加subview
            UIView *listHeader = [[UIView alloc] initWithFrame:CGRectMake(0, -self.headerContainerHeight, self.view.bounds.size.width, self.headerContainerHeight)];
            [listScrollView addSubview:listHeader];
            
            [listHeader addSubview:self.headerContainerView];
            
            // set headerContainerView's frame
            self.headerContainerView.frame = listHeader.bounds;
            
            self.listHeaderDict[@(indexPath.item)] = listHeader;
            
            // listFooter
            UIView *listFooter = [[UIView alloc] initWithFrame:CGRectMake(0, listScrollView.contentSize.height, self.view.bounds.size.width, self.bottomContainerHeight)];
            listFooter.backgroundColor = UIColor.yellowColor;
            [listScrollView addSubview:listFooter];
            self.bottomContainerView.frame = listFooter.bounds;
            [listFooter addSubview:self.bottomContainerView];
            self.listFooterDict[@(indexPath.item)] = listFooter;
            
            // kvo监听内容scrollview
            [listScrollView addObserver:self forKeyPath:@"contentOffset" options:NSKeyValueObservingOptionNew context:nil];
            [listScrollView addObserver:self forKeyPath:@"contentSize" options:NSKeyValueObservingOptionNew context:nil];
            
            // bug fix #69 修复首次进入时可能出现的headerView无法下拉的问题
    //        [listScrollView setContentOffset:listScrollView.contentOffset];
        } else {
            // 社区page在作为整体滚动时, 关闭自身的滚动
            listScrollView.scrollEnabled = NO;
            
            [listScrollView addObserver:self forKeyPath:@"contentOffset" options:NSKeyValueObservingOptionNew context:listScrollView2Context];
            [listScrollView addObserver:self forKeyPath:@"contentSize" options:NSKeyValueObservingOptionNew context:listScrollView2Context];
        }
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

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView {
    return 1;
}

#pragma mark - UICollectionViewDelegate

- (void)collectionView:(UICollectionView *)collectionView willDisplayCell:(UICollectionViewCell *)cell forItemAtIndexPath:(NSIndexPath *)indexPath {
    
}

- (void)collectionView:(UICollectionView *)collectionView didEndDisplayingCell:(UICollectionViewCell *)cell forItemAtIndexPath:(NSIndexPath *)indexPath {
    
}

#pragma mark - UICollectionViewDelegateFlowLayout

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)collectionViewLayout sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    NSMutableDictionary *listDict = (collectionView == self.listCollectionView) ? self.listDict : self.listDict2;
    for (id<TBPageSmoothListViewDelegate> list in listDict.allValues) {
        // 同时设置内容frame
        list.listView.frame = (CGRect){{0, 0}, collectionView.bounds.size};
    }
    return collectionView.bounds.size;
}

#pragma mark - JXCategoryViewDelegate

- (void)categoryView:(JXCategoryBaseView *)categoryView didClickSelectedItemAtIndex:(NSInteger)index {
//    [self.smoothView showingOnTop];
}

#pragma mark - TBPageSmoothViewDataSource

- (UIView *)headerViewInSmoothView:(id)smoothView {
    return self.headerView;
}

- (UIView *)segmentedViewInSmoothView:(id)smoothView {
    return self.categoryView;
}

- (NSInteger)numberOfListsInSmoothView:(id)smoothView {
    if (smoothView == self.listCollectionView) {
        return self.categoryView.titles.count;
    } else {
        return self.categoryView2.titles.count;
    }
}

- (id<TBPageSmoothListViewDelegate>)smoothView:(id)smoothView initListAtIndex:(NSInteger)index {
    TBContentViewController *vc = [[TBContentViewController alloc] init];
    return vc;
}

#pragma mark - TBPageSmoothViewDelegate

- (void)smoothView:(id)smoothView listScrollViewDidScroll:(UIScrollView *)scrollView contentOffset:(CGPoint)contentOffset {
    NSLog(@"contentOffset = %@", NSStringFromCGPoint(contentOffset));
//    if (smoothView.isOnTop) return;
    
    // 导航栏显隐
    CGFloat offsetY = contentOffset.y;
    CGFloat alpha = 0;
    if (offsetY <= 0) {
        alpha = 0;
    } else if (offsetY > 60) {
        alpha = 1;
        [self changeTitle:YES];
    } else {
        alpha = offsetY / 60;
        [self changeTitle:NO];
    }
    self.gk_navBarAlpha = alpha;
}

#pragma mark - KVO

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context {
    if (context == listScrollView2Context) {
        if ([keyPath isEqualToString:@"contentOffset"]) {
            UIScrollView *scrollView = (UIScrollView *)object;
            if (scrollView != nil) {
                [self listScrollViewDidScroll2:scrollView];
            }
        } else if ([keyPath isEqualToString:@"contentSize"]) {
            UIScrollView *scrollView = (UIScrollView *)object;
            if (scrollView != nil) {
                [self listScrollViewDidScroll2:scrollView];
            }
        }
        return;
    }
    
    if ([keyPath isEqualToString:@"contentOffset"]) {
        UIScrollView *scrollView = (UIScrollView *)object;
        if (scrollView != nil) {
            [self listScrollViewDidScroll:scrollView];
        }
    } else if ([keyPath isEqualToString:@"contentSize"]) {
        UIScrollView *scrollView = (UIScrollView *)object;
        if (scrollView != nil) {
            [self listScrollViewDidScroll:scrollView];
        }
    }
}

#pragma mark - Private Methods

- (void)listScrollViewDidScroll:(UIScrollView *)scrollView {
    NSLog(@"%@", NSStringFromCGPoint(scrollView.contentOffset));
    
    // 翻页时不处理内容滚动
    // 似乎只有第一次翻页时会触发
    if (self.listCollectionView.isDragging ||
        self.listCollectionView.isDecelerating) {
        return;
    }
    
    // TODO: 处理吸顶
    
    // 不在顶部，通过列表scrollView滑动确定悬浮位置
    NSInteger listIndex = [self listIndexForListScrollView:scrollView];
    if (listIndex != self.currentIndex) return;
    self.currentListScrollView = scrollView;
    
    // contentOffsetY 从0开始
    CGFloat contentOffsetY = scrollView.contentOffset.y + self.headerContainerHeight;
    
    // headerView滚动, segment1未吸顶
    if (contentOffsetY < (self.headerHeight - self.ceilPointHeight)) {
        self.currentHeaderContainerViewY = -contentOffsetY;
        
        // 同步contentOffset
        for (id<TBPageSmoothListViewDelegate> list in self.listDict.allValues) {
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
    }
    // segment1吸顶
    else if (contentOffsetY < (self.headerContainerHeight + scrollView.contentSize.height - self.ceilPointHeight)) {
        // headerContainerView添加到self.view
        if (self.headerContainerView.superview != self.view) {
            CGRect frame = self.headerContainerView.frame;
            frame.origin.y = - (self.headerHeight - self.ceilPointHeight);
            self.headerContainerView.frame = frame;
            [self.view addSubview:self.headerContainerView];
        }
    }
    // segment2吸顶
    else {
        // bottomContainerView添加到self.view, 吸顶
    }
    
    // 处理bottomContainerView
    // 默认segment2吸底, 如果page1剩余部分不足一屏也可能不吸底
    CGFloat visibleHeight = self.view.bounds.size.height;
    if (@available(iOS 11.0, *)) {
        visibleHeight -= self.view.safeAreaInsets.bottom;
    }
    // 滚动未超过(整体高度-可见高度), 吸底
    if (contentOffsetY < (self.headerContainerHeight + scrollView.contentSize.height - visibleHeight)) {
        // bottomContainerView添加到self.view, 吸底
        if (self.bottomContainerView.superview != self.view) {
            CGRect frame = self.bottomContainerView.frame;
            frame.origin.y = self.view.bounds.size.height - self.segmentedHeight;
            if (@available(iOS 11.0, *)) {
                frame.origin.y -= self.view.safeAreaInsets.bottom;
            }
            self.bottomContainerView.frame = frame;
            [self.view addSubview:self.bottomContainerView];
        }
    }
    // 滚动超过(整体高度-可见高度), 拉起segment2, 不吸底
    else {
        // bottomContainerView添加到listFooter
        UIView *listFooter = [self listFooterForListScrollView:scrollView];
        if (self.bottomContainerView.superview != listFooter) {
            CGRect frame = self.bottomContainerView.frame;
            frame.origin.y = 0;
            self.bottomContainerView.frame = frame;
            [listFooter addSubview:self.bottomContainerView];
        }
        
        if (contentOffsetY < (self.headerContainerHeight + scrollView.contentSize.height - self.segmentedHeight - self.ceilPointHeight)) {
            self.headerContainerView.hidden = NO;
        }
        else {
            self.headerContainerView.hidden = YES;
            if (contentOffsetY < (self.headerContainerHeight + scrollView.contentSize.height - self.ceilPointHeight)) {
                // bottomContainerView添加到listFooter
            } else {
                // bottomContainerView添加到self.view, 吸顶
                if (self.bottomContainerView.superview != self.view) {
                    CGRect frame = self.bottomContainerView.frame;
                    frame.origin.y = self.ceilPointHeight;
//                    if (@available(iOS 11.0, *)) {
//                        frame.origin.y -= self.view.safeAreaInsets.bottom;
//                    }
                    self.bottomContainerView.frame = frame;
                    [self.view addSubview:self.bottomContainerView];
                }
            }
            self.listDict2[@(self.currentIndex2)].listScrollView.scrollEnabled = YES;
        }
    }
    
    // 修改导航栏用
    CGPoint contentOffset = CGPointMake(scrollView.contentOffset.x, contentOffsetY);
    [self smoothView:nil listScrollViewDidScroll:scrollView contentOffset:contentOffset];
}

- (void)listScrollViewDidScroll2:(UIScrollView *)scrollView {
    NSLog(@"(2)%@", NSStringFromCGPoint(scrollView.contentOffset));
    if (scrollView.contentOffset.y < 0) {
        scrollView.scrollEnabled = NO;
        // bottomContainerView添加到listFooter
        UIView *listFooter = self.listFooterDict[@(self.currentIndex)];
        if (self.bottomContainerView.superview != listFooter) {
            CGRect frame = self.bottomContainerView.frame;
            frame.origin.y = 0;
            self.bottomContainerView.frame = frame;
            [listFooter addSubview:self.bottomContainerView];
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

- (UIView *)listFooterForListScrollView:(UIScrollView *)scrollView {
    for (NSNumber *index in self.listDict) {
        if (self.listDict[index].listScrollView == scrollView) {
            return self.listFooterDict[index];
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

- (void)setScrollView:(UIScrollView *)scrollView offset:(CGPoint)offset {
    if (!CGPointEqualToPoint(scrollView.contentOffset, offset)) {
        scrollView.contentOffset = offset;
    }
}

- (void)changeTitle:(BOOL)isShow {
    if (isShow) {
        if (self.gk_navTitle == nil) return;
        self.gk_navTitle = nil;
        self.gk_navTitleView = self.titleView;
    } else {
        if (self.gk_navTitleView == nil) return;
        self.gk_navTitle = @"电影";
        self.gk_navTitleView = nil;
    }
}

- (void)horizontalScrollDidEndAtIndex:(NSInteger)index {
    // set currentIndex & currentListScrollView
    self.currentIndex = index;
    UIView *listHeader = self.listHeaderDict[@(index)];
    UIScrollView *listScrollView = self.listDict[@(index)].listScrollView;
    self.currentListScrollView = listScrollView;
    
    // 已吸顶或在执行吸顶操作的过程中, 什么都不用做, 直接返回
//    if (self.isOnTop) return;
    
    // 有listHeader, 且未达到吸顶的临界点, 说明在滑动过程中把headerContainerView临时放入self来实现悬浮效果
    // 或者至少headerContainerView还在上一个内容vc的listHeader
    // 所以滚动结束后把headerContainerView添加到当前内容vc的listHeader
    if (listHeader != nil &&
        listScrollView.contentOffset.y <= -(self.segmentedHeight + self.ceilPointHeight)) {
        
        // 滚动结束, 确定位置, headerContainerView从self.view回到listHeader
        CGRect frame = self.headerContainerView.frame;
        frame.origin.y = 0;
        self.headerContainerView.frame = frame;
        if (self.headerContainerView.superview != listHeader) {
            [listHeader addSubview:self.headerContainerView];
        }
    }
}

#pragma mark - Getters & Setters

- (UIImageView *)headerView {
    if (!_headerView) {
        UIImage *image = [UIImage imageNamed:@"douban"];
        _headerView = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, image.size.width, image.size.height)];
        _headerView.image = image;
    }
    return _headerView;
}

- (JXCategorySubTitleView *)categoryView {
    if (!_categoryView) {
        _categoryView = [[JXCategorySubTitleView alloc] initWithFrame:CGRectMake(0, 10, self.view.frame.size.width, 40)];
        _categoryView.backgroundColor = UIColor.whiteColor;
        _categoryView.averageCellSpacingEnabled = NO;
        _categoryView.contentEdgeInsetLeft = 16;
        _categoryView.delegate = self;
        _categoryView.titles = @[@"Overview", @"Options", @"Analysis", @"Company"];
        _categoryView.titleFont = [UIFont systemFontOfSize:16];
        _categoryView.titleColor = UIColor.grayColor;
        _categoryView.titleSelectedColor = UIColor.blackColor;
//        _categoryView.subTitles = @[@"342", @"2004"];
        _categoryView.subTitleFont = [UIFont systemFontOfSize:11];
        _categoryView.subTitleColor = UIColor.grayColor;
        _categoryView.subTitleSelectedColor = UIColor.grayColor;
        _categoryView.positionStyle = JXCategorySubTitlePositionStyle_Right;
        _categoryView.alignStyle = JXCategorySubTitleAlignStyle_Top;
        _categoryView.cellSpacing = 30;
        _categoryView.cellWidthIncrement = 0;
        _categoryView.ignoreSubTitleWidth = YES;
        
        JXCategoryIndicatorLineView *lineView = [JXCategoryIndicatorLineView new];
        lineView.indicatorColor = UIColor.blackColor;
        _categoryView.indicators = @[self.lineView];
        
//        _categoryView.contentScrollView = self.smoothView.listCollectionView;
    }
    return _categoryView;
}

-  (JXCategoryIndicatorAlignmentLineView *)lineView {
    if (!_lineView) {
        _lineView = [JXCategoryIndicatorAlignmentLineView new];
        _lineView.indicatorColor = UIColor.blackColor;
    }
    return _lineView;
}

- (UICollectionView *)listCollectionView {
    if (!_listCollectionView) {
        UICollectionViewFlowLayout *layout = [UICollectionViewFlowLayout new];
        layout.scrollDirection = UICollectionViewScrollDirectionHorizontal;
        layout.minimumLineSpacing = 0;
        layout.minimumInteritemSpacing = 0;
        _listCollectionView = [[TBCollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
        _listCollectionView.dataSource = self;
        _listCollectionView.delegate = self;
        _listCollectionView.pagingEnabled = YES;
        _listCollectionView.bounces = NO;
        _listCollectionView.showsHorizontalScrollIndicator = NO;
        _listCollectionView.scrollsToTop = NO;
        [_listCollectionView registerClass:[UICollectionViewCell class] forCellWithReuseIdentifier:@"cellId"];
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

- (UIView *)titleView {
    if (!_titleView) {
        _titleView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.frame.size.width - 100, 44.0f)];
        
        UIImage *image = [UIImage imageNamed:@"db_title"];
        UIImageView *imgView = [[UIImageView alloc] initWithImage:image];
        imgView.frame = CGRectMake(0, 0, 44.0f * image.size.width / image.size.height, 44.0f);
        [_titleView addSubview:imgView];
    }
    return _titleView;
}

- (JXCategorySubTitleView *)categoryView2 {
    if (!_categoryView2) {
        _categoryView2 = [[JXCategorySubTitleView alloc] initWithFrame:CGRectMake(0, 10, self.view.frame.size.width, 40)];
        _categoryView2.backgroundColor = UIColor.whiteColor;
        _categoryView2.averageCellSpacingEnabled = NO;
        _categoryView2.contentEdgeInsetLeft = 16;
        _categoryView2.delegate = self;
        _categoryView2.titles = @[@"News", @"Posts", @"Fillings"];
        _categoryView2.titleFont = [UIFont systemFontOfSize:16];
        _categoryView2.titleColor = UIColor.grayColor;
        _categoryView2.titleSelectedColor = UIColor.blackColor;
        _categoryView2.alignStyle = JXCategorySubTitleAlignStyle_Top;
        _categoryView2.cellSpacing = 30;
        _categoryView2.cellWidthIncrement = 0;
        _categoryView2.ignoreSubTitleWidth = YES;
        _categoryView2.indicators = @[self.lineView2];
    }
    return _categoryView2;
}

-  (JXCategoryIndicatorAlignmentLineView *)lineView2 {
    if (!_lineView2) {
        _lineView2 = [JXCategoryIndicatorAlignmentLineView new];
        _lineView2.indicatorColor = UIColor.blackColor;
    }
    return _lineView2;
}

- (UICollectionView *)listCollectionView2 {
    if (!_listCollectionView2) {
        UICollectionViewFlowLayout *layout = [UICollectionViewFlowLayout new];
        layout.scrollDirection = UICollectionViewScrollDirectionHorizontal;
        layout.minimumLineSpacing = 0;
        layout.minimumInteritemSpacing = 0;
        _listCollectionView2 = [[TBCollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
        _listCollectionView2.dataSource = self;
        _listCollectionView2.delegate = self;
        _listCollectionView2.pagingEnabled = YES;
        _listCollectionView2.bounces = NO;
        _listCollectionView2.showsHorizontalScrollIndicator = NO;
        _listCollectionView2.scrollsToTop = NO;
        [_listCollectionView2 registerClass:[UICollectionViewCell class] forCellWithReuseIdentifier:@"cellId"];
        if (@available(iOS 11.0, *)) {
            _listCollectionView2.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
        }
        if (@available(iOS 10.0, *)) {
            _listCollectionView2.prefetchingEnabled = NO;
        }
    }
    return _listCollectionView2;
}

@end
