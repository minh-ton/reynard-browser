//
//  AddonPopupViewController.swift
//  Reynard
//
//  Created by Minh Ton on 17/6/26.
//

import GeckoView
import UIKit

final class AddonPopupViewController: UIViewController, ContentDelegate, NavigationDelegate {
    private enum UX {
        static let maxSheetWidth: CGFloat = 430
        static let mediumHeightMultiplier: CGFloat = 0.7
        static let sheetCornerRadius: CGFloat = 16
        static let closeButtonTopInset: CGFloat = 8
        static let closeButtonTrailingInset: CGFloat = 12
        static let closeButtonSize: CGFloat = 30
        static let geckoViewTopSpacing: CGFloat = 8
        static let shadowOpacity: Float = 0.18
        static let shadowRadius: CGFloat = 12
        static let shadowOffset = CGSize(width: 0, height: -4)
        static let borderWidth: CGFloat = 0.5
    }
    
    private let url: String
    private let sessionManager: SessionManager
    private let openInNewTab: (String) -> Void
    private let createSession: (String, String) -> GeckoSession?
    private let didDismiss: () -> Void
    private let geckoView = GeckoView()
    private let session: GeckoSession
    private var hasClosedSession = false
    
    // MARK: - Lifecycle
    
    init(
        url: String,
        sessionManager: SessionManager,
        openInNewTab: @escaping (String) -> Void,
        createSession: @escaping (String, String) -> GeckoSession?,
        didDismiss: @escaping () -> Void
    ) {
        self.url = url
        self.sessionManager = sessionManager
        self.openInNewTab = openInNewTab
        self.createSession = createSession
        self.didDismiss = didDismiss
        session = sessionManager.createSession(
            url: url,
            tabID: nil,
            isPrivate: false,
            isAddonPopup: true,
            opening: .manual,
            delegates: SessionDelegates()
        )
        super.init(nibName: nil, bundle: nil)
        configureSession()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        closeSessionIfNeeded()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        configureView()
        loadPopup()
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard isBeingDismissed || isMovingFromParent || navigationController?.isBeingDismissed == true else {
            return
        }
        
        closeSessionIfNeeded()
        didDismiss()
    }
    
    // MARK: - Setup
    
    private func configureSession() {
        sessionManager.bindDelegates(
            to: session,
            delegates: SessionDelegates(content: self, navigation: self)
        )
        sessionManager.open(session)
    }
    
    private func configureView() {
        view.backgroundColor = .clear
        
        let containerView = makeContainerView()
        let sheetView = makeSheetView()
        let closeButton = makeCloseButton()
        
        view.addSubview(containerView)
        containerView.addSubview(sheetView)
        sheetView.addSubview(closeButton)
        sheetView.addSubview(geckoView)
        
        constrainContainerView(containerView)
        constrainSheetView(sheetView, in: containerView)
        constrainCloseButton(closeButton, in: sheetView)
        constrainGeckoView(in: sheetView, below: closeButton)
    }
    
    private func loadPopup() {
        geckoView.session = session
        sessionManager.activate(session)
        session.load(url)
    }
    
    // MARK: - View Construction
    
    private func makeContainerView() -> UIView {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .clear
        view.layer.cornerRadius = UX.sheetCornerRadius
        view.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = UX.shadowOpacity
        view.layer.shadowRadius = UX.shadowRadius
        view.layer.shadowOffset = UX.shadowOffset
        view.layer.borderWidth = UX.borderWidth
        view.layer.borderColor = UIColor.separator.cgColor
        return view
    }
    
    private func makeSheetView() -> UIView {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .systemBackground
        view.layer.cornerRadius = UX.sheetCornerRadius
        view.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        view.clipsToBounds = true
        return view
    }
    
    private func makeCloseButton() -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(UIImage(named: "reynard.xmark"), for: .normal)
        button.tintColor = .label
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        return button
    }
    
    // MARK: - Constraints
    
    private func constrainContainerView(_ containerView: UIView) {
        NSLayoutConstraint.activate([
            containerView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            containerView.widthAnchor.constraint(lessThanOrEqualToConstant: UX.maxSheetWidth),
            containerView.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor),
            containerView.widthAnchor.constraint(equalTo: view.widthAnchor).withPriority(.defaultLow),
            containerView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        
        let mediumHeight = containerView.heightAnchor.constraint(
            equalTo: view.heightAnchor,
            multiplier: UX.mediumHeightMultiplier
        )
        let largeHeight = containerView.heightAnchor.constraint(equalTo: view.heightAnchor)
        
        if traitCollection.horizontalSizeClass == .compact && traitCollection.verticalSizeClass == .compact {
            largeHeight.isActive = true
        } else {
            mediumHeight.isActive = true
        }
    }
    
    private func constrainSheetView(_ sheetView: UIView, in containerView: UIView) {
        NSLayoutConstraint.activate([
            sheetView.topAnchor.constraint(equalTo: containerView.topAnchor),
            sheetView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            sheetView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            sheetView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
    }
    
    private func constrainCloseButton(_ closeButton: UIButton, in sheetView: UIView) {
        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: sheetView.safeAreaLayoutGuide.topAnchor, constant: UX.closeButtonTopInset),
            closeButton.trailingAnchor.constraint(equalTo: sheetView.safeAreaLayoutGuide.trailingAnchor, constant: -UX.closeButtonTrailingInset),
            closeButton.heightAnchor.constraint(equalToConstant: UX.closeButtonSize),
            closeButton.widthAnchor.constraint(equalToConstant: UX.closeButtonSize)
        ])
    }
    
    private func constrainGeckoView(in sheetView: UIView, below closeButton: UIButton) {
        geckoView.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            geckoView.topAnchor.constraint(equalTo: closeButton.bottomAnchor, constant: UX.geckoViewTopSpacing),
            geckoView.leadingAnchor.constraint(equalTo: sheetView.leadingAnchor),
            geckoView.trailingAnchor.constraint(equalTo: sheetView.trailingAnchor),
            geckoView.bottomAnchor.constraint(equalTo: sheetView.bottomAnchor)
        ])
    }
    
    // MARK: - Actions & Delegates
    
    @objc private func closeTapped() {
        onCloseRequest(session: session)
    }
    
    func onCloseRequest(session: GeckoSession) {
        closeSessionIfNeeded()
        if let navigationController {
            navigationController.popViewController(animated: true)
        } else {
            dismiss(animated: true)
        }
    }
    
    func onLoadRequest(session: GeckoSession, request: LoadRequest) async -> AllowOrDeny {
        guard request.target == .new else {
            return .allow
        }
        
        openInNewTab(request.uri)
        return .deny
    }
    
    func onNewSession(session: GeckoSession, uri: String, windowId: String) async -> GeckoSession? {
        return createSession(uri, windowId)
    }
    
    private func closeSessionIfNeeded() {
        guard !hasClosedSession else {
            return
        }
        
        hasClosedSession = true
        geckoView.session = nil
        sessionManager.close(session)
    }
}
