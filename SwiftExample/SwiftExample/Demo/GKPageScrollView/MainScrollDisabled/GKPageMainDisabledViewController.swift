//
//  GKPageMainDisabledViewController.swift
//  SwiftExample
//
//  Created by gaokun on 2021/7/19.
//

import UIKit
import GKPageScrollView
import JXSegmentedViewExt

class GKPageMainDisabledViewController: GKDemoBaseViewController {
    var titleDataSource = JXSegmentedTitleDataSource()
    
    lazy var pageScrollView: GKPageScrollView! = {
        let pageScrollView = GKPageScrollView(delegate: self)
        pageScrollView.isLazyLoadList = true
        pageScrollView.listContainerView.scrollView.gk_openGestureHandle = true
        pageScrollView.isMainScrollDisabled = true
        return pageScrollView
    }()
    
    lazy var headerView: UIImageView = {
        let headerView = UIImageView(frame: CGRect(x: 0, y: 0, width: kScreenW, height: kBaseHeaderHeight))
        headerView.contentMode = .scaleAspectFill
        headerView.clipsToBounds = true
        headerView.image = UIImage(named: "test")
        return headerView
    }()
    
    let titles = ["UITableView", "UICollectionView", "UIScrollView"]
    
    lazy var segmentedView: JXSegmentedView = {
        titleDataSource.titles = self.titles
        titleDataSource.titleNormalColor = UIColor.gray
        titleDataSource.titleSelectedColor = UIColor.red
        titleDataSource.titleNormalFont = UIFont.systemFont(ofSize: 15.0)
        titleDataSource.titleSelectedFont = UIFont.systemFont(ofSize: 15.0)
        titleDataSource.reloadData(selectedIndex: 0)
        
        var segmentedView = JXSegmentedView(frame: CGRect(x: 0, y: 0, width: kScreenW, height: kBaseSegmentHeight))
        segmentedView.dataSource = titleDataSource
        
        segmentedView.contentScrollView = self.pageScrollView.listContainerView.scrollView
        
        return segmentedView
    }()
    
    
    override func viewDidLoad() {
        super.viewDidLoad()

        self.gk_navBarAlpha = 0;
        self.gk_navTitle = "禁止主页滑动"
        self.gk_navTitleColor = .white
        self.gk_statusBarStyle = .lightContent;
        
        self.view.addSubview(self.pageScrollView)
        self.pageScrollView.snp.makeConstraints { (make) in
            make.edges.equalTo(self.view)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.pageScrollView.reloadData()
        }
    }
}

extension GKPageMainDisabledViewController: GKPageScrollViewDelegate {
    func headerView(in pageScrollView: GKPageScrollView) -> UIView {
        return self.headerView
    }
    
    func segmentedView(in pageScrollView: GKPageScrollView) -> UIView {
        return self.segmentedView
    }
    
    func numberOfLists(in pageScrollView: GKPageScrollView) -> Int {
        return self.titleDataSource.titles.count
    }
    
    func pageScrollView(_ pageScrollView: GKPageScrollView, initListAtIndex index: Int) -> GKPageListViewDelegate {
        let listVC = GKBaseListViewController(listType: GKBaseListType(rawValue: index) ?? .UITableView)
        listVC.shouldLoadData = true
        return listVC
    }
}
