//
//  MultiSelectViewController.swift
//  Reynard
//
//  Created by Minh Ton on 17/6/26.
//

import GeckoView
import UIKit

final class MultiSelectViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private let cellReuseIdentifier = "cell"
    private var choices: [PromptChoice]
    private var selectedIds: Set<String>
    private var sections: [(title: String?, items: [PromptChoice])] = []
    private var tableView: UITableView!
    private var onDone: (([String]?) -> Void)?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        configureNavigation()
        configureTableView()
    }
    
    init(choices: [PromptChoice], onDone: @escaping ([String]?) -> Void) {
        self.choices = choices
        self.onDone = onDone
        self.selectedIds = Self.collectSelectedIds(from: choices)
        super.init(nibName: nil, bundle: nil)
        rebuildSections()
    }
    
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
    
    // MARK: - Updates
    
    func updateChoices(_ updatedChoices: [PromptChoice]) {
        choices = updatedChoices
        rebuildSections()
        tableView?.reloadData()
    }
    
    // MARK: - Setup
    
    private func configureNavigation() {
        title = "Select Options"
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(doneTapped)
        )
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancelTapped)
        )
    }
    
    private func configureTableView() {
        tableView = UITableView(frame: view.bounds, style: .insetGrouped)
        tableView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: cellReuseIdentifier)
        view.addSubview(tableView)
    }
    
    // MARK: - Sections
    
    private func rebuildSections() {
        sections = []
        var currentItems: [PromptChoice] = []
        
        for item in choices {
            if item.separator {
                appendSection(items: &currentItems)
                continue
            }
            
            if let subItems = item.items {
                appendSection(items: &currentItems)
                sections.append((title: item.label, items: subItems.filter { !$0.separator }))
            } else {
                currentItems.append(item)
            }
        }
        
        appendSection(items: &currentItems)
    }
    
    private func appendSection(items: inout [PromptChoice]) {
        guard !items.isEmpty else {
            return
        }
        sections.append((title: nil, items: items))
        items = []
    }
    
    private static func collectSelectedIds(from choices: [PromptChoice]) -> Set<String> {
        var ids = Set<String>()
        for choice in choices {
            if choice.selected {
                ids.insert(choice.id)
            }
            if let items = choice.items {
                ids.formUnion(collectSelectedIds(from: items))
            }
        }
        return ids
    }
    
    // MARK: - Actions
    
    @objc private func doneTapped() {
        let result = Array(selectedIds)
        dismiss(animated: true) { [weak self] in
            self?.onDone?(result)
            self?.onDone = nil
        }
    }
    
    @objc private func cancelTapped() {
        dismiss(animated: true) { [weak self] in
            self?.onDone?(nil)
            self?.onDone = nil
        }
    }
    
    // MARK: - UITableViewDataSource
    
    func numberOfSections(in tableView: UITableView) -> Int {
        sections.count
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections[section].items.count
    }
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        sections[section].title
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: cellReuseIdentifier, for: indexPath)
        let item = sections[indexPath.section].items[indexPath.row]
        cell.textLabel?.text = item.label
        cell.accessoryType = selectedIds.contains(item.id) ? .checkmark : .none
        cell.textLabel?.isEnabled = !item.disabled
        cell.selectionStyle = item.disabled ? .none : .default
        return cell
    }
    
    // MARK: - UITableViewDelegate
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let item = sections[indexPath.section].items[indexPath.row]
        guard !item.disabled else { return }
        
        if selectedIds.contains(item.id) {
            selectedIds.remove(item.id)
        } else {
            selectedIds.insert(item.id)
        }
        tableView.reloadRows(at: [indexPath], with: .automatic)
    }
}
