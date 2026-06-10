//
//  Tabs.swift
//  Reynard
//
//  Created by Minh Ton on 11/4/26.
//

import UIKit

final class PositionOptionControl: UIControl {
    let position: AddressBarPosition
    private let imageView = UIImageView()
    private let titleLabel = UILabel()
    private let radioView = UIImageView()
    
    init(position: AddressBarPosition, symbolName: String, title: String) {
        self.position = position
        super.init(frame: .zero)
        isAccessibilityElement = true
        accessibilityLabel = title
        accessibilityTraits = [.button]
        
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = UIFont.systemFont(ofSize: 13, weight: .regular)
        titleLabel.textAlignment = .center
        titleLabel.text = title
        
        radioView.translatesAutoresizingMaskIntoConstraints = false
        radioView.contentMode = .scaleAspectFit
        
        let symbolConfig = UIImage.SymbolConfiguration(pointSize: 78, weight: .ultraLight)
        imageView.image = UIImage(named: symbolName)?.applyingSymbolConfiguration(symbolConfig)
        
        addSubview(imageView)
        addSubview(titleLabel)
        addSubview(radioView)
        
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.heightAnchor.constraint(equalToConstant: 102),
            
            titleLabel.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 0),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            
            radioView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
            radioView.centerXAnchor.constraint(equalTo: centerXAnchor),
            radioView.widthAnchor.constraint(equalToConstant: 26),
            radioView.heightAnchor.constraint(equalToConstant: 26),
            radioView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
        ])
        
        updateAppearance(selected: false)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func updateAppearance(selected: Bool) {
        let accent = tintColor ?? .systemBlue
        let secondary = UIColor.secondaryLabel
        imageView.tintColor = selected ? accent : secondary
        titleLabel.textColor = .label
        let radioConfig = UIImage.SymbolConfiguration(pointSize: 22, weight: .regular)
        radioView.image = UIImage(
            systemName: selected ? "checkmark.circle.fill" : "circle",
            withConfiguration: radioConfig
        )
        radioView.tintColor = selected ? accent : secondary
    }
}

final class AddressBarPositionPickerCell: UITableViewCell {
    var onSelectionChanged: ((AddressBarPosition) -> Void)?
    private(set) var selectedPosition: AddressBarPosition = .bottom
    
    private let bottomOption = PositionOptionControl(
        position: .bottom,
        symbolName: "platter.filled.bottom.iphone",
        title: "Bottom"
    )
    private let topOption = PositionOptionControl(
        position: .top,
        symbolName: "platter.filled.top.iphone",
        title: "Top"
    )
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        let stackView = UIStackView(arrangedSubviews: [bottomOption, topOption])
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
        bottomOption.addTarget(self, action: #selector(bottomOptionTapped), for: .touchUpInside)
        topOption.addTarget(self, action: #selector(topOptionTapped), for: .touchUpInside)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func configure(selectedPosition: AddressBarPosition) {
        self.selectedPosition = selectedPosition
        bottomOption.updateAppearance(selected: selectedPosition == .bottom)
        topOption.updateAppearance(selected: selectedPosition == .top)
    }
    
    @objc private func bottomOptionTapped() {
        guard selectedPosition != .bottom else { return }
        configure(selectedPosition: .bottom)
        onSelectionChanged?(.bottom)
    }
    
    @objc private func topOptionTapped() {
        guard selectedPosition != .top else { return }
        configure(selectedPosition: .top)
        onSelectionChanged?(.top)
    }
}

final class AppearancePreferencesViewController: SettingsTableViewController {
    private let landscapeTabBarSwitch = UISwitch()
    
    private var showsTabsSection: Bool {
        UIDevice.current.userInterfaceIdiom != .pad
    }
    
    init() {
        super.init(style: .insetGrouped)
        title = "Appearance"
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        landscapeTabBarSwitch.addTarget(self, action: #selector(landscapeTabBarSwitchChanged), for: .valueChanged)
        refreshControls()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshControls()
        tableView.reloadData()
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        showsTabsSection ? 1 : 0
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard showsTabsSection else {
            return 0
        }
        return 2
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        showsTabsSection ? "Tabs" : nil
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard showsTabsSection else {
            return UITableViewCell()
        }
        
        if indexPath.row == 0 {
            let cell = AddressBarPositionPickerCell(style: .default, reuseIdentifier: nil)
            cell.configure(selectedPosition: Prefs.AppearanceSettings.addressBarPosition)
            cell.onSelectionChanged = { [weak self] position in
                Prefs.AppearanceSettings.addressBarPosition = position
            }
            return cell
        }
        
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.textLabel?.text = "Landscape Tab Bar"
        cell.selectionStyle = .none
        cell.accessoryView = landscapeTabBarSwitch
        return cell
    }
    
    private func refreshControls() {
        landscapeTabBarSwitch.isOn = Prefs.AppearanceSettings.showsLandscapeTabBar
    }
    
    @objc private func landscapeTabBarSwitchChanged() {
        Prefs.AppearanceSettings.showsLandscapeTabBar = landscapeTabBarSwitch.isOn
    }
}
