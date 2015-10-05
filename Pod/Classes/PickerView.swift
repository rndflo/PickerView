//
//  FAPickerView.swift
//
//  Created by Filipe Alvarenga on 19/05/15.
//  Copyright (c) 2015 Filipe Alvarenga. All rights reserved.
//

import UIKit

// MARK: - Protocols

public protocol PickerViewDataSource {
    func numberOfRowsInPickerView(pickerView: PickerView) -> Int
    func pickerView(pickerView: PickerView, titleForRow row:Int) -> String
}

public protocol PickerViewDelegate {
    func pickerView(pickerView: PickerView, didSelectRow row: Int)
    func heightForRowInPickerView(pickerView: PickerView) -> CGFloat
    func styleForLabel(label: UILabel, inPickerView pickerView: PickerView)
    func styleForHighlightedLabel(label: UILabel, inPickerView pickerView: PickerView)
}

public class PickerView: UIView {
    
    // MARK: Nested Types
    
    class SimplePickerTableViewCell: UITableViewCell {
        lazy var titleLabel: UILabel = {
            let titleLabel = UILabel(frame: CGRect(x: 0.0, y: 0.0, width: self.contentView.frame.width, height: self.contentView.frame.height))
            
            return titleLabel
        }()
    }
    
    public enum ScrollingStyle: Int {
        case Default, Infinite
    }
    
    public enum SelectionStyle: Int {
        case None, DefaultIndicator, Overlay, Image
    }
    
    // MARK: Properties
    
    var enabled = true {
        didSet {
            if enabled {
                turnPickerViewOn()
            } else {
                turnPickerViewOff()
            }
        }
    }
    
    var selectionOverlayH: NSLayoutConstraint!
    var selectionImageH: NSLayoutConstraint!
    var pickerCellBackgroundColor: UIColor?
    
    var numberOfRowsByDataSource: Int {
        get {
            return dataSource?.numberOfRowsInPickerView(self) ?? 0
        }
    }
    
    var rowHeight: CGFloat {
        get {
            return delegate?.heightForRowInPickerView(self) ?? 0
        }
    }
    
    override public var backgroundColor: UIColor? {
        didSet {
            self.tableView.backgroundColor = self.backgroundColor
            self.pickerCellBackgroundColor = self.backgroundColor
        }
    }
    
    let pickerViewCellIdentifier = "pickerViewCell"
    
    public var dataSource: PickerViewDataSource?
    public var delegate: PickerViewDelegate?
    
    public lazy var defaultSelectionIndicator: UIView = {
        let selectionIndicator = UIView()
        selectionIndicator.backgroundColor = .blackColor()
        selectionIndicator.alpha = 0.0
        
        return selectionIndicator
    }()
    
    public lazy var selectionOverlay: UIView = {
        let selectionOverlay = UIView()
        selectionOverlay.backgroundColor = .blackColor()
        selectionOverlay.alpha = 0.0
        
        return selectionOverlay
    }()
    
    public lazy var selectionImageView: UIImageView = {
        let selectionImageView = UIImageView()
        selectionImageView.alpha = 0.0
        
        return selectionImageView
    }()
    
    lazy var tableView: UITableView = {
        let tableView = UITableView()
        
        return tableView
    }()
    
    var infinityRowsMultiplier: Int = 1
    public var currentSelectedRow: Int = 0
    
    var firstTimeOrientationChanged = true
    var orientationChanged = false
    var isScrolling = false
    var setupHasBeenDone = false
    
    public var scrollingStyle = ScrollingStyle.Default {
        didSet {
            switch scrollingStyle {
            case .Default:
                infinityRowsMultiplier = 1
            case .Infinite:
                infinityRowsMultiplier = generateInfinityRowsMultiplier()
            }
        }
    }
    
    public var selectionStyle = SelectionStyle.None {
        didSet {
            switch selectionStyle {
            case .DefaultIndicator:
                defaultSelectionIndicator.alpha = 1.0
                selectionOverlay.alpha = 0.0
                selectionImageView.alpha = 0.0
            case .Overlay:
                selectionOverlay.alpha = 0.25
                defaultSelectionIndicator.alpha = 0.0
                selectionImageView.alpha = 0.0
            case .Image:
                selectionImageView.alpha = 1.0
                selectionOverlay.alpha = 0.0
                defaultSelectionIndicator.alpha = 0.0
            case .None:
                selectionOverlay.alpha = 0.0
                defaultSelectionIndicator.alpha = 0.0
                selectionImageView.alpha = 0.0
            }
        }
    }
    
    // MARK: Initialization
    
    required public init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
    }
    
    // MARK: Subviews Setup
    
    func setup() {
        infinityRowsMultiplier = generateInfinityRowsMultiplier()
        
        // Setup subviews constraints and apperance
        translatesAutoresizingMaskIntoConstraints = false
        setupTableView()
        setupSelectionOverlay()
        setupSelectionImageView()
        setupDefaultSelectionIndicator()
        
        // Setup UITableView data source & delegate in background
        // Reason: When FAPickerView scrollingStyle is set to .Infinite and the data source is huge, setting UITableView data source & delegate
        // on main queue can causes a little delay in the transition animation (push or modal animation)
        let priority = DISPATCH_QUEUE_PRIORITY_BACKGROUND
        dispatch_async(dispatch_get_global_queue(priority, 0)) {
            self.tableView.delegate = self
            self.tableView.dataSource = self
            
            dispatch_async(dispatch_get_main_queue(),{
                // Some UI Adjustments we need to do after setting UITableView data source & delegate.
                self.configureFirstSelection()
                self.adjustSelectionOverlayHeightConstraint()
            })
        }
    }
    
    private func setupTableView() {
        tableView.backgroundColor = .clearColor()
        tableView.separatorStyle = .None
        tableView.separatorColor = .None
        tableView.allowsSelection = true
        tableView.allowsMultipleSelection = false
        tableView.showsVerticalScrollIndicator = false
        tableView.showsHorizontalScrollIndicator = false
        tableView.scrollsToTop = false
        tableView.registerClass(SimplePickerTableViewCell.classForCoder(), forCellReuseIdentifier: self.pickerViewCellIdentifier)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(tableView)
        
        // Add constraints to tableView
        let tableViewH = NSLayoutConstraint(item: tableView, attribute: .Height, relatedBy: .Equal, toItem: self,
                                                attribute: .Height, multiplier: 1, constant: 0)
        addConstraint(tableViewH)
        
        let tableViewW = NSLayoutConstraint(item: tableView, attribute: .Width, relatedBy: .Equal, toItem: self,
                                                attribute: .Width, multiplier: 1, constant: 0)
        addConstraint(tableViewW)
        
        let tableViewL = NSLayoutConstraint(item: tableView, attribute: .Leading, relatedBy: .Equal, toItem: self,
                                                attribute: .Leading, multiplier: 1, constant: 0)
        addConstraint(tableViewL)
        
        let tableViewTop = NSLayoutConstraint(item: tableView, attribute: .Top, relatedBy: .Equal, toItem: self,
                                                attribute: .Top, multiplier: 1, constant: 0)
        addConstraint(tableViewTop)
        
        let tableViewBottom = NSLayoutConstraint(item: tableView, attribute: .Bottom, relatedBy: .Equal, toItem: self,
                                                    attribute: .Bottom, multiplier: 1, constant: 0)
        addConstraint(tableViewBottom)
        
        let tableViewT = NSLayoutConstraint(item: tableView, attribute: .Trailing, relatedBy: .Equal, toItem: self,
                                                attribute: .Trailing, multiplier: 1, constant: 0)
        addConstraint(tableViewT)
    }
    
    private func setupSelectionOverlay() {
        selectionOverlay.userInteractionEnabled = false
        selectionOverlay.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(selectionOverlay)
        
        selectionOverlayH = NSLayoutConstraint(item: selectionOverlay, attribute: .Height, relatedBy: .Equal, toItem: nil,
                                                attribute: .NotAnAttribute, multiplier: 1, constant: rowHeight)
        self.addConstraint(selectionOverlayH)
        
        let selectionOverlayW = NSLayoutConstraint(item: selectionOverlay, attribute: .Width, relatedBy: .Equal, toItem: self,
                                                    attribute: .Width, multiplier: 1, constant: 0)
        addConstraint(selectionOverlayW)
        
        let selectionOverlayL = NSLayoutConstraint(item: selectionOverlay, attribute: .Leading, relatedBy: .Equal, toItem: self,
                                                    attribute: .Leading, multiplier: 1, constant: 0)
        addConstraint(selectionOverlayL)
        
        let selectionOverlayT = NSLayoutConstraint(item: selectionOverlay, attribute: .Trailing, relatedBy: .Equal, toItem: self,
                                                    attribute: .Trailing, multiplier: 1, constant: 0)
        addConstraint(selectionOverlayT)
        
        let selectionOverlayY = NSLayoutConstraint(item: selectionOverlay, attribute: .CenterY, relatedBy: .Equal, toItem: self,
                                                    attribute: .CenterY, multiplier: 1, constant: 0)
        addConstraint(selectionOverlayY)
    }
    
    private func setupSelectionImageView() {
        selectionImageView.userInteractionEnabled = false
        selectionImageView.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(selectionImageView)
        
        selectionImageH = NSLayoutConstraint(item: selectionImageView, attribute: .Height, relatedBy: .Equal, toItem: nil,
                                                attribute: .NotAnAttribute, multiplier: 1, constant: rowHeight)
        self.addConstraint(selectionImageH)
        
        let selectionImageW = NSLayoutConstraint(item: selectionImageView, attribute: .Width, relatedBy: .Equal, toItem: self,
                                                    attribute: .Width, multiplier: 1, constant: 0)
        addConstraint(selectionImageW)
        
        let selectionImageL = NSLayoutConstraint(item: selectionImageView, attribute: .Leading, relatedBy: .Equal, toItem: self,
                                                    attribute: .Leading, multiplier: 1, constant: 0)
        addConstraint(selectionImageL)
        
        let selectionImageT = NSLayoutConstraint(item: selectionImageView, attribute: .Trailing, relatedBy: .Equal, toItem: self,
                                                    attribute: .Trailing, multiplier: 1, constant: 0)
        addConstraint(selectionImageT)
        
        let selectionImageY = NSLayoutConstraint(item: selectionImageView, attribute: .CenterY, relatedBy: .Equal, toItem: self,
                                                    attribute: .CenterY, multiplier: 1, constant: 0)
        addConstraint(selectionImageY)
    }
    
    private func setupDefaultSelectionIndicator() {
        defaultSelectionIndicator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(defaultSelectionIndicator)
        
        let selectionIndicatorH = NSLayoutConstraint(item: defaultSelectionIndicator, attribute: .Height, relatedBy: .Equal, toItem: nil,
                                                        attribute: .NotAnAttribute, multiplier: 1, constant: 5.0)
        addConstraint(selectionIndicatorH)
        
        let selectionIndicatorW = NSLayoutConstraint(item: defaultSelectionIndicator, attribute: .Width, relatedBy: .Equal,
                                                        toItem: self.selectionOverlay, attribute: .Width, multiplier: 1, constant: 0)
        addConstraint(selectionIndicatorW)
        
        let selectionIndicatorL = NSLayoutConstraint(item: defaultSelectionIndicator, attribute: .Leading, relatedBy: .Equal,
                                                        toItem: self.selectionOverlay, attribute: .Leading, multiplier: 1, constant: 0)
        addConstraint(selectionIndicatorL)
        
        let selectionIndicatorB = NSLayoutConstraint(item: defaultSelectionIndicator, attribute: .Bottom, relatedBy: .Equal,
                                                        toItem: self.selectionOverlay, attribute: .Bottom, multiplier: 1, constant: 0)
        addConstraint(selectionIndicatorB)
        
        let selectionIndicatorT = NSLayoutConstraint(item: defaultSelectionIndicator, attribute: .Trailing, relatedBy: .Equal,
                                                        toItem: self.selectionOverlay, attribute: .Trailing, multiplier: 1, constant: 0)
        addConstraint(selectionIndicatorT)
    }
    
    // MARK: Infinite Scrolling Helpers
    
    private func generateInfinityRowsMultiplier() -> Int {
        if scrollingStyle == .Default {
            return 1
        }
    
        if numberOfRowsByDataSource > 100 {
            return 100
        } else if numberOfRowsByDataSource < 100 && numberOfRowsByDataSource > 50 {
            return 200
        } else if numberOfRowsByDataSource < 50 && numberOfRowsByDataSource > 25 {
            return 400
        } else {
            return 800
        }
    }
    
    // MARK: Life Cycle
    
    override public func didMoveToSuperview() {
        super.didMoveToSuperview()
        
        NSNotificationCenter.defaultCenter().addObserver(self, selector: "adjustCurrentSelectedAfterOrientationChanges",
                                                            name: UIDeviceOrientationDidChangeNotification, object: nil)
    }
    
    override public func layoutSubviews() {
        super.layoutSubviews()
        
        if !setupHasBeenDone {
            setup()
            setupHasBeenDone = true
        }
    }
    
    private func adjustSelectionOverlayHeightConstraint() {
        if selectionOverlayH.constant != rowHeight || selectionImageH.constant != rowHeight {
            selectionOverlayH.constant = rowHeight
            selectionImageH.constant = rowHeight
            layoutIfNeeded()
        }
    }
    
    func adjustCurrentSelectedAfterOrientationChanges() {
        setNeedsLayout()
        layoutIfNeeded()
        selectedNearbyToMiddleRow(currentSelectedRow)
        
        if firstTimeOrientationChanged {
            firstTimeOrientationChanged = false
            return
        }
        
        if !isScrolling {
            return
        }
        
        orientationChanged = true
    }
    
    // MARK: - Actions
    
    private func selectedNearbyToMiddleRow(row: Int) {
        currentSelectedRow = row
        tableView.reloadData()
        
        repeat {
            let middleMultiplier = scrollingStyle == .Infinite ? (infinityRowsMultiplier / 2) : infinityRowsMultiplier
            let middleIndex = numberOfRowsByDataSource * middleMultiplier
            
            let nearbyToMiddleIndexForRow: Int!
            
            if scrollingStyle == .Default && row == 0 {
                nearbyToMiddleIndexForRow = 0
            } else {
                nearbyToMiddleIndexForRow = middleIndex - (numberOfRowsByDataSource - row)
            }
            
            tableView.contentInset = UIEdgeInsetsZero

            switch (numberOfRowsByDataSource, tableView.numberOfRowsInSection(0), nearbyToMiddleIndexForRow, scrollingStyle) {
            case (_, _, _, .Infinite) where numberOfRowsByDataSource > 0 && tableView.numberOfRowsInSection(0) > 0 && nearbyToMiddleIndexForRow > 0:
                tableView.setContentOffset(CGPoint(x: 0.0, y: CGFloat(nearbyToMiddleIndexForRow) * rowHeight), animated: false)
                delegate?.pickerView(self, didSelectRow: row)
            case (_, _, _, .Default) where numberOfRowsByDataSource > 0 && tableView.numberOfRowsInSection(0) > 0 && nearbyToMiddleIndexForRow >= 0:
                tableView.setContentOffset(CGPoint(x: 0.0, y: CGFloat(nearbyToMiddleIndexForRow) * rowHeight), animated: false)
                delegate?.pickerView(self, didSelectRow: row)
            default:
                break
            }
        } while !(numberOfRowsByDataSource > 0 && tableView.numberOfRowsInSection(0) > 0)
    }
    
    private func selectTappedRow(row: Int) {
        tableView.setContentOffset(CGPoint(x: 0.0, y: CGFloat(row) * rowHeight), animated: true)
        delegate?.pickerView(self, didSelectRow: row % numberOfRowsByDataSource)
    }
    
    private func configureFirstSelection() {
        let rowToSelect = currentSelectedRow != 0 ? currentSelectedRow : Int(ceil(Float(numberOfRowsByDataSource) / 2.0))
        selectedNearbyToMiddleRow(rowToSelect)
    }
    
    private func turnPickerViewOn() {
        tableView.scrollEnabled = true
    }
    
    private func turnPickerViewOff() {
        tableView.scrollEnabled = false
    }
    
}

extension PickerView: UITableViewDataSource {
    
    // MARK: UITableViewDataSource
    
    public func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return numberOfRowsByDataSource * infinityRowsMultiplier
    }
    
    public func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        let pickerViewCell = tableView.dequeueReusableCellWithIdentifier(pickerViewCellIdentifier, forIndexPath: indexPath) as! SimplePickerTableViewCell
        
        if indexPath.row == 0 {
            let centerY = (self.frame.height / 2) - (rowHeight / 2)
            pickerViewCell.titleLabel.frame = CGRect(x: 0.0, y: centerY, width: frame.width, height: rowHeight)
        } else {
            pickerViewCell.titleLabel.frame = CGRect(x: 0.0, y: 0.0, width: frame.width, height: rowHeight)
        }
        
        pickerViewCell.selectionStyle = .None
        pickerViewCell.backgroundColor = pickerCellBackgroundColor ?? UIColor.whiteColor()
        pickerViewCell.contentView.addSubview(pickerViewCell.titleLabel)
        pickerViewCell.titleLabel.backgroundColor = UIColor.clearColor()
        pickerViewCell.titleLabel.text = dataSource?.pickerView(self, titleForRow: indexPath.row % numberOfRowsByDataSource)
        
        let currentSelectedCellMultiplier = scrollingStyle == .Infinite ? (infinityRowsMultiplier / 2) : infinityRowsMultiplier
        let middleIndex = numberOfRowsByDataSource * currentSelectedCellMultiplier
        
        let nearbyToMiddleIndexForRow: Int!

        if scrollingStyle == .Default && currentSelectedRow == 0 {
            nearbyToMiddleIndexForRow = 0
        } else {
            nearbyToMiddleIndexForRow = middleIndex - (numberOfRowsByDataSource - currentSelectedRow)
        }
        
        if indexPath.row == nearbyToMiddleIndexForRow {
            delegate?.styleForHighlightedLabel(pickerViewCell.titleLabel, inPickerView: self)
        } else {
            delegate?.styleForLabel(pickerViewCell.titleLabel, inPickerView: self)
        }
        
        return pickerViewCell
    }
    
}

extension PickerView: UITableViewDelegate {
    
    // MARK: UITableViewDelegate
    
    public func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
        selectTappedRow(indexPath.row)
    }
    
    public func tableView(tableView: UITableView, heightForRowAtIndexPath indexPath: NSIndexPath) -> CGFloat {
        let numberOfRowsInPickerView = dataSource!.numberOfRowsInPickerView(self) * infinityRowsMultiplier
        
        if indexPath.row == 0 {
            return selectionOverlay.frame.origin.y + rowHeight
        } else if numberOfRowsInPickerView > 0 && indexPath.row == numberOfRowsInPickerView - 1 {
            return selectionOverlay.frame.origin.y + rowHeight
        }
        
        return rowHeight
    }
    
}

extension PickerView: UIScrollViewDelegate {
    
    // MARK: UIScrollViewDelegate
    
    public func scrollViewWillBeginDragging(scrollView: UIScrollView) {
        isScrolling = true
    }
    
    public func scrollViewWillEndDragging(scrollView: UIScrollView, withVelocity velocity: CGPoint, targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        let partialRow = Float(targetContentOffset.memory.y / rowHeight)
        var roundedRow = Int(lroundf(partialRow))
        
        if roundedRow < 0 {
            roundedRow = 0
        } else {
            targetContentOffset.memory.y = CGFloat(roundedRow) * rowHeight
        }
        
        currentSelectedRow = roundedRow % numberOfRowsByDataSource

        delegate?.pickerView(self, didSelectRow: roundedRow % dataSource!.numberOfRowsInPickerView(self))
    }
    
    public func scrollViewDidEndDecelerating(scrollView: UIScrollView) {
        if orientationChanged {
            selectedNearbyToMiddleRow(currentSelectedRow)
            orientationChanged = false
        }
        
        isScrolling = false
    }
    
    public func scrollViewDidScroll(scrollView: UIScrollView) {
        let partialRow = Float(scrollView.contentOffset.y / rowHeight)
        let roundedRow = Int(lroundf(partialRow))
        
        if let visibleRows = tableView.indexPathsForVisibleRows {
            for indexPath in visibleRows {
                if let cellToUnhighlight = tableView.cellForRowAtIndexPath(indexPath) as? SimplePickerTableViewCell {
                    delegate?.styleForLabel(cellToUnhighlight.titleLabel, inPickerView: self)
                }
            }
        }
        
        if let cellToHighlight = tableView.cellForRowAtIndexPath(NSIndexPath(forRow: roundedRow, inSection: 0)) as? SimplePickerTableViewCell {
            delegate?.styleForHighlightedLabel(cellToHighlight.titleLabel, inPickerView: self)
        }
    }
    
}