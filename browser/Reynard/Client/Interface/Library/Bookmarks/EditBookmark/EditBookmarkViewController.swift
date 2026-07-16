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
    private var pendingCustomIconMutation: BookmarkCustomIconMutation = .unchanged
    private lazy var iconEditingCoordinator = BookmarkIconEditingCoordinator(
        presenter: self
    ) { [weak self] icon in
        self?.pendingCustomIconMutation = .set(icon)
        self?.applyIconPreview(BookmarkCustomIconRenderer.image(for: icon))
    }
    
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
        imageView.isUserInteractionEnabled = true
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
        imageView.isUserInteractionEnabled = true
        return imageView
    }()
    
    private lazy var titleField: UITextField = {
        let textField = UITextField()
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.borderStyle = .none
        textField.clearButtonMode = .whileEditing
        textField.font = .preferredFont(forTextStyle: .body)
        textField.adjustsFontForContentSizeCategory = true
        textField.placeholder = NSLocalizedString("Title", comment: "")
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
        textField.placeholder = NSLocalizedString("URL", comment: "")
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
        
        title = limitsToFavorites ? NSLocalizedString("Add to Favorites", comment: "") : (bookmark == nil ? NSLocalizedString("Add Bookmark", comment: "") : NSLocalizedString("Edit Bookmark", comment: ""))
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
            navigationItem.rightBarButtonItem = UIBarButtonItem(title: NSLocalizedString("Save", comment: ""), style: .done, target: self, action: #selector(saveBookmark))
        }
        
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        
        reloadFolderRows()
        configureIconEditing()
        
        storeObserver = NotificationCenter.default.addObserver(
            forName: .bookmarkStoreDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reloadFolderRows()
            self?.tableView.reloadSections(IndexSet(integer: 2), with: .none)
        }
        
        loadInitialIcon()
        
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
        section == 2 ? NSLocalizedString("Location", comment: "") : nil
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
            cell.textLabel?.text = NSLocalizedString("New Folder", comment: "")
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
        
        let savedBookmark: BookmarkSnapshot?
        if let bookmark {
            savedBookmark = store.updateBookmark(
                guid: bookmark.guid,
                title: title,
                url: url,
                parentGUID: selectedFolderID,
                customIcon: pendingCustomIconMutation
            )
        } else {
            savedBookmark = store.addBookmark(
                title: title,
                url: url,
                to: selectedFolderID,
                customIcon: pendingCustomIconMutation
            )
        }

        guard savedBookmark != nil else {
            presentSaveError()
            return
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

    @objc private func editIcon() {
        view.endEditing(true)
        let alert = UIAlertController(
            title: NSLocalizedString("Bookmark Icon", comment: ""),
            message: nil,
            preferredStyle: .actionSheet
        )
        alert.addAction(UIAlertAction(title: NSLocalizedString("Choose Photo", comment: ""), style: .default) { [weak self] _ in
            self?.iconEditingCoordinator.choosePhoto()
        })
        alert.addAction(UIAlertAction(title: NSLocalizedString("Choose File", comment: ""), style: .default) { [weak self] _ in
            self?.iconEditingCoordinator.chooseFile()
        })
        alert.addAction(UIAlertAction(title: NSLocalizedString("Choose Symbol & Color", comment: ""), style: .default) { [weak self] _ in
            guard let self else {
                return
            }
            iconEditingCoordinator.chooseSymbol(initialIcon: currentCustomIcon)
        })
        if hasCustomIconOverride {
            alert.addAction(UIAlertAction(title: NSLocalizedString("Restore Website Icon", comment: ""), style: .destructive) { [weak self] _ in
                self?.restoreWebsiteIcon()
            })
        }
        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel))
        alert.popoverPresentationController?.sourceView = titleFaviconView
        alert.popoverPresentationController?.sourceRect = titleFaviconView.bounds
        present(alert, animated: true)
    }
    
    // MARK: - Folder Loading
    
    private func reloadFolderRows() {
        let root = limitsToFavorites ? store.favoritesFolderHierarchy() : store.childFolders()
        folderRows = makeBookmarkFolderRows(root: root, store: store)
        if selectedFolderID == nil {
            selectedFolderID = root.parent.guid
        }
    }

    private var hasCustomIconOverride: Bool {
        return currentCustomIcon != nil
    }

    private var currentCustomIcon: BookmarkCustomIcon? {
        let storedIcon = bookmark.flatMap { store.customIcon(for: $0.guid) }
        return pendingCustomIconMutation.resolved(over: storedIcon)
    }

    private func configureIconEditing() {
        let titleTap = UITapGestureRecognizer(target: self, action: #selector(editIcon))
        let urlTap = UITapGestureRecognizer(target: self, action: #selector(editIcon))
        titleFaviconView.addGestureRecognizer(titleTap)
        urlFaviconView.addGestureRecognizer(urlTap)
        let label = NSLocalizedString("Edit Bookmark Icon", comment: "")
        titleFaviconView.accessibilityLabel = label
        urlFaviconView.accessibilityLabel = label
        titleFaviconView.isAccessibilityElement = true
        urlFaviconView.isAccessibilityElement = false
        titleFaviconView.accessibilityTraits = .button
        urlFaviconView.accessibilityTraits = .button
    }

    private func loadInitialIcon() {
        if let bookmark,
           let customIcon = store.customIcon(for: bookmark.guid),
           let image = BookmarkCustomIconRenderer.image(for: customIcon) {
            applyIconPreview(image)
            return
        }
        loadWebsiteIcon()
    }

    private func restoreWebsiteIcon() {
        pendingCustomIconMutation = .remove
        loadWebsiteIcon()
    }

    private func loadWebsiteIcon() {
        faviconTask?.cancel()
        guard let url = URL(string: urlField.text ?? "") else {
            applyIconPreview(nil)
            return
        }
        if let image = FaviconStore.shared.cachedFavicon(for: url) {
            applyIconPreview(image)
            return
        }
        applyIconPreview(nil)
        faviconTask = Task { [weak self] in
            let image = await FaviconStore.shared.favicon(for: url)
            guard !Task.isCancelled else {
                return
            }
            await MainActor.run {
                self?.applyIconPreview(image)
            }
        }
    }

    private func applyIconPreview(_ image: UIImage?) {
        let resolvedImage = image ?? UIImage(named: "reynard.globe")
        titleFaviconView.image = resolvedImage
        urlFaviconView.image = resolvedImage
        let tintColor: UIColor? = image == nil ? .secondaryLabel : nil
        titleFaviconView.tintColor = tintColor
        urlFaviconView.tintColor = tintColor
    }

    private func presentSaveError() {
        let alert = UIAlertController(
            title: NSLocalizedString("Unable to Save Bookmark", comment: ""),
            message: NSLocalizedString("Your bookmark was not changed. Please try again.", comment: ""),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default))
        present(alert, animated: true)
    }
}
