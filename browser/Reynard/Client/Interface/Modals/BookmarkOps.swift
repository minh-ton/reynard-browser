//
//  BookmarkOps.swift
//  Reynard
//
//  Created by Minh Ton on 21/5/26.
//

import UIKit

private typealias BookmarkOperationFolderRow = (folder: BookmarkFolderSnapshot, depth: Int)

private func makeBookmarkOperationFolderRows(root: BookmarkFolderHierarchySnapshot, store: BookmarkStore) -> [BookmarkOperationFolderRow] {
    var rows: [BookmarkOperationFolderRow] = []
    
    func appendFolders(parentGUID: String, depth: Int) {
        for folder in store.folderHierarchy(parentGUID: parentGUID).items {
            rows.append((folder, depth))
            appendFolders(parentGUID: folder.guid, depth: depth + 1)
        }
    }
    
    for folder in root.items where folder.isProtected {
        rows.append((folder, 0))
        appendFolders(parentGUID: folder.guid, depth: 1)
    }
    rows.append((root.parent, 0))
    for folder in root.items where !folder.isProtected {
        rows.append((folder, 1))
        appendFolders(parentGUID: folder.guid, depth: 2)
    }
    
    return rows
}

final class EditBookmarkViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate {
    private let bookmarkStore: BookmarkStore
    private let bookmark: BookmarkSnapshot?
    private let initialBookmarkTitle: String
    private let initialBookmarkURL: URL?
    private let showsFavoritesHierarchyOnly: Bool
    private var bookmarkFolderRows: [BookmarkOperationFolderRow] = []
    private var selectedBookmarkFolderGUID: String?
    private var faviconTask: Task<Void, Never>?
    private var bookmarkStoreObserver: NSObjectProtocol?
    
    private lazy var tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .systemGroupedBackground
        tableView.dataSource = self
        tableView.delegate = self
        tableView.separatorStyle = .singleLine
        if #available(iOS 15.0, *) {
            tableView.sectionHeaderTopPadding = 0
        }
        return tableView
    }()
    
    private let bookmarkFaviconTopView: UIImageView = {
        let imageView = UIImageView(image: UIImage(systemName: "globe"))
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = .secondaryLabel
        imageView.backgroundColor = .secondarySystemGroupedBackground
        imageView.layer.cornerRadius = 12
        imageView.layer.cornerCurve = .continuous
        imageView.clipsToBounds = true
        return imageView
    }()
    private let bookmarkFaviconBottomView: UIImageView = {
        let imageView = UIImageView(image: UIImage(systemName: "globe"))
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = .secondaryLabel
        imageView.backgroundColor = .secondarySystemGroupedBackground
        imageView.layer.cornerRadius = 12
        imageView.layer.cornerCurve = .continuous
        imageView.clipsToBounds = true
        return imageView
    }()
    
    private lazy var bookmarkTitleField: UITextField = {
        let textField = UITextField()
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.borderStyle = .none
        textField.clearButtonMode = .whileEditing
        textField.font = .preferredFont(forTextStyle: .body)
        textField.adjustsFontForContentSizeCategory = true
        textField.placeholder = "Title"
        textField.text = bookmark?.title ?? initialBookmarkTitle
        textField.delegate = self
        textField.addTarget(self, action: #selector(updateDoneButtonState), for: .editingChanged)
        return textField
    }()
    
    private lazy var bookmarkURLField: UITextField = {
        let textField = UITextField()
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.borderStyle = .none
        textField.clearButtonMode = .whileEditing
        textField.font = .preferredFont(forTextStyle: .body)
        textField.adjustsFontForContentSizeCategory = true
        textField.autocapitalizationType = .none
        textField.autocorrectionType = .no
        textField.keyboardType = .URL
        textField.placeholder = "URL"
        textField.text = bookmark?.url.absoluteString ?? initialBookmarkURL?.absoluteString
        textField.delegate = self
        textField.addTarget(self, action: #selector(updateDoneButtonState), for: .editingChanged)
        return textField
    }()
    
    init(
        bookmark: BookmarkSnapshot? = nil,
        title: String = "",
        url: URL? = nil,
        selectedFolderGUID: String? = nil,
        showsFavoritesHierarchyOnly: Bool = false,
        store: BookmarkStore = .shared
    ) {
        self.bookmark = bookmark
        self.bookmarkStore = store
        self.initialBookmarkTitle = title
        self.initialBookmarkURL = url
        self.showsFavoritesHierarchyOnly = showsFavoritesHierarchyOnly
        self.selectedBookmarkFolderGUID = selectedFolderGUID ?? bookmark?.parentGUID
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        faviconTask?.cancel()
        if let bookmarkStoreObserver {
            NotificationCenter.default.removeObserver(bookmarkStoreObserver)
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = showsFavoritesHierarchyOnly ? "Add to Favorites" : (bookmark == nil ? "Add Bookmark" : "Edit Bookmark")
        view.backgroundColor = .systemGroupedBackground
        navigationItem.largeTitleDisplayMode = .never
        
        if #available(iOS 26.0, *), MakeButtons.hasLiquidGlass {
            navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(saveBookmark))
            navigationItem.rightBarButtonItem?.tintColor = .label
            if bookmark != nil {
                navigationItem.leftBarButtonItems = [UIBarButtonItem(barButtonSystemItem: .trash, target: self, action: #selector(deleteBookmark))]
                navigationItem.leftBarButtonItems?.first?.tintColor = .systemRed
            } else {
                navigationItem.leftBarButtonItems = [UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancel))]
                navigationItem.leftBarButtonItems?.first?.tintColor = .label
            }
        } else {
            navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Save", style: .done, target: self, action: #selector(saveBookmark))
        }
        
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        
        reloadFolderHierarchy()
        
        bookmarkStoreObserver = NotificationCenter.default.addObserver(
            forName: .bookmarkStoreDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reloadFolderHierarchy()
            self?.tableView.reloadSections(IndexSet(integer: 2), with: .none)
        }
        
        if let url = bookmark?.url ?? URL(string: bookmarkURLField.text ?? "") {
            if let image = FaviconStore.shared.cachedImage(for: url) {
                bookmarkFaviconTopView.image = image
                bookmarkFaviconTopView.tintColor = nil
                bookmarkFaviconBottomView.image = image
                bookmarkFaviconBottomView.tintColor = nil
            } else {
                faviconTask = Task { [weak self] in
                    let image = await FaviconStore.shared.resolveFavicon(for: url)
                    await MainActor.run {
                        guard let self, let image else {
                            return
                        }
                        self.bookmarkFaviconTopView.image = image
                        self.bookmarkFaviconTopView.tintColor = nil
                        self.bookmarkFaviconBottomView.image = image
                        self.bookmarkFaviconBottomView.tintColor = nil
                    }
                }
            }
        }
        
        updateDoneButtonState()
    }
    
    func numberOfSections(in tableView: UITableView) -> Int {
        3
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0:
            return 2
        case 2:
            return bookmarkFolderRows.count
        default:
            return 1
        }
    }
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 2 ? "Location" : nil
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == 0 {
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.selectionStyle = .none
            cell.backgroundColor = .secondarySystemGroupedBackground
            cell.clipsToBounds = true
            cell.contentView.clipsToBounds = true
            
            if indexPath.row == 0 {
                cell.contentView.addSubview(bookmarkFaviconTopView)
                cell.contentView.addSubview(bookmarkTitleField)
                cell.separatorInset.left = cell.layoutMargins.left + 75
                
                NSLayoutConstraint.activate([
                    bookmarkFaviconTopView.leadingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.leadingAnchor),
                    bookmarkFaviconTopView.centerYAnchor.constraint(equalTo: cell.contentView.bottomAnchor),
                    bookmarkFaviconTopView.widthAnchor.constraint(equalToConstant: 56),
                    bookmarkFaviconTopView.heightAnchor.constraint(equalToConstant: 56),
                    
                    bookmarkTitleField.leadingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.leadingAnchor, constant: 68),
                    bookmarkTitleField.trailingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.trailingAnchor),
                    bookmarkTitleField.centerYAnchor.constraint(equalTo: cell.contentView.centerYAnchor),
                ])
            } else {
                cell.contentView.addSubview(bookmarkFaviconBottomView)
                cell.contentView.addSubview(bookmarkURLField)
                
                NSLayoutConstraint.activate([
                    bookmarkFaviconBottomView.leadingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.leadingAnchor),
                    bookmarkFaviconBottomView.centerYAnchor.constraint(equalTo: cell.contentView.topAnchor),
                    bookmarkFaviconBottomView.widthAnchor.constraint(equalToConstant: 56),
                    bookmarkFaviconBottomView.heightAnchor.constraint(equalToConstant: 56),
                    
                    bookmarkURLField.leadingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.leadingAnchor, constant: 68),
                    bookmarkURLField.trailingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.trailingAnchor),
                    bookmarkURLField.centerYAnchor.constraint(equalTo: cell.contentView.centerYAnchor),
                ])
            }
            
            return cell
        }
        
        if indexPath.section == 1 {
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.backgroundColor = .secondarySystemGroupedBackground
            cell.tintColor = .systemBlue
            cell.textLabel?.text = "New Folder"
            cell.textLabel?.textColor = .systemBlue
            cell.imageView?.image = UIImage(systemName: "folder.badge.plus")?.withRenderingMode(.alwaysTemplate)
            return cell
        }
        
        let row = bookmarkFolderRows[indexPath.row]
        let cell = BookmarkOperationFolderCell(style: .default, reuseIdentifier: nil)
        let isSelected = row.folder.guid == selectedBookmarkFolderGUID
        cell.accessoryType = isSelected ? .checkmark : .none
        cell.apply(folder: row.folder, depth: row.depth, isSelected: isSelected)
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        if indexPath.section == 1 {
            let viewController = NewBookmarkFolderViewController(
                selectedParentFolderGUID: selectedBookmarkFolderGUID,
                showsFavoritesHierarchyOnly: showsFavoritesHierarchyOnly,
                store: bookmarkStore
            )
            let navigationController = UINavigationController(rootViewController: viewController)
            navigationController.modalPresentationStyle = .pageSheet
            present(navigationController, animated: true)
        } else if indexPath.section == 2 {
            selectedBookmarkFolderGUID = bookmarkFolderRows[indexPath.row].folder.guid
            tableView.reloadSections(IndexSet(integer: 2), with: .none)
        }
    }
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if textField === bookmarkTitleField {
            bookmarkURLField.becomeFirstResponder()
        } else {
            textField.resignFirstResponder()
        }
        return true
    }
    
    @objc private func saveBookmark() {
        guard let title = bookmarkTitleField.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              let urlString = bookmarkURLField.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: urlString),
              !title.isEmpty else {
            return
        }
        
        if let bookmark {
            _ = bookmarkStore.editBookmark(guid: bookmark.guid, title: title, url: url, inFolderWithGUID: selectedBookmarkFolderGUID)
        } else {
            _ = bookmarkStore.saveBookmark(title: title, url: url, inFolderWithGUID: selectedBookmarkFolderGUID)
        }
        
        dismiss(animated: true)
    }
    
    @objc private func deleteBookmark() {
        guard let bookmark else {
            return
        }
        
        _ = bookmarkStore.deleteBookmark(guid: bookmark.guid)
        dismiss(animated: true)
    }
    
    @objc private func cancel() {
        dismiss(animated: true)
    }
    
    @objc private func updateDoneButtonState() {
        let title = bookmarkTitleField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let urlString = bookmarkURLField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        navigationItem.rightBarButtonItem?.isEnabled = !title.isEmpty && URL(string: urlString) != nil
    }
    
    private func reloadFolderHierarchy() {
        let root = showsFavoritesHierarchyOnly ? bookmarkStore.favoritesFolderHierarchy() : bookmarkStore.folderHierarchy()
        bookmarkFolderRows = makeBookmarkOperationFolderRows(root: root, store: bookmarkStore)
        if selectedBookmarkFolderGUID == nil {
            selectedBookmarkFolderGUID = root.parent.guid
        }
    }
}

final class NewBookmarkFolderViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate {
    private let bookmarkStore: BookmarkStore
    private let showsFavoritesHierarchyOnly: Bool
    private var parentFolderRows: [BookmarkOperationFolderRow] = []
    private var selectedParentFolderGUID: String?
    
    private lazy var tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .systemGroupedBackground
        tableView.dataSource = self
        tableView.delegate = self
        tableView.separatorStyle = .singleLine
        if #available(iOS 15.0, *) {
            tableView.sectionHeaderTopPadding = 0
        }
        return tableView
    }()
    
    private lazy var folderTitleField: UITextField = {
        let textField = UITextField()
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.borderStyle = .none
        textField.clearButtonMode = .whileEditing
        textField.font = .preferredFont(forTextStyle: .body)
        textField.adjustsFontForContentSizeCategory = true
        textField.placeholder = "Title"
        textField.delegate = self
        textField.addTarget(self, action: #selector(updateDoneButtonState), for: .editingChanged)
        return textField
    }()
    
    init(selectedParentFolderGUID: String? = nil, showsFavoritesHierarchyOnly: Bool = false, store: BookmarkStore = .shared) {
        self.selectedParentFolderGUID = selectedParentFolderGUID
        self.bookmarkStore = store
        self.showsFavoritesHierarchyOnly = showsFavoritesHierarchyOnly
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
        
        if #available(iOS 26.0, *), MakeButtons.hasLiquidGlass {
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
        
        let root = showsFavoritesHierarchyOnly ? bookmarkStore.favoritesFolderHierarchy() : bookmarkStore.folderHierarchy()
        parentFolderRows = makeBookmarkOperationFolderRows(root: root, store: bookmarkStore)
        if selectedParentFolderGUID == nil {
            selectedParentFolderGUID = root.parent.guid
        }
        
        updateDoneButtonState()
    }
    
    func numberOfSections(in tableView: UITableView) -> Int {
        2
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 1 ? parentFolderRows.count : 1
    }
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 1 ? "Location" : nil
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == 0 {
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.selectionStyle = .none
            cell.backgroundColor = .secondarySystemGroupedBackground
            cell.contentView.addSubview(folderTitleField)
            
            NSLayoutConstraint.activate([
                folderTitleField.leadingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.leadingAnchor),
                folderTitleField.trailingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.trailingAnchor),
                folderTitleField.centerYAnchor.constraint(equalTo: cell.contentView.centerYAnchor),
            ])
            
            return cell
        }
        
        let row = parentFolderRows[indexPath.row]
        let cell = BookmarkOperationFolderCell(style: .default, reuseIdentifier: nil)
        let isSelected = row.folder.guid == selectedParentFolderGUID
        cell.accessoryType = isSelected ? .checkmark : .none
        cell.apply(folder: row.folder, depth: row.depth, isSelected: isSelected)
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        if indexPath.section == 1 {
            selectedParentFolderGUID = parentFolderRows[indexPath.row].folder.guid
            tableView.reloadSections(IndexSet(integer: 1), with: .none)
        }
    }
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
    
    @objc private func createFolder() {
        guard let title = folderTitleField.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty else {
            return
        }
        
        _ = bookmarkStore.createFolder(title: title, inFolderWithGUID: selectedParentFolderGUID)
        dismiss(animated: true)
    }
    
    @objc private func cancel() {
        dismiss(animated: true)
    }
    
    @objc private func updateDoneButtonState() {
        let title = folderTitleField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        navigationItem.rightBarButtonItem?.isEnabled = !title.isEmpty
    }
}

private final class BookmarkOperationFolderCell: UITableViewCell {
    private let hierarchyIndentWidth: CGFloat = 28
    private var currentDepth = 0
    private var iconLeadingConstraint: NSLayoutConstraint?
    
    private let folderIconView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = .systemBlue
        return imageView
    }()
    
    private let folderTitleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .preferredFont(forTextStyle: .body)
        label.textColor = .label
        label.adjustsFontForContentSizeCategory = true
        return label
    }()
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .secondarySystemGroupedBackground
        tintColor = .systemBlue
        
        contentView.addSubview(folderIconView)
        contentView.addSubview(folderTitleLabel)
        
        let iconLeadingConstraint = folderIconView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor)
        self.iconLeadingConstraint = iconLeadingConstraint
        
        NSLayoutConstraint.activate([
            iconLeadingConstraint,
            folderIconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            folderIconView.widthAnchor.constraint(equalToConstant: 24),
            folderIconView.heightAnchor.constraint(equalToConstant: 24),
            
            folderTitleLabel.leadingAnchor.constraint(equalTo: folderIconView.trailingAnchor, constant: 16),
            folderTitleLabel.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            folderTitleLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            folderTitleLabel.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor, constant: 10),
            folderTitleLabel.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -10),
        ])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        let titleLeading = contentView.layoutMargins.left + CGFloat(currentDepth) * hierarchyIndentWidth + 40
        separatorInset = UIEdgeInsets(
            top: separatorInset.top,
            left: titleLeading,
            bottom: separatorInset.bottom,
            right: contentView.layoutMargins.right
        )
    }
    
    func apply(folder: BookmarkFolderSnapshot, depth: Int, isSelected: Bool) {
        currentDepth = depth
        folderTitleLabel.text = folder.title
        iconLeadingConstraint?.constant = CGFloat(depth) * hierarchyIndentWidth
        folderIconView.tintColor = isSelected ? .systemBlue : .secondaryLabel
        
        if folder.parentGUID == nil {
            folderIconView.image = UIImage(systemName: "book")?.withRenderingMode(.alwaysTemplate)
        } else if folder.isProtected && folder.title == "Favorites" {
            folderIconView.image = UIImage(systemName: "star")?.withRenderingMode(.alwaysTemplate)
        } else {
            folderIconView.image = UIImage(systemName: "folder")?.withRenderingMode(.alwaysTemplate)
        }
    }
}
