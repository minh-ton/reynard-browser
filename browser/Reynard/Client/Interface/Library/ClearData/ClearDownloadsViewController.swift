//
//  ClearDownloadsViewController.swift
//  Reynard
//
//  Created by Minh Ton on 22/5/26.
//

import UIKit

final class ClearDownloadsViewController: UITableViewController {
    private let onClear: (Date?) -> Void
    private var selectedTimeframe: ClearDataTimeframe = .lastHour
    
    private lazy var clearFooterView = ClearDataFooterView(
        title: "Clear Downloads",
        target: self,
        action: #selector(confirmClearDownloads)
    )
    
    init(onClear: @escaping (Date?) -> Void) {
        self.onClear = onClear
        super.init(style: .insetGrouped)
        title = "Clear Downloads"
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
        
        clearFooterView.alignClearButton(to: tableView.rectForRow(at: IndexPath(row: 0, section: 0)), tableViewWidth: tableView.bounds.width)
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        1
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        ClearDataTimeframe.allCases.count
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        "Clear Timeframe"
    }
    
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        "Clearing downloads history does not delete files in your Downloads folder."
    }
    
    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell")
        ?? UITableViewCell(style: .default, reuseIdentifier: "Cell")
        ClearDataTimeframe.configureCell(cell, at: indexPath, selectedTimeframe: selectedTimeframe)
        return cell
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        selectedTimeframe = ClearDataTimeframe.allCases[indexPath.row]
        tableView.reloadSections(IndexSet(integer: 0), with: .none)
        tableView.deselectRow(at: indexPath, animated: true)
    }
    
    @objc private func dismissSheet() {
        dismiss(animated: true)
    }
    
    @objc private func confirmClearDownloads() {
        onClear(selectedTimeframe.cutoffDate())
        dismiss(animated: true)
    }
}
