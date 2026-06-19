//
//  BrowserChromePositionPickerCell.swift
//  Reynard
//
//  Created by Minh Ton on 18/6/26.
//

import UIKit

final class BrowserChromePositionPickerCell: UITableViewCell {
    var onPositionChanged: ((BrowserChromePosition) -> Void)?
    private(set) var selectedPosition: BrowserChromePosition = .bottom
    
    private let bottomPositionOption = BrowserChromePositionOptionControl(
        position: .bottom,
        symbolName: "reynard.platter.filled.bottom.iphone",
        title: "Bottom"
    )
    private let topPositionOption = BrowserChromePositionOptionControl(
        position: .top,
        symbolName: "reynard.platter.filled.top.iphone",
        title: "Top"
    )
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        configureCell()
        installOptions()
        connectActions()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func display(selectedPosition: BrowserChromePosition) {
        self.selectedPosition = selectedPosition
        bottomPositionOption.displaySelection(selected: selectedPosition == .bottom)
        topPositionOption.displaySelection(selected: selectedPosition == .top)
    }
    
    private func configureCell() {
        selectionStyle = .none
    }
    
    private func installOptions() {
        let stackView = UIStackView(arrangedSubviews: [bottomPositionOption, topPositionOption])
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.alignment = .fill
        stackView.distribution = .fillEqually
        contentView.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: contentView.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }
    
    private func connectActions() {
        bottomPositionOption.addTarget(self, action: #selector(selectBottomPosition), for: .touchUpInside)
        topPositionOption.addTarget(self, action: #selector(selectTopPosition), for: .touchUpInside)
    }
    
    @objc private func selectBottomPosition() {
        guard selectedPosition != .bottom else { return }
        display(selectedPosition: .bottom)
        onPositionChanged?(.bottom)
    }
    
    @objc private func selectTopPosition() {
        guard selectedPosition != .top else { return }
        display(selectedPosition: .top)
        onPositionChanged?(.top)
    }
}
