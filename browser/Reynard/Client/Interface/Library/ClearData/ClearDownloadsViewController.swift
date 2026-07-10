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
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 2
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return section == 0 ? ClearDataTimeframe.allCases.count : 1
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return section == 0 ? "Clear Timeframe" : nil
    }
    
    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        if indexPath.section == 0 {
            let cell = tableView.dequeueReusableCell(withIdentifier: "Cell")
            ?? UITableViewCell(style: .default, reuseIdentifier: "Cell")
            ClearDataTimeframe.configureCell(
                cell,
                at: indexPath,
                selectedTimeframe: selectedTimeframe,
                allTimeTitle: "All Downloads"
            )
            return cell
        }
        
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.textLabel?.text = "Clear Downloads"
        cell.textLabel?.textColor = .systemRed
        cell.textLabel?.textAlignment = .center
        cell.accessoryType = .none
        return cell
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        defer {
            tableView.deselectRow(at: indexPath, animated: true)
        }
        
        guard indexPath.section == 0 else {
            confirmClearDownloads()
            return
        }
        
        selectedTimeframe = ClearDataTimeframe.allCases[indexPath.row]
        tableView.reloadSections(IndexSet(integer: indexPath.section), with: .none)
    }
    
    @objc private func dismissSheet() {
        dismiss(animated: true)
    }
    
    @objc private func confirmClearDownloads() {
        onClear(selectedTimeframe.cutoffDate())
        dismiss(animated: true)
    }
}
