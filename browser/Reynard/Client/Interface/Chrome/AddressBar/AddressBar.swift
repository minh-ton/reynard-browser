//
//  AddressBar.swift
//  Reynard
//
//  Created by Minh Ton on 5/3/26.
//

import UIKit

private final class AutocompleteTextField: UITextField {
    var isAutocompleteActive = false
    private var suppressTextActions = false
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if isAutocompleteActive {
            suppressTextActions = true
            DispatchQueue.main.async { [weak self] in
                self?.suppressTextActions = false
            }
            return
        }
        super.touchesBegan(touches, with: event)
    }
    
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if isAutocompleteActive || suppressTextActions {
            return false
        }
        return super.canPerformAction(action, withSender: sender)
    }
}

protocol AddressBarDelegate: AnyObject {
    func addressBarDidSubmit(_ searchTerm: String)
    func addressBarDidBeginEditing(_ addressBar: AddressBar)
    func addressBarDidEndEditing(_ addressBar: AddressBar)
    func addressBar(_ addressBar: AddressBar, didChangeText text: String, previousText: String, isDelete: Bool)
    func addressBarDidTapTrailingButton(_ addressBar: AddressBar)
}

final class AddressBar: UIView {
    static let placeholderText = "Search or enter website name"
    
    private weak var delegate: AddressBarDelegate?
    private var shadowEnabled = true
    private var hidePlaceholderIcon = false
    private var currentText: String?
    private var currentLocationText: String?
    private var currentLocationTitle: String?
    private var canShowBarMenu = false
    private var isLoading = false
    private var forceComposingAppearanceWhenUnfocused = false
    private var preservesAutocompleteWhenUnfocused = false
    private var addonsMenu: UIMenu?
    private var lastEditingText = ""
    private var lastEditWasDelete = false
    private var showsFocusPreview = false
    private var autocompleteCommittedText: String?
    private var autocompleteSubmissionText: String?
    private var urlFieldLeadingToIconConstraint: NSLayoutConstraint!
    private var urlFieldLeadingToBarConstraint: NSLayoutConstraint!
    private var urlFieldTrailingToButtonConstraint: NSLayoutConstraint!
    private var urlFieldTrailingToBarConstraint: NSLayoutConstraint!
    private var displayLabelLeadingToIconConstraint: NSLayoutConstraint!
    private var displayLabelLeadingToBarConstraint: NSLayoutConstraint!
    private var displayLabelTrailingToButtonConstraint: NSLayoutConstraint!
    private var displayLabelTrailingToBarConstraint: NSLayoutConstraint!
    
    private let backgroundFillView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ? .tertiarySystemBackground : .systemBackground
        }
        view.layer.cornerCurve = .continuous
        view.layer.cornerRadius = 16
        view.layer.masksToBounds = true
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
    
    private let urlField: AutocompleteTextField = {
        let field = AutocompleteTextField()
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
    
    private let displayLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .left
        label.textColor = .label
        label.font = .systemFont(ofSize: 17)
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
        label.font = .systemFont(ofSize: 17)
        label.lineBreakMode = .byTruncatingTail
        label.numberOfLines = 1
        label.isHidden = true
        return label
    }()
    
    private let overlayButton: UIButton = {
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
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        layer.cornerCurve = .continuous
        layer.cornerRadius = 16
        layer.shadowColor = traitCollection.userInterfaceStyle == .dark ? UIColor.white.withAlphaComponent(0.3).cgColor : UIColor.black.cgColor
        layer.shadowOpacity = 0.12
        layer.shadowRadius = 10
        layer.shadowOffset = CGSize(width: 0, height: 2)
        clipsToBounds = false
        setupView()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func configure(delegate: AddressBarDelegate) {
        self.delegate = delegate
        urlField.delegate = self
        urlField.addTarget(self, action: #selector(textFieldDidChange), for: .editingChanged)
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
        if !urlField.isFirstResponder {
            urlField.text = currentText
        }
        clearAutocomplete()
        updateDisplayState()
    }
    
    func setAddonsMenu(_ menu: UIMenu?) {
        addonsMenu = menu
        updateDisplayState()
    }
    
    func setHidePlaceholderIcon(_ hide: Bool) {
        hidePlaceholderIcon = hide
        updateDisplayState()
    }
    
    func setForceComposingAppearanceWhenUnfocused(_ force: Bool) {
        forceComposingAppearanceWhenUnfocused = force
        updateDisplayState()
    }
    
    func setPreservesAutocompleteWhenUnfocused(_ preserve: Bool) {
        preservesAutocompleteWhenUnfocused = preserve
        if !preserve && !urlField.isFirstResponder {
            clearAutocomplete()
        }
    }
    
    func resetOverlayState() {
        showsFocusPreview = false
        clearAutocomplete()
    }
    
    func setShadowEnabled(_ enabled: Bool) {
        shadowEnabled = enabled
        layer.shadowOpacity = enabled ? 0.12 : 0
        setNeedsLayout()
    }
    
    func getText() -> String? {
        urlField.text
    }
    
    func setAutocomplete(displayText: NSAttributedString, committedText: String, submissionText: String) {
        guard urlField.isFirstResponder else {
            return
        }
        
        showsFocusPreview = false
        autocompleteLabel.attributedText = displayText
        autocompleteLabel.isHidden = false
        autocompleteCommittedText = committedText
        autocompleteSubmissionText = submissionText
        updateOverlayState()
    }
    
    func clearAutocomplete() {
        autocompleteCommittedText = nil
        autocompleteSubmissionText = nil
        if !showsFocusPreview {
            autocompleteLabel.attributedText = nil
            autocompleteLabel.isHidden = true
        }
        updateOverlayState()
    }
    
    var isShowingAutocomplete: Bool {
        autocompleteSubmissionText != nil
    }
    
    private var isShowingOverlay: Bool {
        isShowingAutocomplete || showsFocusPreview
    }
    
    func setLoadingProgress(_ progress: Float, isLoading: Bool) {
        progressView.progress = progress
        progressView.isHidden = !isLoading
        self.isLoading = isLoading
        updateDisplayState()
    }
    
    func performAfterMenuDismissal(_ action: @escaping () -> Void) {
        leadingButton.performAfterMenuDismissal(action)
    }
    
    var isEditingText: Bool {
        urlField.isFirstResponder
    }
    
    override var canBecomeFirstResponder: Bool {
        urlField.canBecomeFirstResponder
    }
    
    @discardableResult
    override func becomeFirstResponder() -> Bool {
        urlField.becomeFirstResponder()
    }
    
    @discardableResult
    override func resignFirstResponder() -> Bool {
        urlField.resignFirstResponder()
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        layer.shadowPath = shadowEnabled ? UIBezierPath(roundedRect: bounds, cornerRadius: 16).cgPath : nil
    }
    
    private func setupView() {
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleBarTap))
        tapGesture.cancelsTouchesInView = true
        tapGesture.delegate = self
        addGestureRecognizer(tapGesture)
        
        addSubview(backgroundFillView)
        backgroundFillView.addSubview(leadingButton)
        backgroundFillView.addSubview(trailingButton)
        backgroundFillView.addSubview(urlField)
        backgroundFillView.addSubview(overlayButton)
        backgroundFillView.addSubview(displayLabel)
        backgroundFillView.addSubview(autocompleteLabel)
        backgroundFillView.addSubview(progressView)
        
        NSLayoutConstraint.activate([
            backgroundFillView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundFillView.trailingAnchor.constraint(equalTo: trailingAnchor),
            backgroundFillView.topAnchor.constraint(equalTo: topAnchor),
            backgroundFillView.bottomAnchor.constraint(equalTo: bottomAnchor),
            
            leadingButton.leadingAnchor.constraint(equalTo: backgroundFillView.leadingAnchor, constant: 12),
            leadingButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            leadingButton.widthAnchor.constraint(equalToConstant: 18),
            leadingButton.heightAnchor.constraint(equalToConstant: 18),
            
            trailingButton.trailingAnchor.constraint(equalTo: backgroundFillView.trailingAnchor, constant: -12),
            trailingButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            trailingButton.widthAnchor.constraint(equalToConstant: 18),
            trailingButton.heightAnchor.constraint(equalToConstant: 18),
            
            urlField.topAnchor.constraint(equalTo: backgroundFillView.topAnchor),
            urlField.bottomAnchor.constraint(equalTo: backgroundFillView.bottomAnchor),
            
            overlayButton.leadingAnchor.constraint(equalTo: urlField.leadingAnchor),
            overlayButton.trailingAnchor.constraint(equalTo: urlField.trailingAnchor, constant: -30),
            overlayButton.topAnchor.constraint(equalTo: urlField.topAnchor),
            overlayButton.bottomAnchor.constraint(equalTo: urlField.bottomAnchor),
            
            autocompleteLabel.leadingAnchor.constraint(equalTo: urlField.leadingAnchor),
            autocompleteLabel.trailingAnchor.constraint(equalTo: urlField.trailingAnchor, constant: -30),
            autocompleteLabel.topAnchor.constraint(equalTo: urlField.topAnchor),
            autocompleteLabel.bottomAnchor.constraint(equalTo: urlField.bottomAnchor),
            
            displayLabel.topAnchor.constraint(equalTo: backgroundFillView.topAnchor),
            displayLabel.bottomAnchor.constraint(equalTo: backgroundFillView.bottomAnchor),
            
            progressView.leadingAnchor.constraint(equalTo: backgroundFillView.leadingAnchor),
            progressView.trailingAnchor.constraint(equalTo: backgroundFillView.trailingAnchor),
            progressView.bottomAnchor.constraint(equalTo: backgroundFillView.bottomAnchor),
            progressView.heightAnchor.constraint(equalToConstant: 2),
        ])
        
        urlFieldLeadingToIconConstraint = urlField.leadingAnchor.constraint(equalTo: leadingButton.trailingAnchor, constant: 8)
        urlFieldLeadingToBarConstraint = urlField.leadingAnchor.constraint(equalTo: backgroundFillView.leadingAnchor, constant: 12)
        urlFieldTrailingToButtonConstraint = urlField.trailingAnchor.constraint(equalTo: trailingButton.leadingAnchor, constant: -8)
        urlFieldTrailingToBarConstraint = urlField.trailingAnchor.constraint(equalTo: backgroundFillView.trailingAnchor, constant: -12)
        displayLabelLeadingToIconConstraint = displayLabel.leadingAnchor.constraint(equalTo: leadingButton.trailingAnchor, constant: 8)
        displayLabelLeadingToBarConstraint = displayLabel.leadingAnchor.constraint(equalTo: backgroundFillView.leadingAnchor, constant: 12)
        displayLabelTrailingToButtonConstraint = displayLabel.trailingAnchor.constraint(equalTo: trailingButton.leadingAnchor, constant: -8)
        displayLabelTrailingToBarConstraint = displayLabel.trailingAnchor.constraint(equalTo: backgroundFillView.trailingAnchor, constant: -12)
        urlFieldLeadingToBarConstraint.isActive = true
        urlFieldTrailingToBarConstraint.isActive = true
        displayLabelLeadingToBarConstraint.isActive = true
        displayLabelTrailingToBarConstraint.isActive = true
        
        trailingButton.addTarget(self, action: #selector(handleTrailingButtonTap), for: .touchUpInside)
        overlayButton.addTarget(self, action: #selector(handleOverlayButtonTap), for: .touchUpInside)
        
        updateDisplayState()
    }
    
    private func updateDisplayState() {
        let isEditing = urlField.isFirstResponder
        let usesComposingAppearance = isEditing || forceComposingAppearanceWhenUnfocused
        let hasCommittedText = !(currentText?.isEmpty ?? true)
        let hasTypedText = !(urlField.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let isPlaceholderMode = usesComposingAppearance ? !hasTypedText : !hasCommittedText
        let leadingButtonVisible = !usesComposingAppearance && !(hidePlaceholderIcon && isPlaceholderMode)
        let trailingButtonVisible = !usesComposingAppearance && (hasCommittedText || isLoading)
        let leadingButtonShowsSearchIcon = !hidePlaceholderIcon && !usesComposingAppearance && isPlaceholderMode
        let leadingButtonShowsMenu = canShowBarMenu && !usesComposingAppearance
        let displayText = displayAttributedText()
        
        updateTextVisibility(
            usesComposingAppearance: usesComposingAppearance,
            hasCommittedText: hasCommittedText,
            displayText: displayText
        )
        updateLeadingButton(
            leadingButtonVisible: leadingButtonVisible,
            leadingButtonShowsSearchIcon: leadingButtonShowsSearchIcon,
            leadingButtonShowsMenu: leadingButtonShowsMenu
        )
        updateTrailingButton(trailingButtonVisible: trailingButtonVisible, isLoading: isLoading)
        
        NSLayoutConstraint.deactivate([
            urlFieldLeadingToIconConstraint,
            urlFieldLeadingToBarConstraint,
            urlFieldTrailingToButtonConstraint,
            urlFieldTrailingToBarConstraint,
            displayLabelLeadingToIconConstraint,
            displayLabelLeadingToBarConstraint,
            displayLabelTrailingToButtonConstraint,
            displayLabelTrailingToBarConstraint,
        ])
        
        NSLayoutConstraint.activate([
            leadingButtonVisible ? urlFieldLeadingToIconConstraint : urlFieldLeadingToBarConstraint,
            trailingButtonVisible ? urlFieldTrailingToButtonConstraint : urlFieldTrailingToBarConstraint,
            leadingButtonVisible ? displayLabelLeadingToIconConstraint : displayLabelLeadingToBarConstraint,
            trailingButtonVisible ? displayLabelTrailingToButtonConstraint : displayLabelTrailingToBarConstraint,
        ])
    }
    
    private func updateTextVisibility(usesComposingAppearance: Bool, hasCommittedText: Bool, displayText: NSAttributedString?) {
        if usesComposingAppearance {
            displayLabel.isHidden = true
            urlField.isHidden = false
        } else {
            displayLabel.attributedText = displayText
            displayLabel.isHidden = displayText == nil
            urlField.isHidden = hasCommittedText
        }
        urlField.textAlignment = .left
    }
    
    private func updateLeadingButton(
        leadingButtonVisible: Bool,
        leadingButtonShowsSearchIcon: Bool,
        leadingButtonShowsMenu: Bool
    ) {
        guard leadingButtonVisible else {
            leadingButton.isHidden = true
            leadingButton.setImage(nil, for: .normal)
            leadingButton.setMenuPreservingPresentation(nil)
            leadingButton.isUserInteractionEnabled = false
            return
        }
        
        leadingButton.isHidden = false
        if leadingButtonShowsSearchIcon {
            leadingButton.tintColor = .secondaryLabel
            leadingButton.setImage(symbolImage(primary: "magnifyingglass", fallback: "magnifyingglass.circle"), for: .normal)
            leadingButton.setMenuPreservingPresentation(nil)
            leadingButton.isUserInteractionEnabled = false
            return
        }
        
        leadingButton.tintColor = leadingButtonShowsMenu ? .label : .secondaryLabel
        leadingButton.setImage(symbolImage(primary: "list.bullet.below.rectangle", fallback: "line.horizontal.3"), for: .normal)
        leadingButton.setMenuPreservingPresentation(leadingButtonShowsMenu ? addonsMenu : nil)
        leadingButton.isUserInteractionEnabled = leadingButtonShowsMenu && addonsMenu != nil
    }
    
    private func updateTrailingButton(trailingButtonVisible: Bool, isLoading: Bool) {
        trailingButton.isHidden = !trailingButtonVisible
        trailingButton.isUserInteractionEnabled = trailingButtonVisible
        guard trailingButtonVisible else {
            return
        }
        trailingButton.setImage(UIImage(systemName: isLoading ? "xmark" : "arrow.clockwise"), for: .normal)
    }
    
    private func displayAttributedText() -> NSAttributedString? {
        guard let currentText, !currentText.isEmpty else {
            return nil
        }
        
        guard canShowBarMenu,
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
    private func handleBarTap() {
        if urlField.isFirstResponder {
            if isShowingOverlay {
                handleOverlayTap()
            }
            return
        }
        
        urlField.becomeFirstResponder()
    }
    
    @objc
    private func textFieldDidChange() {
        let previousText = lastEditingText
        showsFocusPreview = false
        clearAutocomplete()
        let currentText = urlField.text ?? ""
        lastEditingText = currentText
        delegate?.addressBar(self, didChangeText: currentText, previousText: previousText, isDelete: lastEditWasDelete)
        lastEditWasDelete = false
        if urlField.isFirstResponder {
            updateDisplayState()
        }
    }
    
    @objc
    private func handleTrailingButtonTap() {
        delegate?.addressBarDidTapTrailingButton(self)
    }
    
    @objc
    private func handleOverlayButtonTap() {
        handleOverlayTap()
    }
    
    private func handleOverlayTap() {
        if !urlField.isFirstResponder {
            _ = urlField.becomeFirstResponder()
        }
        
        if isShowingAutocomplete {
            commitAutocompleteForEditing()
            return
        }
        
        if showsFocusPreview {
            clearFocusPreview()
            selectAllText()
        }
    }
    
    private func symbolImage(primary: String, fallback: String) -> UIImage? {
        if let image = UIImage(systemName: primary) {
            return image
        }
        return UIImage(systemName: fallback)
    }
    
    private func commitAutocompleteForEditing() {
        let committedText = autocompleteCommittedText ?? autocompleteSubmissionText ?? urlField.text ?? ""
        clearAutocomplete()
        urlField.text = committedText
        lastEditingText = committedText
        restoreCaretToEnd()
    }
    
    private func showFocusPreview() {
        guard let text = urlField.text?.trimmingCharacters(in: .whitespacesAndNewlines),
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
        showsFocusPreview = true
        updateOverlayState()
    }
    
    private func clearFocusPreview() {
        showsFocusPreview = false
        if !isShowingAutocomplete {
            autocompleteLabel.attributedText = nil
            autocompleteLabel.isHidden = true
        }
        updateOverlayState()
    }
    
    private func updateOverlayState() {
        urlField.isAutocompleteActive = isShowingOverlay
        urlField.textColor = isShowingOverlay ? .clear : .label
        urlField.tintColor = isShowingOverlay ? .clear : tintColor
        overlayButton.isHidden = !isShowingOverlay
    }
    
    private func restoreCaretToEnd() {
        let end = urlField.endOfDocument
        urlField.selectedTextRange = urlField.textRange(from: end, to: end)
    }
    
    private func selectAllText() {
        let start = urlField.beginningOfDocument
        let end = urlField.endOfDocument
        urlField.selectedTextRange = urlField.textRange(from: start, to: end)
    }
}

extension AddressBar: UITextFieldDelegate {
    func textField(
        _ textField: UITextField,
        shouldChangeCharactersIn range: NSRange,
        replacementString string: String
    ) -> Bool {
        if showsFocusPreview {
            clearFocusPreview()
            let previousText = lastEditingText
            if string.isEmpty {
                urlField.text = ""
                lastEditWasDelete = true
            } else {
                urlField.text = string
                lastEditWasDelete = false
            }
            let currentText = urlField.text ?? ""
            lastEditingText = currentText
            delegate?.addressBar(self, didChangeText: currentText, previousText: previousText, isDelete: lastEditWasDelete)
            lastEditWasDelete = false
            if urlField.isFirstResponder {
                updateDisplayState()
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
        let searchText = autocompleteSubmissionText ?? textField.text?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let searchText, !searchText.isEmpty else {
            return false
        }
        
        delegate?.addressBarDidSubmit(searchText)
        return true
    }
    
    func textFieldDidBeginEditing(_ textField: UITextField) {
        if let currentText,
           !currentText.isEmpty {
            textField.text = currentText
        }
        lastEditingText = textField.text ?? ""
        let preservesAutocomplete = preservesAutocompleteWhenUnfocused && isShowingAutocomplete
        preservesAutocompleteWhenUnfocused = false
        if !preservesAutocomplete {
            clearAutocomplete()
        } else {
            updateOverlayState()
        }
        updateDisplayState()
        delegate?.addressBarDidBeginEditing(self)
        if !preservesAutocomplete {
            showFocusPreview()
        }
    }
    
    func textFieldDidEndEditing(_ textField: UITextField) {
        showsFocusPreview = false
        if !preservesAutocompleteWhenUnfocused {
            clearAutocomplete()
        } else {
            updateOverlayState()
        }
        currentText = textField.text?.trimmingCharacters(in: .whitespacesAndNewlines)
        currentLocationText = nil
        currentLocationTitle = nil
        canShowBarMenu = false
        updateDisplayState()
        delegate?.addressBarDidEndEditing(self)
    }
}

extension AddressBar: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if touch.view?.isDescendant(of: leadingButton) == true {
            return false
        }
        
        if touch.view?.isDescendant(of: trailingButton) == true {
            return false
        }
        
        if touch.view?.isDescendant(of: urlField) == true {
            return false
        }
        
        return true
    }
}

enum AddressBarPosition: String {
    case bottom
    case top
}
