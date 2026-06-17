//
//  ClearHistory.swift
//  Reynard
//
//  Created by Minh Ton on 22/5/26.
//

import UIKit

final class ClearHistoryViewController: UITableViewController {
    private let tabCount: Int
    private let onClear: (Date?, Bool) -> Void
    private let closeAllTabsSwitch = UISwitch()
    private var clearButtonLeadingConstraint: NSLayoutConstraint?
    private var clearButtonTrailingConstraint: NSLayoutConstraint?
    private lazy var clearButton: UIButton = {
        let button = UIButton(type: .system)
        button.backgroundColor = .systemRed
        button.tintColor = .white
        button.layer.cornerRadius = 25
        button.layer.cornerCurve = .continuous
        button.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        button.setTitle("Clear History", for: .normal)
        button.addTarget(self, action: #selector(clearHistory), for: .touchUpInside)
        return button
    }()
    private var selectedTimeframeIndex = 0
    
    init(tabCount: Int, onClear: @escaping (Date?, Bool) -> Void) {
        self.tabCount = tabCount
        self.onClear = onClear
        super.init(style: .insetGrouped)
        title = "Clear History"
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = .systemGroupedBackground
        navigationItem.largeTitleDisplayMode = .never
        
        if #available(iOS 26.0, *), MakeButtons.hasLiquidGlass {
            navigationItem.rightBarButtonItems = [UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(dismissModal))]
            navigationItem.rightBarButtonItems?.first?.tintColor = .label
        } else {
            navigationItem.rightBarButtonItems = [UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(dismissModal))]
        }
        
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 0, height: 88))
        container.addSubview(clearButton)
        clearButton.translatesAutoresizingMaskIntoConstraints = false
        clearButtonLeadingConstraint = clearButton.leadingAnchor.constraint(equalTo: container.leadingAnchor)
        clearButtonTrailingConstraint = clearButton.trailingAnchor.constraint(equalTo: container.trailingAnchor)
        NSLayoutConstraint.activate([
            clearButton.topAnchor.constraint(equalTo: container.topAnchor, constant: 24),
            clearButtonLeadingConstraint!,
            clearButtonTrailingConstraint!,
            clearButton.heightAnchor.constraint(equalToConstant: 50),
        ])
        
        tableView.tableFooterView = container
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        let rowRect = tableView.rectForRow(at: IndexPath(row: 0, section: 1))
        guard rowRect.width > 0 else {
            return
        }
        
        clearButtonLeadingConstraint?.constant = rowRect.minX
        clearButtonTrailingConstraint?.constant = -(tableView.bounds.width - rowRect.maxX)
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        2
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? 4 : 1
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 0 ? "Clear Timeframe" : "Additional Options"
    }
    
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard section == 1 else {
            return nil
        }
        
        return "This will close your \(tabCount) \(tabCount == 1 ? "tab" : "tabs")."
    }
    
    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell") ?? UITableViewCell(style: .default, reuseIdentifier: "Cell")
        
        if indexPath.section == 0 {
            cell.textLabel?.text = ["Last hour", "Today", "Today and yesterday", "All history"][indexPath.row]
            cell.accessoryView = nil
            cell.accessoryType = indexPath.row == selectedTimeframeIndex ? .checkmark : .none
            cell.selectionStyle = .default
        } else {
            cell.textLabel?.text = "Close All Tabs"
            cell.accessoryView = closeAllTabsSwitch
            cell.accessoryType = .none
            cell.selectionStyle = .none
        }
        
        return cell
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard indexPath.section == 0 else {
            return
        }
        
        selectedTimeframeIndex = indexPath.row
        tableView.reloadSections(IndexSet(integer: 0), with: .none)
        tableView.deselectRow(at: indexPath, animated: true)
    }
    
    @objc private func dismissModal() {
        dismiss(animated: true)
    }
    
    @objc private func clearHistory() {
        let now = Date()
        let calendar = Calendar.current
        let startDate: Date?
        
        switch selectedTimeframeIndex {
        case 0:
            startDate = now.addingTimeInterval(-3_600)
        case 1:
            startDate = calendar.startOfDay(for: now)
        case 2:
            startDate = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now))
        default:
            startDate = nil
        }
        
        onClear(startDate, closeAllTabsSwitch.isOn)
        dismiss(animated: true)
    }
}
