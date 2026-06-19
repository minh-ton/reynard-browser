//
//  NewBookmarkFolderViewController.swift
//  Reynard
//
//  Created by Minh Ton on 17/6/26.
//

import UIKit

final class NewBookmarkFolderViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate {
    private enum UX {
        static let sectionHeaderTopPadding: CGFloat = 0
    }
    
    private let store: BookmarkStore
    private let limitsToFavorites: Bool
    private var folderRows: [BookmarkFolderRow] = []
    private var selectedFolderID: String?
    
    private lazy var tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .systemGroupedBackground
        tableView.dataSource = self
        tableView.delegate = self
        tableView.separatorStyle = .singleLine
        if #available(iOS 15.0, *) {
            tableView.sectionHeaderTopPadding = UX.sectionHeaderTopPadding
        }
        return tableView
    }()
    
    private lazy var titleField: UITextField = {
        let textField = UITextField()
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.borderStyle = .none
        textField.clearButtonMode = .whileEditing
        textField.font = .preferredFont(forTextStyle: .body)
        textField.adjustsFontForContentSizeCategory = true
        textField.placeholder = "Title"
        textField.delegate = self
        textField.addTarget(self, action: #selector(validateSaveButton), for: .editingChanged)
        return textField
    }()
    
    // MARK: - Lifecycle
    
    init(selectedFolderID: String? = nil, limitsToFavorites: Bool = false, store: BookmarkStore = .shared) {
        self.selectedFolderID = selectedFolderID
        self.store = store
        self.limitsToFavorites = limitsToFavorites
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = "New Folder"
        view.backgroundColor = .systemGroupedBackground
        navigationItem.largeTitleDisplayMode = .never
        
        if #available(iOS 26.0, *) {
            navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancel))
            navigationItem.leftBarButtonItem?.tintColor = .label
            navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(createFolder))
            navigationItem.rightBarButtonItem?.tintColor = .label
        } else {
            navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Save", style: .done, target: self, action: #selector(createFolder))
        }
        
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        
        let root = limitsToFavorites ? store.favoritesFolderHierarchy() : store.childFolders()
        folderRows = makeBookmarkFolderRows(root: root, store: store)
        if selectedFolderID == nil {
            selectedFolderID = root.parent.guid
        }
        
        validateSaveButton()
    }
    
    // MARK: - Delegates
    
    func numberOfSections(in tableView: UITableView) -> Int {
        2
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 1 ? folderRows.count : 1
    }
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 1 ? "Location" : nil
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == 0 {
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.selectionStyle = .none
            cell.backgroundColor = .secondarySystemGroupedBackground
            cell.contentView.addSubview(titleField)
            
            NSLayoutConstraint.activate([
                titleField.leadingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.leadingAnchor),
                titleField.trailingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.trailingAnchor),
                titleField.centerYAnchor.constraint(equalTo: cell.contentView.centerYAnchor),
            ])
            
            return cell
        }
        
        let row = folderRows[indexPath.row]
        let cell = BookmarkFolderRowCell(style: .default, reuseIdentifier: nil)
        let isSelected = row.folder.guid == selectedFolderID
        cell.accessoryType = isSelected ? .checkmark : .none
        cell.configure(folder: row.folder, depth: row.depth, isSelected: isSelected)
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        if indexPath.section == 1 {
            selectedFolderID = folderRows[indexPath.row].folder.guid
            tableView.reloadSections(IndexSet(integer: 1), with: .none)
        }
    }
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
    
    // MARK: - Actions
    
    @objc private func createFolder() {
        guard let title = titleField.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty else {
            return
        }
        
        _ = store.addFolder(title: title, to: selectedFolderID)
        dismiss(animated: true)
    }
    
    @objc private func cancel() {
        dismiss(animated: true)
    }
    
    @objc private func validateSaveButton() {
        let title = titleField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        navigationItem.rightBarButtonItem?.isEnabled = !title.isEmpty
    }
}
