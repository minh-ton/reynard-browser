//
//  AddressBar.swift
//  Reynard
//
//  Created by Minh Ton on 5/3/26.
//

import UIKit

protocol AddressBarDelegate: AnyObject {
    func addressBarDidRequestReloadOrStop(_ addressBar: AddressBar)
    func addressBarAddonItems(_ addressBar: AddressBar) -> [AddressBarMenu.AddonItem]
    func addressBar(_ addressBar: AddressBar, didSelectAddon item: AddonMenuItem)
    func addressBarDidRequestPageZoom(_ addressBar: AddressBar)
    func addressBarDidRequestWebsiteModeChange(_ addressBar: AddressBar)
    func addressBarDidRequestWebsiteSettings(_ addressBar: AddressBar)
    func addressBar(_ addressBar: AddressBar, didRequestBookmarkInFavorites favorites: Bool)
    func addressBarShareableURL(_ addressBar: AddressBar) -> URL?
}

final class AddressBar: UIView {
    private enum UX {
        static let addressBarBackgroundCornerRadius: CGFloat = 16
        static let addressBarContentHorizontalInset: CGFloat = 12
        static let addressBarButtonToTextSpacing: CGFloat = 8
        static let addressBarDismissButtonSpacing: CGFloat = 9
        static let addressBarButtonSize: CGFloat = 18
        static let phoneAddressBarHeight: CGFloat = 42
        static let compactAddressBarHeight: CGFloat = 38
        static let padAddressBarHeight: CGFloat = 38
        static let addressBarLoadingProgressHeight: CGFloat = 2
        static let addressBarAutocompleteTrailingInset: CGFloat = 30
        static let addressBarTextFontSize: CGFloat = 17
        static let addressBarDismissButtonAnimationDuration: TimeInterval = 0.2
        static let addressBarBackgroundDarkModeShadowAlpha: CGFloat = 0.3
        static let addressBarBackgroundShadowOpacity: Float = 0.12
        static let addressBarBackgroundShadowRadius: CGFloat = 10
        static let addressBarBackgroundShadowOffset = CGSize(width: 0, height: 2)
    }
    
    enum EditingState: Equatable {
        case inactive
        case focused
        case composing
    }
    
    enum LoadingState {
        case idle
        case loading(progress: Float)
    }
    
    private enum AutocompleteState {
        case none
        case focusPreview
        case suggestion(committedText: String, submissionText: String)
    }
    
    private enum ContentState {
        case placeholder
        case page(NSAttributedString)
        case typedText
    }
    
    private enum LeadingButtonState: Equatable {
        case hidden
        case search
        case menu
        case loading
    }
    
    private enum TrailingButtonState: Equatable {
        case hidden
        case reload
        case stop
    }
    
    private struct RenderModel {
        let content: ContentState
        let leadingButton: LeadingButtonState
        let trailingButton: TrailingButtonState
    }
    
    static let placeholderText = "Search or enter website name"
    
    private weak var delegate: AddressBarDelegate?
    private weak var searchDelegate: AddressBarSearchDelegate?
    
    private var editingState: EditingState = .inactive
    private var loadingState: LoadingState = .idle
    private var position: BrowserChromePosition = .bottom
    private var chromeMode: BrowserChromeMode = .phone
    private var autocompleteState: AutocompleteState = .none
    private var autocompleteDeletedText: String?
    
    private var currentText: String?
    private var currentLocationText: String?
    private var currentLocationTitle: String?
    private var canShowBarMenu = false
    
    private var preserveAutocompleteAfterResign = false
    private var addonsMenu: UIMenu?
    
    private var lastEditingText = ""
    private var lastEditWasDelete = false
    
    private var textLeadingToButtonConstraint: NSLayoutConstraint!
    private var textLeadingToBackgroundConstraint: NSLayoutConstraint!
    private var textTrailingToButtonConstraint: NSLayoutConstraint!
    private var textTrailingToBackgroundConstraint: NSLayoutConstraint!
    private var labelLeadingToButtonConstraint: NSLayoutConstraint!
    private var labelLeadingToBackgroundConstraint: NSLayoutConstraint!
    private var labelTrailingToButtonConstraint: NSLayoutConstraint!
    private var labelTrailingToBackgroundConstraint: NSLayoutConstraint!
    
    private let addressBarBackground: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .clear
        view.layer.cornerCurve = .continuous
        view.layer.cornerRadius = UX.addressBarBackgroundCornerRadius
        return view
    }()
    
    private let addressBarContent: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ? .tertiarySystemBackground : .systemBackground
        }
        view.layer.cornerCurve = .continuous
        view.layer.cornerRadius = UX.addressBarBackgroundCornerRadius
        view.clipsToBounds = true
        return view
    }()
    
    private let leadingButton: AddressBarButton = {
        let button = AddressBarButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.tintColor = .secondaryLabel
        if #available(iOS 14.0, *) {
            button.showsMenuAsPrimaryAction = true
        }
        button.isUserInteractionEnabled = false
        return button
    }()
    
    private let trailingButton: AddressBarButton = {
        let button = AddressBarButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.tintColor = .label
        button.isHidden = true
        button.isUserInteractionEnabled = false
        return button
    }()
    
    private let textField: AddressBarTextField = {
        let field = AddressBarTextField()
        field.translatesAutoresizingMaskIntoConstraints = false
        field.borderStyle = .none
        field.backgroundColor = .clear
        field.placeholder = AddressBar.placeholderText
        field.keyboardType = .webSearch
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.textContentType = .none
        field.returnKeyType = .go
        field.clearButtonMode = .whileEditing
        return field
    }()
    
    private let addressLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .left
        label.textColor = .label
        label.font = UIFont.systemFont(ofSize: UX.addressBarTextFontSize)
        label.lineBreakMode = .byTruncatingTail
        label.numberOfLines = 1
        label.isUserInteractionEnabled = false
        return label
    }()
    
    private let autocompleteLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .left
        label.textColor = .label
        label.font = UIFont.systemFont(ofSize: UX.addressBarTextFontSize)
        label.lineBreakMode = .byTruncatingTail
        label.numberOfLines = 1
        label.isHidden = true
        return label
    }()
    
    private let autocompleteButton: UIButton = {
        let button = UIButton(type: .custom)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.backgroundColor = .clear
        button.isHidden = true
        return button
    }()
    
    private let progressView: UIProgressView = {
        let view = UIProgressView(progressViewStyle: .default)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.progressTintColor = .label
        view.trackTintColor = .clear
        view.isHidden = true
        return view
    }()
    
    private let dismissButton = AddressBarDismissButton(type: .system)
    private var gestures: AddressBarGestures?
    
    private var backgroundTrailingFullConstraint: NSLayoutConstraint!
    private var backgroundTrailingFocusedConstraint: NSLayoutConstraint!
    private var backgroundHeightConstraint: NSLayoutConstraint!
    private var dismissWidthConstraint: NSLayoutConstraint!
    private var dismissHeightConstraint: NSLayoutConstraint!
    
    // MARK: - Lifecycle
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        configureAppearance()
        configureHierarchy()
        configureConstraints()
        configureTargets()
        configureObservers()
        applyState()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    override var canBecomeFirstResponder: Bool {
        return textField.canBecomeFirstResponder
    }
    
    override func becomeFirstResponder() -> Bool {
        return textField.becomeFirstResponder()
    }
    
    override func resignFirstResponder() -> Bool {
        return textField.resignFirstResponder()
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        let showsShadow = chromeMode != .pad
        addressBarBackground.layer.shadowPath = showsShadow
        ? UIBezierPath(roundedRect: addressBarBackground.bounds, cornerRadius: UX.addressBarBackgroundCornerRadius).cgPath
        : nil
    }
    
    // MARK: - Configuration
    
    func configure(delegate: AddressBarDelegate, searchDelegate: AddressBarSearchDelegate, gestureDelegate: AddressBarGestureDelegate) {
        self.delegate = delegate
        self.searchDelegate = searchDelegate
        textField.delegate = self
        let gestures = AddressBarGestures(addressBar: self, delegate: gestureDelegate)
        self.gestures = gestures
        gestures.configure()
    }
    
    func setText(
        _ text: String?,
        locationText: String? = nil,
        locationTitle: String? = nil,
        showsBarMenu: Bool = false
    ) {
        currentText = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        currentLocationText = locationText?.trimmingCharacters(in: .whitespacesAndNewlines)
        currentLocationTitle = locationTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        canShowBarMenu = showsBarMenu
        guard editingState == .inactive else {
            applyState()
            return
        }
        
        textField.text = currentText
        clearAutocomplete()
        applyState()
    }
    
    func updateMenu(url: String?, usesDesktopWebsite: Bool?) {
        addonsMenu = AddressBarMenu.makeMenu(
            selectedURL: url,
            usesDesktopWebsite: usesDesktopWebsite,
            addonItems: delegate?.addressBarAddonItems(self) ?? [],
            onAddonSelected: { [weak self] item in
                guard let self else { return }
                self.delegate?.addressBar(self, didSelectAddon: item)
            },
            onPageZoom: { [weak self] in
                guard let self else { return }
                self.delegate?.addressBarDidRequestPageZoom(self)
            },
            onChangeWebsiteMode: { [weak self] in
                guard let self else { return }
                self.delegate?.addressBarDidRequestWebsiteModeChange(self)
            },
            onWebsiteSettings: { [weak self] in
                guard let self else { return }
                self.delegate?.addressBarDidRequestWebsiteSettings(self)
            },
            onBookmark: { [weak self] favorites in
                guard let self else { return }
                self.delegate?.addressBar(self, didRequestBookmarkInFavorites: favorites)
            }
        )
        applyState()
    }
    
    func setEditingState(_ state: EditingState) {
        editingState = state
        applyState()
    }
    
    func setPreservesAutocompleteAfterResign(_ preserve: Bool) {
        preserveAutocompleteAfterResign = preserve
        if !preserve && !textField.isFirstResponder {
            clearAutocomplete()
        }
    }
    
    func updateLayout(position: BrowserChromePosition, chromeMode: BrowserChromeMode) {
        self.position = position
        self.chromeMode = chromeMode
        backgroundHeightConstraint.constant = height(for: chromeMode)
        dismissWidthConstraint.constant = height(for: chromeMode)
        dismissHeightConstraint.constant = height(for: chromeMode)
        dismissButton.setShadowVisible(chromeMode == .phone)
        applyState()
    }
    
    func setDismissButtonVisible(_ visible: Bool, animated: Bool) {
        backgroundTrailingFullConstraint.isActive = !visible
        backgroundTrailingFocusedConstraint.isActive = visible
        if visible {
            dismissButton.isHidden = false
        }
        let animations = {
            self.dismissButton.alpha = visible ? 1 : 0
            self.layoutIfNeeded()
        }
        let completion: (Bool) -> Void = { _ in
            if !visible {
                self.dismissButton.isHidden = true
            }
        }
        if animated {
            UIView.animate(withDuration: UX.addressBarDismissButtonAnimationDuration, animations: animations, completion: completion)
        } else {
            animations()
            completion(true)
        }
    }
    
    // MARK: - Text And Autocomplete
    
    private var editingText: String? {
        return textField.text
    }
    
    func setAutocomplete(displayText: NSAttributedString, committedText: String, submissionText: String) {
        guard textField.isFirstResponder else {
            return
        }
        
        autocompleteState = .suggestion(committedText: committedText, submissionText: submissionText)
        autocompleteLabel.attributedText = displayText
        autocompleteLabel.isHidden = false
        updateAutocompletePresentation()
    }
    
    func recordEditForAutocomplete(previousText: String, currentText: String, isDelete: Bool) {
        autocompleteDeletedText = isDelete && previousText.count > currentText.count ? currentText : nil
    }
    
    func applySearchAutocomplete(query: String, result: UserDataSearchResult?) {
        guard isEditingText else {
            clearAutocomplete()
            return
        }
        
        let currentText = editingText ?? ""
        guard !query.isEmpty,
              currentText == query,
              autocompleteDeletedText != query,
              let result,
              let autocomplete = searchAutocompletePresentation(for: result, query: query) else {
            clearAutocomplete()
            return
        }
        
        setAutocomplete(
            displayText: autocomplete.displayText,
            committedText: autocomplete.committedText,
            submissionText: autocomplete.submissionText
        )
    }
    
    func clearAutocomplete() {
        autocompleteState = .none
        autocompleteLabel.attributedText = nil
        autocompleteLabel.isHidden = true
        updateAutocompletePresentation()
    }
    
    var isShowingAutocomplete: Bool {
        if case .suggestion = autocompleteState { return true }
        return false
    }
    
    private var isShowingOverlay: Bool {
        if case .none = autocompleteState { return false }
        return true
    }
    
    // MARK: - Loading And Menu
    
    func setLoadingProgress(_ progress: Float, isLoading: Bool) {
        loadingState = isLoading ? .loading(progress: progress) : .idle
        applyState()
    }
    
    func performAfterMenuDismissal(_ action: @escaping () -> Void) {
        leadingButton.performAfterMenuDismissal(action)
    }
    
    // MARK: - Tab Transitions
    
    func resetHorizontalTransition() {
        gestures?.resetHorizontalTransition()
    }
    
    func performAfterTransition(_ completion: @escaping () -> Void) -> Bool {
        gestures?.performAfterTransition(completion) ?? false
    }
    
    func animateAutomaticNewTabTransition(to tab: Tab, completion: @escaping () -> Void) {
        gestures?.animateAutomaticNewTabTransition(to: tab, completion: completion)
    }
    
    var isEditingText: Bool {
        return textField.isFirstResponder
    }
    
    // MARK: - View Setup
    
    private func configureAppearance() {
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear
        clipsToBounds = false
        addressBarBackground.layer.shadowColor = traitCollection.userInterfaceStyle == .dark
        ? UIColor.white.withAlphaComponent(UX.addressBarBackgroundDarkModeShadowAlpha).cgColor
        : UIColor.black.cgColor
        addressBarBackground.layer.shadowOpacity = UX.addressBarBackgroundShadowOpacity
        addressBarBackground.layer.shadowRadius = UX.addressBarBackgroundShadowRadius
        addressBarBackground.layer.shadowOffset = UX.addressBarBackgroundShadowOffset
        addressBarBackground.layer.masksToBounds = false
    }
    
    private func configureHierarchy() {
        addSubview(addressBarBackground)
        addSubview(dismissButton)
        addressBarBackground.addSubview(addressBarContent)
        addressBarContent.addSubview(leadingButton)
        addressBarContent.addSubview(trailingButton)
        addressBarContent.addSubview(textField)
        addressBarContent.addSubview(autocompleteButton)
        addressBarContent.addSubview(addressLabel)
        addressBarContent.addSubview(autocompleteLabel)
        addressBarContent.addSubview(progressView)
    }
    
    private func configureConstraints() {
        backgroundTrailingFullConstraint = addressBarBackground.trailingAnchor.constraint(equalTo: trailingAnchor)
        backgroundTrailingFocusedConstraint = addressBarBackground.trailingAnchor.constraint(
            equalTo: dismissButton.leadingAnchor,
            constant: -UX.addressBarDismissButtonSpacing
        )
        backgroundHeightConstraint = addressBarBackground.heightAnchor.constraint(equalToConstant: UX.phoneAddressBarHeight)
        dismissWidthConstraint = dismissButton.widthAnchor.constraint(equalToConstant: UX.phoneAddressBarHeight)
        dismissHeightConstraint = dismissButton.heightAnchor.constraint(equalToConstant: UX.phoneAddressBarHeight)
        
        NSLayoutConstraint.activate([
            addressBarBackground.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundTrailingFullConstraint,
            addressBarBackground.topAnchor.constraint(equalTo: topAnchor),
            addressBarBackground.bottomAnchor.constraint(equalTo: bottomAnchor),
            backgroundHeightConstraint,
            
            addressBarContent.leadingAnchor.constraint(equalTo: addressBarBackground.leadingAnchor),
            addressBarContent.trailingAnchor.constraint(equalTo: addressBarBackground.trailingAnchor),
            addressBarContent.topAnchor.constraint(equalTo: addressBarBackground.topAnchor),
            addressBarContent.bottomAnchor.constraint(equalTo: addressBarBackground.bottomAnchor),
            
            dismissButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            dismissButton.centerYAnchor.constraint(equalTo: addressBarBackground.centerYAnchor),
            dismissWidthConstraint,
            dismissHeightConstraint,
            
            leadingButton.leadingAnchor.constraint(equalTo: addressBarContent.leadingAnchor, constant: UX.addressBarContentHorizontalInset),
            leadingButton.centerYAnchor.constraint(equalTo: addressBarContent.centerYAnchor),
            leadingButton.widthAnchor.constraint(equalToConstant: UX.addressBarButtonSize),
            leadingButton.heightAnchor.constraint(equalToConstant: UX.addressBarButtonSize),
            
            trailingButton.trailingAnchor.constraint(equalTo: addressBarContent.trailingAnchor, constant: -UX.addressBarContentHorizontalInset),
            trailingButton.centerYAnchor.constraint(equalTo: addressBarContent.centerYAnchor),
            trailingButton.widthAnchor.constraint(equalToConstant: UX.addressBarButtonSize),
            trailingButton.heightAnchor.constraint(equalToConstant: UX.addressBarButtonSize),
            
            textField.topAnchor.constraint(equalTo: addressBarContent.topAnchor),
            textField.bottomAnchor.constraint(equalTo: addressBarContent.bottomAnchor),
            
            autocompleteButton.leadingAnchor.constraint(equalTo: textField.leadingAnchor),
            autocompleteButton.trailingAnchor.constraint(equalTo: textField.trailingAnchor, constant: -UX.addressBarAutocompleteTrailingInset),
            autocompleteButton.topAnchor.constraint(equalTo: textField.topAnchor),
            autocompleteButton.bottomAnchor.constraint(equalTo: textField.bottomAnchor),
            
            autocompleteLabel.leadingAnchor.constraint(equalTo: textField.leadingAnchor),
            autocompleteLabel.trailingAnchor.constraint(equalTo: textField.trailingAnchor, constant: -UX.addressBarAutocompleteTrailingInset),
            autocompleteLabel.topAnchor.constraint(equalTo: textField.topAnchor),
            autocompleteLabel.bottomAnchor.constraint(equalTo: textField.bottomAnchor),
            
            addressLabel.topAnchor.constraint(equalTo: addressBarContent.topAnchor),
            addressLabel.bottomAnchor.constraint(equalTo: addressBarContent.bottomAnchor),
            
            progressView.leadingAnchor.constraint(equalTo: addressBarContent.leadingAnchor),
            progressView.trailingAnchor.constraint(equalTo: addressBarContent.trailingAnchor),
            progressView.bottomAnchor.constraint(equalTo: addressBarContent.bottomAnchor),
            progressView.heightAnchor.constraint(equalToConstant: UX.addressBarLoadingProgressHeight),
        ])
        
        textLeadingToButtonConstraint = textField.leadingAnchor.constraint(equalTo: leadingButton.trailingAnchor, constant: UX.addressBarButtonToTextSpacing)
        textLeadingToBackgroundConstraint = textField.leadingAnchor.constraint(equalTo: addressBarContent.leadingAnchor, constant: UX.addressBarContentHorizontalInset)
        textTrailingToButtonConstraint = textField.trailingAnchor.constraint(equalTo: trailingButton.leadingAnchor, constant: -UX.addressBarButtonToTextSpacing)
        textTrailingToBackgroundConstraint = textField.trailingAnchor.constraint(equalTo: addressBarContent.trailingAnchor, constant: -UX.addressBarContentHorizontalInset)
        labelLeadingToButtonConstraint = addressLabel.leadingAnchor.constraint(equalTo: leadingButton.trailingAnchor, constant: UX.addressBarButtonToTextSpacing)
        labelLeadingToBackgroundConstraint = addressLabel.leadingAnchor.constraint(equalTo: addressBarContent.leadingAnchor, constant: UX.addressBarContentHorizontalInset)
        labelTrailingToButtonConstraint = addressLabel.trailingAnchor.constraint(equalTo: trailingButton.leadingAnchor, constant: -UX.addressBarButtonToTextSpacing)
        labelTrailingToBackgroundConstraint = addressLabel.trailingAnchor.constraint(equalTo: addressBarContent.trailingAnchor, constant: -UX.addressBarContentHorizontalInset)
    }
    
    private func configureTargets() {
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleBarTap))
        tapGesture.cancelsTouchesInView = true
        tapGesture.delegate = self
        addGestureRecognizer(tapGesture)
        addressBarContent.addInteraction(UIContextMenuInteraction(delegate: self))
        textField.addTarget(self, action: #selector(textFieldDidChange), for: .editingChanged)
        trailingButton.addTarget(self, action: #selector(handleTrailingButtonTap), for: .touchUpInside)
        autocompleteButton.addTarget(self, action: #selector(handleOverlayButtonTap), for: .touchUpInside)
        dismissButton.addTarget(self, action: #selector(handleDismissButtonTap), for: .touchUpInside)
    }
    
    private func configureObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(showFullWebsiteAddressDidChange),
            name: .showFullWebsiteAddressDidChange,
            object: nil
        )
    }
    
    // MARK: - State Rendering
    
    private func applyState() {
        applyRenderModel(resolveRenderModel())
        applyLoadingState()
        addressBarBackground.layer.shadowOpacity = chromeMode == .pad ? 0 : UX.addressBarBackgroundShadowOpacity
        setNeedsLayout()
    }
    
    private func applyLoadingState() {
        switch loadingState {
        case .idle:
            progressView.isHidden = true
        case let .loading(progress):
            progressView.progress = progress
            progressView.isHidden = false
        }
    }
    
    private func resolveRenderModel() -> RenderModel {
        let content = resolveContentState()
        return RenderModel(
            content: content,
            leadingButton: resolveLeadingButtonState(for: content),
            trailingButton: resolveTrailingButtonState(for: content)
        )
    }
    
    private func resolveContentState() -> ContentState {
        if editingState != .inactive {
            let typedText = textField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return typedText.isEmpty ? .placeholder : .typedText
        }
        
        guard let displayText = displayAttributedText() else {
            return .placeholder
        }
        return .page(displayText)
    }
    
    private func resolveLeadingButtonState(for content: ContentState) -> LeadingButtonState {
        guard editingState == .inactive else { return .hidden }
        if case .loading = loadingState { return .loading }
        switch content {
        case .placeholder:
            return chromeMode == .phone && position == .bottom ? .search : .hidden
        case .page:
            return canShowBarMenu ? .menu : .hidden
        case .typedText:
            return .hidden
        }
    }
    
    private func resolveTrailingButtonState(for content: ContentState) -> TrailingButtonState {
        guard editingState == .inactive else { return .hidden }
        if case .loading = loadingState { return .stop }
        if case .page = content { return .reload }
        return .hidden
    }
    
    private func applyRenderModel(_ model: RenderModel) {
        applyContentState(model.content)
        applyLeadingButtonState(model.leadingButton)
        applyTrailingButtonState(model.trailingButton)
        
        let showsLeadingButton = model.leadingButton != .hidden
        let showsTrailingButton = model.trailingButton != .hidden
        
        NSLayoutConstraint.deactivate([
            textLeadingToButtonConstraint,
            textLeadingToBackgroundConstraint,
            textTrailingToButtonConstraint,
            textTrailingToBackgroundConstraint,
            labelLeadingToButtonConstraint,
            labelLeadingToBackgroundConstraint,
            labelTrailingToButtonConstraint,
            labelTrailingToBackgroundConstraint,
        ])
        
        NSLayoutConstraint.activate([
            showsLeadingButton ? textLeadingToButtonConstraint : textLeadingToBackgroundConstraint,
            showsTrailingButton ? textTrailingToButtonConstraint : textTrailingToBackgroundConstraint,
            showsLeadingButton ? labelLeadingToButtonConstraint : labelLeadingToBackgroundConstraint,
            showsTrailingButton ? labelTrailingToButtonConstraint : labelTrailingToBackgroundConstraint,
        ])
    }
    
    private func applyContentState(_ state: ContentState) {
        switch state {
        case .placeholder, .typedText:
            addressLabel.isHidden = true
            textField.isHidden = false
        case let .page(displayText):
            addressLabel.attributedText = displayText
            addressLabel.isHidden = false
            textField.isHidden = true
        }
        textField.textAlignment = .left
    }
    
    private func applyLeadingButtonState(_ state: LeadingButtonState) {
        guard state != .hidden else {
            leadingButton.isHidden = true
            leadingButton.setImage(nil, for: .normal)
            leadingButton.setMenuPreservingPresentation(nil)
            leadingButton.isUserInteractionEnabled = false
            return
        }
        
        leadingButton.isHidden = false
        if state == .search {
            leadingButton.tintColor = .secondaryLabel
            leadingButton.setImage(UIImage(named: "reynard.magnifyingglass"), for: .normal)
            leadingButton.setMenuPreservingPresentation(nil)
            leadingButton.isUserInteractionEnabled = false
            return
        }
        
        if state == .loading {
            leadingButton.tintColor = .secondaryLabel
            leadingButton.setImage(UIImage(named: "reynard.list.bullet.below.rectangle"), for: .normal)
            leadingButton.setMenuPreservingPresentation(nil)
            leadingButton.isUserInteractionEnabled = false
            return
        }
        
        leadingButton.tintColor = .label
        leadingButton.setImage(UIImage(named: "reynard.list.bullet.below.rectangle"), for: .normal)
        leadingButton.setMenuPreservingPresentation(addonsMenu)
        leadingButton.isUserInteractionEnabled = addonsMenu != nil
    }
    
    private func applyTrailingButtonState(_ state: TrailingButtonState) {
        let visible = state != .hidden
        trailingButton.isHidden = !visible
        trailingButton.isUserInteractionEnabled = visible
        guard visible else {
            return
        }
        trailingButton.setImage(UIImage(named: state == .stop ? "reynard.xmark" : "reynard.arrow.clockwise"), for: .normal)
    }
    
    private func height(for chromeMode: BrowserChromeMode) -> CGFloat {
        switch chromeMode {
        case .phone: return UX.phoneAddressBarHeight
        case .compact: return UX.compactAddressBarHeight
        case .pad: return UX.padAddressBarHeight
        }
    }
    
    // MARK: - Display Content
    
    private func displayAttributedText() -> NSAttributedString? {
        guard let currentText, !currentText.isEmpty else {
            return nil
        }
        
        guard !Prefs.AppearanceSettings.showsFullWebsiteAddress,
              canShowBarMenu,
              let host = locationHost() else {
            return NSAttributedString(
                string: currentText,
                attributes: [.foregroundColor: UIColor.label]
            )
        }
        
        let attributedText = NSMutableAttributedString(
            string: host,
            attributes: [.foregroundColor: UIColor.label]
        )
        attributedText.append(
            NSAttributedString(
                string: " / ",
                attributes: [.foregroundColor: UIColor.secondaryLabel]
            )
        )
        if let title = currentLocationTitle,
           !title.isEmpty {
            attributedText.append(
                NSAttributedString(
                    string: title,
                    attributes: [.foregroundColor: UIColor.secondaryLabel]
                )
            )
        }
        return attributedText
    }
    
    private func locationHost() -> String? {
        let sourceText = currentLocationText ?? currentText
        guard let sourceText,
              let host = URL(string: sourceText)?.host,
              !host.isEmpty else {
            return nil
        }
        return host
    }
    
    @objc
    private func showFullWebsiteAddressDidChange() {
        guard editingState == .inactive else {
            return
        }
        applyState()
    }
    
    // MARK: - Actions
    
    @objc
    private func handleBarTap() {
        if textField.isFirstResponder {
            if isShowingOverlay {
                handleOverlayTap()
            }
            return
        }
        
        textField.becomeFirstResponder()
    }
    
    @objc
    private func textFieldDidChange() {
        let previousText = lastEditingText
        clearAutocomplete()
        let currentText = textField.text ?? ""
        lastEditingText = currentText
        searchDelegate?.addressBar(self, didChangeText: currentText, previousText: previousText, isDelete: lastEditWasDelete)
        lastEditWasDelete = false
        if textField.isFirstResponder {
            applyState()
        }
    }
    
    @objc
    private func handleTrailingButtonTap() {
        delegate?.addressBarDidRequestReloadOrStop(self)
    }
    
    @objc
    private func handleDismissButtonTap() {
        searchDelegate?.addressBarDidTapDismiss(self)
    }
    
    @objc
    private func handleOverlayButtonTap() {
        handleOverlayTap()
    }
    
    private func handleOverlayTap() {
        if !textField.isFirstResponder {
            _ = textField.becomeFirstResponder()
        }
        
        if isShowingAutocomplete {
            commitAutocompleteForEditing()
            return
        }
        
        if case .focusPreview = autocompleteState {
            clearFocusPreview()
            selectAllText()
        }
    }
    
    // MARK: - Autocomplete Presentation
    
    private func commitAutocompleteForEditing() {
        guard case let .suggestion(committedText, _) = autocompleteState else {
            return
        }
        clearAutocomplete()
        textField.text = committedText
        lastEditingText = committedText
        restoreCaretToEnd()
    }
    
    private func showFocusPreview() {
        guard let text = textField.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            return
        }
        
        let attributedText = NSAttributedString(
            string: text,
            attributes: [
                .foregroundColor: UIColor.label,
                .backgroundColor: UIColor.systemGray4
            ]
        )
        autocompleteLabel.attributedText = attributedText
        autocompleteLabel.isHidden = false
        autocompleteState = .focusPreview
        updateAutocompletePresentation()
    }
    
    private func searchAutocompletePresentation(
        for result: UserDataSearchResult,
        query: String
    ) -> (displayText: NSAttributedString, committedText: String, submissionText: String)? {
        let title = result.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let strippedURL = URLUtils.strippedURLString(result.url.absoluteString, trimsTrailingSlash: true)
        let queryAttributes: [NSAttributedString.Key: Any] = [.foregroundColor: UIColor.label]
        let completionAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: UIColor.label,
            .backgroundColor: UIColor.systemGray4
        ]
        let suffixAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: UIColor.systemBlue,
            .backgroundColor: UIColor.systemGray4
        ]
        
        if title.hasPrefix(query) {
            let attributed = NSMutableAttributedString(
                string: String(title.prefix(query.count)),
                attributes: queryAttributes
            )
            let completion = String(title.dropFirst(query.count))
            if !completion.isEmpty {
                attributed.append(NSAttributedString(string: completion, attributes: completionAttributes))
            }
            attributed.append(NSAttributedString(string: " — \(strippedURL)", attributes: suffixAttributes))
            return (attributed, strippedURL, result.url.absoluteString)
        }
        
        let strippedQuery = URLUtils.normalizedURLMatchString(from: query)
        let strippedURLMatchValue = URLUtils.normalizedURLMatchString(from: result.url.absoluteString)
        guard !strippedQuery.isEmpty else {
            return nil
        }
        
        let completedURL: String
        if strippedURLMatchValue.hasPrefix(strippedQuery) {
            completedURL = URLUtils.autocompleteURLString(for: query, url: result.url) ?? strippedURL
        } else if let matchedDomain = URLUtils.domainCompletion(for: strippedQuery, url: result.url) {
            completedURL = matchedDomain
        } else {
            return nil
        }
        
        let attributed = NSMutableAttributedString(
            string: query,
            attributes: queryAttributes
        )
        let completion = String(completedURL.dropFirst(query.count))
        if !completion.isEmpty {
            attributed.append(NSAttributedString(string: completion, attributes: completionAttributes))
        }
        attributed.append(NSAttributedString(string: " — \(title)", attributes: suffixAttributes))
        return (attributed, completedURL, result.url.absoluteString)
    }
    
    private func clearFocusPreview() {
        autocompleteState = .none
        autocompleteLabel.attributedText = nil
        autocompleteLabel.isHidden = true
        updateAutocompletePresentation()
    }
    
    private func updateAutocompletePresentation() {
        textField.isAutocompleteActive = isShowingOverlay
        textField.textColor = isShowingOverlay ? .clear : .label
        textField.tintColor = isShowingOverlay ? .clear : tintColor
        autocompleteButton.isHidden = !isShowingOverlay
    }
    
    private func restoreCaretToEnd() {
        let end = textField.endOfDocument
        textField.selectedTextRange = textField.textRange(from: end, to: end)
    }
    
    private func selectAllText() {
        let start = textField.beginningOfDocument
        let end = textField.endOfDocument
        textField.selectedTextRange = textField.textRange(from: start, to: end)
    }
}

// MARK: - UIContextMenuInteractionDelegate

extension AddressBar: UIContextMenuInteractionDelegate {
    func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        configurationForMenuAtLocation location: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard editingState == .inactive,
              let url = delegate?.addressBarShareableURL(self) else {
            return nil
        }
        
        return UIContextMenuConfiguration(identifier: url as NSURL, previewProvider: nil) { _ in
            UIMenu(title: "", children: [
                UIAction(title: "Copy URL", image: UIImage(named: "reynard.document.on.document")) { _ in
                    UIPasteboard.general.string = url.absoluteString
                },
            ])
        }
    }
}

// MARK: - UITextFieldDelegate

extension AddressBar: UITextFieldDelegate {
    func textField(
        _ textField: UITextField,
        shouldChangeCharactersIn range: NSRange,
        replacementString string: String
    ) -> Bool {
        if case .focusPreview = autocompleteState {
            clearFocusPreview()
            let previousText = lastEditingText
            if string.isEmpty {
                self.textField.text = ""
                lastEditWasDelete = true
            } else {
                self.textField.text = string
                lastEditWasDelete = false
            }
            let currentText = self.textField.text ?? ""
            lastEditingText = currentText
            searchDelegate?.addressBar(self, didChangeText: currentText, previousText: previousText, isDelete: lastEditWasDelete)
            lastEditWasDelete = false
            if self.textField.isFirstResponder {
                applyState()
            }
            return false
        }
        
        guard isShowingAutocomplete,
              string.isEmpty,
              range.length > 0 else {
            lastEditWasDelete = string.isEmpty && range.length > 0
            return true
        }
        
        clearAutocomplete()
        restoreCaretToEnd()
        lastEditWasDelete = true
        return false
    }
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        let searchText: String?
        if case let .suggestion(_, submissionText) = autocompleteState {
            searchText = submissionText
        } else {
            searchText = textField.text?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let searchText, !searchText.isEmpty else {
            return false
        }
        
        searchDelegate?.addressBarDidSubmit(searchText)
        return true
    }
    
    func textFieldDidBeginEditing(_ textField: UITextField) {
        editingState = .focused
        if let currentText,
           !currentText.isEmpty {
            textField.text = currentText
        }
        lastEditingText = textField.text ?? ""
        let preservesAutocomplete = preserveAutocompleteAfterResign && isShowingAutocomplete
        preserveAutocompleteAfterResign = false
        if !preservesAutocomplete {
            clearAutocomplete()
        } else {
            updateAutocompletePresentation()
        }
        applyState()
        searchDelegate?.addressBarDidBeginEditing(self)
        if !preservesAutocomplete {
            showFocusPreview()
        }
    }
    
    func textFieldDidEndEditing(_ textField: UITextField) {
        if editingState != .composing {
            editingState = .inactive
        }
        if !preserveAutocompleteAfterResign {
            clearAutocomplete()
        } else {
            updateAutocompletePresentation()
        }
        currentText = textField.text?.trimmingCharacters(in: .whitespacesAndNewlines)
        currentLocationText = nil
        currentLocationTitle = nil
        canShowBarMenu = false
        applyState()
        searchDelegate?.addressBarDidEndEditing(self)
    }
}

// MARK: - UIGestureRecognizerDelegate

extension AddressBar: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if touch.view?.isDescendant(of: leadingButton) == true {
            return false
        }
        
        if touch.view?.isDescendant(of: trailingButton) == true {
            return false
        }
        
        if touch.view?.isDescendant(of: textField) == true {
            return false
        }
        
        return true
    }
}
