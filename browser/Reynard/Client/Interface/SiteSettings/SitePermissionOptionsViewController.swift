//
//  SitePermissionOptionsViewController.swift
//  Reynard
//
//  Created by Minh Ton on 17/6/26.
//

import UIKit

final class SitePermissionOptionsViewController: UITableViewController {
    private let cellReuseIdentifier = "Cell"
    private let optionTitles: [String]
    private var selectedIndex: Int
    private let onSelect: (Int) -> Void
    
    init(title: String, options: [String], selectedIndex: Int, onSelect: @escaping (Int) -> Void) {
        self.optionTitles = options
        self.selectedIndex = selectedIndex
        self.onSelect = onSelect
        super.init(style: .insetGrouped)
        self.title = title
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        configureView()
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        1
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        optionTitles.count
    }
    
    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: cellReuseIdentifier)
        ?? UITableViewCell(style: .default, reuseIdentifier: cellReuseIdentifier)
        guard optionTitles.indices.contains(indexPath.row) else {
            return cell
        }
        
        cell.textLabel?.text = optionTitles[indexPath.row]
        cell.accessoryType = indexPath.row == selectedIndex ? .checkmark : .none
        cell.selectionStyle = .default
        return cell
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard optionTitles.indices.contains(indexPath.row) else {
            return
        }
        
        selectedIndex = indexPath.row
        onSelect(indexPath.row)
        tableView.reloadSections(IndexSet(integer: 0), with: .none)
        tableView.deselectRow(at: indexPath, animated: true)
    }
    
    @objc private func dismissModal() {
        dismiss(animated: true)
    }
    
    private func configureView() {
        view.backgroundColor = .systemGroupedBackground
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.rightBarButtonItems = [
            SiteSettingsUtils.makeDismissButton(target: self, action: #selector(dismissModal))
        ]
    }
}
