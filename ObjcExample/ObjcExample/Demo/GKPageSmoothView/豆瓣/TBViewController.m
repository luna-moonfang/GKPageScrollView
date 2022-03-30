//
//  TBViewController.m
//  ObjcExample
//
//  Created by 董恭甫 on 2022/3/30.
//

#import "TBViewController.h"
#import <GKNavigationBar/GKNavigationBar.h>

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

@property (nonatomic, strong) UIView *titleView;

@property (nonatomic, strong) UIImageView *headerView;
@property (nonatomic, strong) JXCategorySubTitleView *categoryView;
@property (nonatomic, strong) JXCategoryIndicatorAlignmentLineView *lineView;
@property (nonatomic, strong) TBCollectionView *listCollectionView;
@property (nonatomic, strong) UIView *headerContainerView;
@property (nonatomic, strong) UIView *bottomContainerView;

@property (nonatomic, assign) CGFloat headerContainerHeight; // headerHeight + segmentedHeight
@property (nonatomic, assign) CGFloat headerHeight;
@property (nonatomic, assign) CGFloat segmentedHeight;
@property (nonatomic, assign) CGFloat ceilPointHeight; // 吸顶时顶部保留的高度
@property (nonatomic, assign) CGFloat currentListInitializeContentOffsetY; // 内容scrollView初始化时的contentOffset位置, 可能需要滚动露出header部分
@property (nonatomic, assign) CGFloat currentHeaderContainerViewY; // headerContainerView作为self的subview时的y值, 用于横向滚动时记录header的位置, 帮助实现悬浮效果

@property (nonatomic, assign) NSInteger currentIndex;
@property (nonatomic, weak) UIScrollView *currentListScrollView;

@property (nonatomic, assign) BOOL bottomHover;

@end

@implementation TBViewController

- (instancetype)init {
    self = [super init];
    if (self) {
        _listDict = [NSMutableDictionary dictionary];
        _listHeaderDict = [NSMutableDictionary dictionary];
        _ceilPointHeight = GK_STATUSBAR_NAVBAR_HEIGHT;
        _bottomHover = YES;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    self.gk_statusBarStyle = UIStatusBarStyleLightContent;
    self.gk_navBarAlpha = 0;
    self.gk_navBackgroundColor = GKColorRGB(123, 106, 89);
    self.gk_navTitle = @"电影";
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
}

- (void)dealloc {
    for (id<TBPageSmoothListViewDelegate> listItem in self.listDict.allValues) {
        [listItem.listScrollView removeObserver:self forKeyPath:@"contentOffset"];
        [listItem.listScrollView removeObserver:self forKeyPath:@"contentSize"];
    }
}

#pragma mark - UICollectionViewDataSource

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return [self numberOfListsInSmoothView:nil];
}

- (__kindof UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    UICollectionViewCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"cellId" forIndexPath:indexPath];
    id<TBPageSmoothListViewDelegate> list = self.listDict[@(indexPath.item)];
    if (list == nil) {
        // init list
        list = [self smoothView:self initListAtIndex:indexPath.item];
        self.listDict[@(indexPath.item)] = list;
        
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
        
        // headerContainerView as contentInset
        listScrollView.contentInset = UIEdgeInsetsMake(self.headerContainerHeight, 0, 0, 0);
        // 滚动到header顶部
        self.currentListInitializeContentOffsetY = -listScrollView.contentInset.top;
        [self setScrollView:listScrollView offset:CGPointMake(0, self.currentListInitializeContentOffsetY)];
        
        // 在contentInset的位置添加subview
        UIView *listHeader = [[UIView alloc] initWithFrame:CGRectMake(0, -self.headerContainerHeight, self.view.bounds.size.width, self.headerContainerHeight)];
        [listScrollView addSubview:listHeader];
        
        [listHeader addSubview:self.headerContainerView];
        
        // set headerContainerView's frame
        self.headerContainerView.frame = listHeader.bounds;
        
        self.listHeaderDict[@(indexPath.item)] = listHeader;
        
        // kvo监听内容scrollview
        [listScrollView addObserver:self forKeyPath:@"contentOffset" options:NSKeyValueObservingOptionNew context:nil];
        [listScrollView addObserver:self forKeyPath:@"contentSize" options:NSKeyValueObservingOptionNew context:nil];
        
        // bug fix #69 修复首次进入时可能出现的headerView无法下拉的问题
//        [listScrollView setContentOffset:listScrollView.contentOffset];
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
    for (id<TBPageSmoothListViewDelegate> list in self.listDict.allValues) {
        // 同时设置内容frame
        list.listView.frame = (CGRect){{0, 0}, self.listCollectionView.bounds.size};
    }
    return self.listCollectionView.bounds.size;
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
    return self.categoryView.titles.count;
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
    if ([keyPath isEqualToString:@"contentOffset"]) {
        UIScrollView *scrollView = (UIScrollView *)object;
        if (scrollView != nil) {
            [self listScrollViewDidScroll:scrollView];
        }
    } else if ([keyPath isEqualToString:@"contentSize"]) {
        
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
    
    CGFloat contentOffsetY = scrollView.contentOffset.y + self.headerContainerHeight;
    
    if (contentOffsetY < (self.headerHeight - self.ceilPointHeight)) {
        // 在可滚动范围内, 没有吸顶, 是否吸底待确认
        
        self.currentHeaderContainerViewY = -contentOffsetY;
        
        // 同步contentOffset
//        for (id<TBPageSmoothListViewDelegate> list in self.listDict.allValues) {
//            if (list.listScrollView != scrollView) {
//                [list.listScrollView setContentOffset:scrollView.contentOffset animated:NO];
//            }
//        }
        
        // headerContainerView放回listHeader
        UIView *listHeader = [self listHeaderForListScrollView:scrollView];
        if (self.headerContainerView.superview != listHeader) {
            CGRect frame = self.headerContainerView.frame;
            frame.origin.y = 0;
            self.headerContainerView.frame = frame;
            [listHeader addSubview:self.headerContainerView];
        }
    } else {
        // 吸顶
        // 滚动已经超过header保留的距离(ceilPointHeight)
        
        // self添加headerContainerView, 把segment部分固定在顶部
        if (self.headerContainerView.superview != self.view) {
            CGRect frame = self.headerContainerView.frame;
            frame.origin.y = - (self.headerHeight - self.ceilPointHeight);
            self.headerContainerView.frame = frame;
            [self.view addSubview:self.headerContainerView];
        }
    }
    
    // 修改导航栏用
    CGPoint contentOffset = CGPointMake(scrollView.contentOffset.x, contentOffsetY);
    [self smoothView:nil listScrollViewDidScroll:scrollView contentOffset:contentOffset];
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
        _categoryView.titles = @[@"影评", @"讨论"];
        _categoryView.titleFont = [UIFont systemFontOfSize:16];
        _categoryView.titleColor = UIColor.grayColor;
        _categoryView.titleSelectedColor = UIColor.blackColor;
        _categoryView.subTitles = @[@"342", @"2004"];
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

@end
