//
//  AppAppearancePickerCell.swift
//  Reynard
//
//  Created by Minh Ton on 22/6/26.
//

import UIKit

final class AppAppearancePickerCell: UITableViewCell {
    var onAppearanceChanged: ((AppAppearance) -> Void)?
    private(set) var selectedAppearance: AppAppearance = .system
    
    private let systemAppearanceOption = AppAppearanceOptionControl(
        appearance: .system,
        symbolName: "reynard.circle.lefthalf.filled",
        title: NSLocalizedString("System", comment: "")
    )
    private let lightAppearanceOption = AppAppearanceOptionControl(
        appearance: .light,
        symbolName: "reynard.sun.max.fill",
        title: NSLocalizedString("Day", comment: "")
    )
    private let darkAppearanceOption = AppAppearanceOptionControl(
        appearance: .dark,
        symbolName: "reynard.moon.fill",
        title: NSLocalizedString("Night", comment: "")
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
    
    func display(selectedAppearance: AppAppearance) {
        self.selectedAppearance = selectedAppearance
        systemAppearanceOption.displaySelection(selected: selectedAppearance == .system)
        lightAppearanceOption.displaySelection(selected: selectedAppearance == .light)
        darkAppearanceOption.displaySelection(selected: selectedAppearance == .dark)
    }
    
    private func configureCell() {
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        selectionStyle = .none
    }
    
    private func installOptions() {
        let stackView = UIStackView(arrangedSubviews: [
            systemAppearanceOption,
            lightAppearanceOption,
            darkAppearanceOption,
        ])
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
        systemAppearanceOption.addTarget(self, action: #selector(selectSystemAppearance), for: .touchUpInside)
        lightAppearanceOption.addTarget(self, action: #selector(selectLightAppearance), for: .touchUpInside)
        darkAppearanceOption.addTarget(self, action: #selector(selectDarkAppearance), for: .touchUpInside)
    }
    
    @objc private func selectSystemAppearance() {
        systemAppearanceOption.animateTap()
        selectAppearance(.system)
    }
    
    @objc private func selectLightAppearance() {
        lightAppearanceOption.animateTap()
        selectAppearance(.light)
    }
    
    @objc private func selectDarkAppearance() {
        darkAppearanceOption.animateTap()
        selectAppearance(.dark)
    }
    
    private func selectAppearance(_ appearance: AppAppearance) {
        guard selectedAppearance != appearance else { return }
        display(selectedAppearance: appearance)
        onAppearanceChanged?(appearance)
    }
}
