//
//  EditBookmarkViewController.swift
//  Reynard
//
//  Created by Minh Ton on 17/6/26.
//

import UIKit

final class EditBookmarkViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate {
    private enum UX {
        static let sectionHeaderTopPadding: CGFloat = 0
        static let faviconCornerRadius: CGFloat = 12
        static let faviconSize: CGFloat = 56
        static let fieldLeadingSpacing: CGFloat = 68
        static let titleSeparatorLeftInset: CGFloat = 75
    }
    
    private let store: BookmarkStore
    private let bookmark: BookmarkSnapshot?
    private let draftTitle: String
    private let draftURL: URL?
    private let limitsToFavorites: Bool
    private var folderRows: [BookmarkFolderRow] = []
    private var selectedFolderID: String?
    private var faviconTask: Task<Void, Never>?
    private var storeObserver: NSObjectProtocol?
    
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
    
    private let titleFaviconView: UIImageView = {
        let imageView = UIImageView(image: UIImage(named: "reynard.globe"))
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = .secondaryLabel
        imageView.backgroundColor = .secondarySystemGroupedBackground
        imageView.layer.cornerRadius = UX.faviconCornerRadius
        imageView.layer.cornerCurve = .continuous
        imageView.clipsToBounds = true
        return imageView
    }()
    private let urlFaviconView: UIImageView = {
        let imageView = UIImageView(image: UIImage(named: "reynard.globe"))
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = .secondaryLabel
        imageView.backgroundColor = .secondarySystemGroupedBackground
        imageView.layer.cornerRadius = UX.faviconCornerRadius
        imageView.layer.cornerCurve = .continuous
        imageView.clipsToBounds = true
        return imageView
    }()
    
    private lazy var titleField: UITextField = {
        let textField = UITextField()
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.borderStyle = .none
        textField.clearButtonMode = .whileEditing
        textField.font = .preferredFont(forTextStyle: .body)
        textField.adjustsFontForContentSizeCategory = true
        textField.placeholder = "Title"
        textField.text = bookmark?.title ?? draftTitle
        textField.delegate = self
        textField.addTarget(self, action: #selector(validateSaveButton), for: .editingChanged)
        return textField
    }()
    
    private lazy var urlField: UITextField = {
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
        textField.text = bookmark?.url.absoluteString ?? draftURL?.absoluteString
        textField.delegate = self
        textField.addTarget(self, action: #selector(validateSaveButton), for: .editingChanged)
        return textField
    }()
    
    // MARK: - Lifecycle
    
    init(
        bookmark: BookmarkSnapshot? = nil,
        title: String = "",
        url: URL? = nil,
        selectedFolderID: String? = nil,
        limitsToFavorites: Bool = false,
        store: BookmarkStore = .shared
    ) {
        self.bookmark = bookmark
        self.store = store
        self.draftTitle = title
        self.draftURL = url
        self.limitsToFavorites = limitsToFavorites
        self.selectedFolderID = selectedFolderID ?? bookmark?.parentGUID
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        faviconTask?.cancel()
        if let storeObserver {
            NotificationCenter.default.removeObserver(storeObserver)
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = limitsToFavorites ? "Add to Favorites" : (bookmark == nil ? "Add Bookmark" : "Edit Bookmark")
        view.backgroundColor = .systemGroupedBackground
        navigationItem.largeTitleDisplayMode = .never
        
        if #available(iOS 26.0, *) {
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
        
        reloadFolderRows()
        
        storeObserver = NotificationCenter.default.addObserver(
            forName: .bookmarkStoreDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reloadFolderRows()
            self?.tableView.reloadSections(IndexSet(integer: 2), with: .none)
        }
        
        if let url = bookmark?.url ?? URL(string: urlField.text ?? "") {
            if let image = FaviconStore.shared.cachedFavicon(for: url) {
                titleFaviconView.image = image
                titleFaviconView.tintColor = nil
                urlFaviconView.image = image
                urlFaviconView.tintColor = nil
            } else {
                faviconTask = Task { [weak self] in
                    let image = await FaviconStore.shared.favicon(for: url)
                    await MainActor.run {
                        guard let self, let image else {
                            return
                        }
                        self.titleFaviconView.image = image
                        self.titleFaviconView.tintColor = nil
                        self.urlFaviconView.image = image
                        self.urlFaviconView.tintColor = nil
                    }
                }
            }
        }
        
        validateSaveButton()
    }
    
    // MARK: - UITableViewDataSource
    
    func numberOfSections(in tableView: UITableView) -> Int {
        3
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0:
            return 2
        case 2:
            return folderRows.count
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
                cell.contentView.addSubview(titleFaviconView)
                cell.contentView.addSubview(titleField)
                cell.separatorInset.left = cell.layoutMargins.left + UX.titleSeparatorLeftInset
                
                NSLayoutConstraint.activate([
                    titleFaviconView.leadingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.leadingAnchor),
                    titleFaviconView.centerYAnchor.constraint(equalTo: cell.contentView.bottomAnchor),
                    titleFaviconView.widthAnchor.constraint(equalToConstant: UX.faviconSize),
                    titleFaviconView.heightAnchor.constraint(equalToConstant: UX.faviconSize),
                    
                    titleField.leadingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.leadingAnchor, constant: UX.fieldLeadingSpacing),
                    titleField.trailingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.trailingAnchor),
                    titleField.centerYAnchor.constraint(equalTo: cell.contentView.centerYAnchor),
                ])
            } else {
                cell.contentView.addSubview(urlFaviconView)
                cell.contentView.addSubview(urlField)
                
                NSLayoutConstraint.activate([
                    urlFaviconView.leadingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.leadingAnchor),
                    urlFaviconView.centerYAnchor.constraint(equalTo: cell.contentView.topAnchor),
                    urlFaviconView.widthAnchor.constraint(equalToConstant: UX.faviconSize),
                    urlFaviconView.heightAnchor.constraint(equalToConstant: UX.faviconSize),
                    
                    urlField.leadingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.leadingAnchor, constant: UX.fieldLeadingSpacing),
                    urlField.trailingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.trailingAnchor),
                    urlField.centerYAnchor.constraint(equalTo: cell.contentView.centerYAnchor),
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
            cell.imageView?.image = UIImage(named: "reynard.folder.badge.plus")?.withRenderingMode(.alwaysTemplate)
            return cell
        }
        
        let row = folderRows[indexPath.row]
        let cell = BookmarkFolderRowCell(style: .default, reuseIdentifier: nil)
        let isSelected = row.folder.guid == selectedFolderID
        cell.accessoryType = isSelected ? .checkmark : .none
        cell.configure(folder: row.folder, depth: row.depth, isSelected: isSelected)
        return cell
    }
    
    // MARK: - UITableViewDelegate
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        if indexPath.section == 1 {
            let viewController = NewBookmarkFolderViewController(
                selectedFolderID: selectedFolderID,
                limitsToFavorites: limitsToFavorites,
                store: store
            )
            let navigationController = UINavigationController(rootViewController: viewController)
            navigationController.modalPresentationStyle = .pageSheet
            present(navigationController, animated: true)
        } else if indexPath.section == 2 {
            selectedFolderID = folderRows[indexPath.row].folder.guid
            tableView.reloadSections(IndexSet(integer: 2), with: .none)
        }
    }
    
    // MARK: - UITextFieldDelegate
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if textField === titleField {
            urlField.becomeFirstResponder()
        } else {
            textField.resignFirstResponder()
        }
        return true
    }
    
    // MARK: - Actions
    
    @objc private func saveBookmark() {
        guard let title = titleField.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              let urlString = urlField.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: urlString),
              !title.isEmpty else {
            return
        }
        
        if let bookmark {
            _ = store.updateBookmark(guid: bookmark.guid, title: title, url: url, parentGUID: selectedFolderID)
        } else {
            _ = store.addBookmark(title: title, url: url, to: selectedFolderID)
        }
        
        dismiss(animated: true)
    }
    
    @objc private func deleteBookmark() {
        guard let bookmark else {
            return
        }
        
        _ = store.removeBookmark(guid: bookmark.guid)
        dismiss(animated: true)
    }
    
    @objc private func cancel() {
        dismiss(animated: true)
    }
    
    @objc private func validateSaveButton() {
        let title = titleField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let urlString = urlField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        navigationItem.rightBarButtonItem?.isEnabled = !title.isEmpty && URL(string: urlString) != nil
    }
    
    // MARK: - Folder Loading
    
    private func reloadFolderRows() {
        let root = limitsToFavorites ? store.favoritesFolderHierarchy() : store.childFolders()
        folderRows = makeBookmarkFolderRows(root: root, store: store)
        if selectedFolderID == nil {
            selectedFolderID = root.parent.guid
        }
    }
}
