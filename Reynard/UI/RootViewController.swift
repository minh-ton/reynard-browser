//
//  RootViewController.swift
//  Reynard
//
//  Created by Minh Ton on 22/2/26.
//

import GeckoWrapper
import UIKit

final class RootViewController: UIViewController {
    private lazy var topBar: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .systemBackground
        return view
    }()

    private lazy var bottomBar: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .systemBackground
        return view
    }()

    private lazy var toolBar: ToolBar = {
        let view = ToolBar()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var searchBar: SearchBar = {
        let view = SearchBar()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var progress: UIProgressView = {
        let view = UIProgressView(progressViewStyle: .default)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var geckoView: GeckoView = {
        let view = GeckoView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var isURLLenient: NSRegularExpression = {
        let pattern = "^\\s*(\\w+-+)*[\\w\\[]+(://[/]*|:|\\.)(\\w+-+)*[\\w\\[:]+([\\S&&[^\\w-]]\\S*)?\\s*$"
        return try! NSRegularExpression(pattern: pattern)
    }()

    private var homepage = ""

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .white

        configureSearchBar()
        configureToolBar()
        configureProgress()
        configureBrowserView()

        let session = GeckoSession()
        session.contentDelegate = self
        session.progressDelegate = self
        session.navigationDelegate = self
        session.open()

        geckoView.session = session

        if let testURL = ProcessInfo.processInfo.environment["MOZ_TEST_URL"] {
            browse(to: testURL)
        } else if !homepage.isEmpty {
            browse(to: homepage)
        }
    }

    private func configureBrowserView() {
        view.addSubview(geckoView)

        NSLayoutConstraint.activate([
            geckoView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            geckoView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            geckoView.topAnchor.constraint(equalTo: progress.bottomAnchor),
            geckoView.bottomAnchor.constraint(equalTo: bottomBar.topAnchor),
        ])
    }

    private func configureProgress() {
        view.addSubview(progress)

        NSLayoutConstraint.activate([
            progress.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            progress.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            progress.topAnchor.constraint(equalTo: topBar.bottomAnchor),
            progress.heightAnchor.constraint(equalToConstant: 3),
        ])

        progress.progressTintColor = .orange
        progress.isHidden = true
    }

    private func configureSearchBar() {
        view.addSubview(topBar)
        topBar.addSubview(searchBar)

        NSLayoutConstraint.activate([
            topBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            topBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            topBar.heightAnchor.constraint(equalToConstant: 48),

            searchBar.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            searchBar.leadingAnchor.constraint(equalTo: topBar.leadingAnchor, constant: 12),
            searchBar.trailingAnchor.constraint(equalTo: topBar.trailingAnchor, constant: -12),
            searchBar.heightAnchor.constraint(equalToConstant: 36),
        ])

        searchBar.configure(browserDelegate: self)
    }

    private func configureToolBar() {
        view.addSubview(bottomBar)
        bottomBar.addSubview(toolBar)

        NSLayoutConstraint.activate([
            bottomBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            bottomBar.heightAnchor.constraint(equalToConstant: 50),

            toolBar.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor, constant: 24),
            toolBar.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor, constant: -24),
            toolBar.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),
            toolBar.heightAnchor.constraint(equalToConstant: 30),
        ])

        toolBar.toolbarDelegate = self
    }

    private func browse(to term: String) {
        searchBar.resignFirstResponder()

        let trimmedValue = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else {
            return
        }

        let fullRange = NSRange(location: 0, length: (term as NSString).length)
        let isURL = isURLLenient.firstMatch(in: term, range: fullRange) != nil

        if isURL {
            geckoView.session?.load(term)
            return
        }

        let encodedValue = trimmedValue.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        geckoView.session?.load("https://www.google.com/search?q=\(encodedValue)")
    }
}

extension RootViewController: ToolBarDelegate {
    func backButtonClicked() {
        geckoView.session?.goBack()
    }

    func forwardButtonClicked() {
        geckoView.session?.goForward()
    }

    func reloadButtonClicked() {
        geckoView.session?.reload()
    }

    func stopButtonClicked() {
        geckoView.session?.stop()
    }
}

extension RootViewController: SearchBarDelegate {
    func openBrowser(searchTerm: String) {
        guard let searchText = searchBar.getSearchBarText(), !searchText.isEmpty else {
            return
        }
        browse(to: searchText)
    }
}

extension RootViewController: ContentDelegate {
    func onTitleChange(session: GeckoSession, title: String) {}

    func onPreviewImage(session: GeckoSession, previewImageUrl: String) {}

    func onFocusRequest(session: GeckoSession) {}

    func onCloseRequest(session: GeckoSession) {
        session.close()
        geckoView.session = nil
    }

    func onFullScreen(session: GeckoSession, fullScreen: Bool) {}

    func onMetaViewportFitChange(session: GeckoSession, viewportFit: String) {}

    func onProductUrl(session: GeckoSession) {}

    func onContextMenu(session: GeckoSession, screenX: Int, screenY: Int, element: ContextElement) {}

    func onCrash(session: GeckoSession) {}

    func onKill(session: GeckoSession) {}

    func onFirstComposite(session: GeckoSession) {}

    func onFirstContentfulPaint(session: GeckoSession) {}

    func onPaintStatusReset(session: GeckoSession) {}

    func onWebAppManifest(session: GeckoSession, manifest: Any) {}

    func onSlowScript(session: GeckoSession, scriptFileName: String) async -> SlowScriptResponse {
        .halt
    }

    func onShowDynamicToolbar(session: GeckoSession) {}

    func onCookieBannerDetected(session: GeckoSession) {}

    func onCookieBannerHandled(session: GeckoSession) {}
}

extension RootViewController: NavigationDelegate {
    func onLocationChange(session: GeckoSession, url: String?, permissions: [ContentPermission]) {}

    func onCanGoBack(session: GeckoSession, canGoBack: Bool) {
        toolBar.updateBackButton(canGoBack: canGoBack)
    }

    func onCanGoForward(session: GeckoSession, canGoForward: Bool) {
        toolBar.updateForwardButton(canGoForward: canGoForward)
    }

    func onLoadRequest(session: GeckoSession, request: LoadRequest) async -> AllowOrDeny {
        .allow
    }

    func onSubframeLoadRequest(session: GeckoSession, request: LoadRequest) async -> AllowOrDeny {
        .allow
    }

    func onNewSession(session: GeckoSession, uri: String) async -> GeckoSession? {
        nil
    }
}

extension RootViewController: ProgressDelegate {
    func onPageStart(session: GeckoSession, url: String) {
        progress.isHidden = false
        toolBar.updateReloadStopButton(isLoading: true)
    }

    func onPageStop(session: GeckoSession, success: Bool) {
        toolBar.updateReloadStopButton(isLoading: false)
        progress.isHidden = true
    }

    func onProgressChange(session: GeckoSession, progress: Int) {
        self.progress.progress = Float(progress) / 100
    }
}
