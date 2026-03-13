import AppKit
import Foundation
import WebKit

@MainActor
final class TabRuntimeRegistry {
    typealias NavigationCallback = (_ tabID: UUID, _ title: String?, _ url: URL?) -> Void
    var onOpenNewTabRequest: ((URL) -> Void)?
    var onLoadingChange: ((UUID, Bool) -> Void)?
    var onProgressChange: ((UUID, Double) -> Void)?
    var onDownloadStarted: ((WKDownload) -> Void)?
    var onDialogRequest: ((JSDialogRequest) -> Void)?
    /// Set once after async compilation; applied to all subsequently created webviews.
    var contentRuleList: WKContentRuleList?

    private var webViews: [UUID: WKWebView] = [:]
    private var delegateRelays: [UUID: WebViewNavigationRelay] = [:]
    func webView(for tab: TabState, callback: @escaping NavigationCallback) -> WKWebView {
        if let webView = webViews[tab.id] {
            delegateRelays[tab.id]?.updateCallback(callback)
            return webView
        }

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = tab.isPrivate ? .nonPersistent() : .default()
        if let rules = contentRuleList, BrowserSettings.shared.contentBlockingEnabled {
            configuration.userContentController.add(rules)
        }
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.defaultWebpagePreferences.preferredContentMode = .desktop
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        configuration.preferences.isTextInteractionEnabled = true
        configuration.preferences.setValue(
            BrowserSettings.shared.developerExtrasEnabled,
            forKey: "developerExtrasEnabled"
        )

        // Use the system WebKit/Safari user agent without additional spoofing.
        // This avoids mismatches between reported capabilities and the actual
        // engine, which can cause Google sign-in and passkeys to misbehave.
        let webView = ContextMenuWebView(frame: .zero, configuration: configuration)
        let relay = WebViewNavigationRelay(
            tabID: tab.id,
            callback: callback,
            onOpenNewTabRequest: onOpenNewTabRequest,
            onLoadingChange: onLoadingChange,
            onProgressChange: onProgressChange,
            onDownloadStarted: onDownloadStarted,
            onDialogRequest: onDialogRequest
        )
        webView.navigationDelegate = relay
        webView.uiDelegate = relay
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        webView.setValue(false, forKey: "drawsBackground")
        if #available(macOS 13.3, *) {
            webView.isInspectable = true
        }

        relay.startObservingProgress(webView)
        delegateRelays[tab.id] = relay
        webViews[tab.id] = webView

        if let url = tab.resolvedURL {
            webView.load(URLRequest(url: url))
        }

        return webView
    }

    func existingWebView(for tabID: UUID) -> WKWebView? {
        webViews[tabID]
    }

    func load(_ input: String, in tab: TabState) {
        let webView = webView(for: tab, callback: { _, _, _ in })
        if let url = TabState(urlString: input).resolvedURL {
            webView.load(URLRequest(url: url))
        }
    }

    func discardWebView(for tabID: UUID) {
        webViews[tabID]?.stopLoading()
        webViews[tabID]?.navigationDelegate = nil
        webViews[tabID]?.uiDelegate = nil
        webViews[tabID] = nil
        delegateRelays[tabID] = nil
    }

    func discardAll(except keepIDs: Set<UUID>) {
        let discardIDs = Set(webViews.keys).subtracting(keepIDs)
        for id in discardIDs {
            discardWebView(for: id)
        }
    }

    func goBack(tabID: UUID) {
        webViews[tabID]?.goBack()
    }

    func goForward(tabID: UUID) {
        webViews[tabID]?.goForward()
    }

    func reload(tabID: UUID) {
        webViews[tabID]?.reload()
    }

    // MARK: - Zoom

    private static let zoomSteps = [0.5, 0.67, 0.75, 0.8, 0.9, 1.0, 1.1, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0]

    func zoomLevel(for tabID: UUID) -> Double {
        Double(webViews[tabID]?.pageZoom ?? 1.0)
    }

    func setZoom(_ level: Double, for tabID: UUID) {
        webViews[tabID]?.pageZoom = level
    }

    func zoomIn(tabID: UUID) -> Double {
        let cur = zoomLevel(for: tabID)
        let next = Self.zoomSteps.first { $0 > cur + 0.001 } ?? Self.zoomSteps.last!
        setZoom(next, for: tabID)
        return next
    }

    func zoomOut(tabID: UUID) -> Double {
        let cur = zoomLevel(for: tabID)
        let prev = Self.zoomSteps.last { $0 < cur - 0.001 } ?? Self.zoomSteps.first!
        setZoom(prev, for: tabID)
        return prev
    }

    func resetZoom(tabID: UUID) -> Double {
        setZoom(1.0, for: tabID)
        return 1.0
    }

    // MARK: - Find in page

    func findNext(_ query: String, in tabID: UUID, completion: @escaping (Bool) -> Void) {
        guard let wv = webViews[tabID], !query.isEmpty else { completion(false); return }
        let cfg = WKFindConfiguration()
        cfg.backwards = false
        cfg.caseSensitive = false
        cfg.wraps = true
        wv.find(query, configuration: cfg) { result in completion(result.matchFound) }
    }

    func findPrev(_ query: String, in tabID: UUID, completion: @escaping (Bool) -> Void) {
        guard let wv = webViews[tabID], !query.isEmpty else { completion(false); return }
        let cfg = WKFindConfiguration()
        cfg.backwards = true
        cfg.caseSensitive = false
        cfg.wraps = true
        wv.find(query, configuration: cfg) { result in completion(result.matchFound) }
    }

    func clearFind(in tabID: UUID) {
        webViews[tabID]?.find("", configuration: WKFindConfiguration()) { _ in }
    }

    // MARK: - Reader mode

    func activateReaderMode(tabID: UUID) {
        guard let wv = webViews[tabID] else { return }
        ReaderMode.activate(in: wv)
    }

    func deactivateReaderMode(tabID: UUID) {
        guard let wv = webViews[tabID] else { return }
        ReaderMode.deactivate(in: wv)
    }

    func checkReaderModeAvailable(tabID: UUID, completion: @escaping (Bool) -> Void) {
        guard let wv = webViews[tabID] else { completion(false); return }
        ReaderMode.checkAvailable(in: wv, completion: completion)
    }
}

final class WebViewNavigationRelay: NSObject, WKNavigationDelegate {
    private let tabID: UUID
    private var callback: TabRuntimeRegistry.NavigationCallback
    private let onOpenNewTabRequest: ((URL) -> Void)?
    private let onLoadingChange: ((UUID, Bool) -> Void)?
    private let onProgressChange: ((UUID, Double) -> Void)?
    private let onDownloadStarted: ((WKDownload) -> Void)?
    private let onDialogRequest: ((JSDialogRequest) -> Void)?
    private var progressObservation: NSKeyValueObservation?

    init(
        tabID: UUID,
        callback: @escaping TabRuntimeRegistry.NavigationCallback,
        onOpenNewTabRequest: ((URL) -> Void)?,
        onLoadingChange: ((UUID, Bool) -> Void)?,
        onProgressChange: ((UUID, Double) -> Void)?,
        onDownloadStarted: ((WKDownload) -> Void)?,
        onDialogRequest: ((JSDialogRequest) -> Void)?
    ) {
        self.tabID = tabID
        self.callback = callback
        self.onOpenNewTabRequest = onOpenNewTabRequest
        self.onLoadingChange = onLoadingChange
        self.onProgressChange = onProgressChange
        self.onDownloadStarted = onDownloadStarted
        self.onDialogRequest = onDialogRequest
        super.init()
    }

    func updateCallback(_ callback: @escaping TabRuntimeRegistry.NavigationCallback) {
        self.callback = callback
    }

    func startObservingProgress(_ webView: WKWebView) {
        progressObservation = webView.observe(\.estimatedProgress, options: .new) { [weak self] wv, _ in
            guard let self else { return }
            self.onProgressChange?(self.tabID, wv.estimatedProgress)
        }
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        onLoadingChange?(tabID, true)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        onLoadingChange?(tabID, false)
        callback(tabID, webView.title, webView.url)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        onLoadingChange?(tabID, false)
        callback(tabID, webView.title, webView.url)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        onLoadingChange?(tabID, false)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        callback(tabID, webView.title, webView.url)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        if let url = navigationAction.request.url {
            logGoogleSignInContext(webView, url: url)
        }
        // "Download Image", "Download Linked File", etc. set this flag.
        // Returning .download causes WebKit to call navigationAction:didBecome:download:
        if navigationAction.shouldPerformDownload {
            print("[DL] shouldPerformDownload=true → .download for \(navigationAction.request.url?.absoluteString ?? "nil")")
            decisionHandler(.download)
            return
        }

        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }

        if let scheme = url.scheme?.lowercased(),
           !["http", "https", "file", "about", "data", "blob"].contains(scheme) {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
            return
        }

        decisionHandler(.allow)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
        // Server-signalled attachment download
        if let http = navigationResponse.response as? HTTPURLResponse,
           let disposition = http.value(forHTTPHeaderField: "Content-Disposition"),
           disposition.lowercased().hasPrefix("attachment") {
            decisionHandler(.download)
            return
        }

        // MIME type WebKit can't render (ZIP, executables, etc.)
        if navigationResponse.canShowMIMEType {
            decisionHandler(.allow)
        } else {
            decisionHandler(.download)
        }
    }

    func webView(
        _ webView: WKWebView,
        navigationAction: WKNavigationAction,
        didBecome download: WKDownload
    ) {
        print("[DL] navigationAction:didBecome:download fired, handing to coordinator")
        onDownloadStarted?(download)
    }

    func webView(
        _ webView: WKWebView,
        navigationResponse: WKNavigationResponse,
        didBecome download: WKDownload
    ) {
        print("[DL] navigationResponse:didBecome:download fired, handing to coordinator")
        onDownloadStarted?(download)
    }
}

// MARK: - Diagnostics

private extension WebViewNavigationRelay {
    func logGoogleSignInContext(_ webView: WKWebView, url: URL) {
        guard let host = url.host,
              host.contains("google.com") else { return }
#if DEBUG
        let ua = webView.value(forKey: "userAgent") as? String
            ?? webView.customUserAgent
            ?? "<unknown>"
        print("[GoogleSignIn] host=\(host) ua=\(ua) contentBlocking=\(BrowserSettings.shared.contentBlockingEnabled)")
#endif
    }
}

extension WebViewNavigationRelay: WKUIDelegate {
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard let requestURL = navigationAction.request.url else { return nil }

        // "Download Image" piggy-backs on "Open Image in New Window" to get the URL.
        if let contextView = webView as? ContextMenuWebView,
           contextView.pendingDownloadAction == .image {
            contextView.pendingDownloadAction = nil
            print("[DL] Intercepted Download Image for \(requestURL)")
            webView.startDownload(using: URLRequest(url: requestURL)) { [weak self] download in
                print("[DL] startDownload completion, handing to coordinator")
                self?.onDownloadStarted?(download)
            }
            return nil
        }

        guard navigationAction.targetFrame == nil else { return nil }
        onOpenNewTabRequest?(requestURL)
        return nil
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping () -> Void
    ) {
        let source = frame.request.url?.host ?? "JavaScript"
        onDialogRequest?(JSDialogRequest(
            message: message,
            source: source,
            kind: .alert(completion: completionHandler)
        ))
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (Bool) -> Void
    ) {
        let source = frame.request.url?.host ?? "JavaScript"
        onDialogRequest?(JSDialogRequest(
            message: message,
            source: source,
            kind: .confirm(completion: completionHandler)
        ))
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (String?) -> Void
    ) {
        let source = frame.request.url?.host ?? "JavaScript"
        onDialogRequest?(JSDialogRequest(
            message: prompt,
            source: source,
            kind: .prompt(defaultText: defaultText, completion: completionHandler)
        ))
    }
}

