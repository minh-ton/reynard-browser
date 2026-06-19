//
//  ClearHistoryViewController.swift
//  Reynard
//
//  Created by Minh Ton on 22/5/26.
//

import UIKit

final class ClearHistoryViewController: UITableViewController {
    private let tabCount: Int
    private let onClear: (Date?, Bool) -> Void
    private var selectedTimeframe: ClearDataTimeframe = .lastHour
    
    private let closeAllTabsSwitch = UISwitch()
    
    private lazy var clearFooterView = ClearDataFooterView(
        title: "Clear History",
        target: self,
        action: #selector(confirmClearHistory)
    )
    
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
        navigationItem.rightBarButtonItem = LibraryActionButton.makeSheetCloseButton(target: self, action: #selector(dismissSheet))
        tableView.tableFooterView = clearFooterView
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        clearFooterView.alignClearButton(to: tableView.rectForRow(at: IndexPath(row: 0, section: 1)), tableViewWidth: tableView.bounds.width)
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        2
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? ClearDataTimeframe.allCases.count : 1
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
            ClearDataTimeframe.configureCell(cell, at: indexPath, selectedTimeframe: selectedTimeframe)
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
        
        selectedTimeframe = ClearDataTimeframe.allCases[indexPath.row]
        tableView.reloadSections(IndexSet(integer: 0), with: .none)
        tableView.deselectRow(at: indexPath, animated: true)
    }
    
    @objc private func dismissSheet() {
        dismiss(animated: true)
    }
    
    @objc private func confirmClearHistory() {
        onClear(selectedTimeframe.cutoffDate(), closeAllTabsSwitch.isOn)
        dismiss(animated: true)
    }
}
