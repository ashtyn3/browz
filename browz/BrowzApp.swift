import Combine
import SwiftUI
import WebKit

@main
struct BrowzApp: App {
    @StateObject private var controller = BrowserController()

    var body: some Scene {
        WindowGroup {
            BrowserWindowView(controller: controller)
                .onOpenURL { url in
                    guard url.scheme?.lowercased() == InternalRoute.scheme else { return }
                    let urlString = url.absoluteString
                    if InternalRoute.parse(urlString) == .settings {
                        controller.openSettings()
                    }
                    // Add more routes here as you extend InternalRoute.
                }
        }
        .commands {
            CommandMenu("Tabs") {
                Button("Find Tab") { controller.presentFinder() }
                    .keyboardShortcut("k", modifiers: .command)
                Button("New Tab") { controller.newTab(openNavigationSurface: true) }
                    .keyboardShortcut("t", modifiers: .command)
                Button("New Private Tab") { controller.newPrivateTab() }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                Button("Close Tab") { controller.closeSelectedTab() }
                    .keyboardShortcut("w", modifiers: .command)
                Button("Reopen Last Closed Tab") { controller.reopenLastClosedTab() }
                    .keyboardShortcut("t", modifiers: [.command, .shift])

                Divider()

                Button("Select Next Tab") { controller.selectNextTab() }
                    .keyboardShortcut("]", modifiers: [.command, .shift])
                Button("Select Previous Tab") { controller.selectPrevTab() }
                    .keyboardShortcut("[", modifiers: [.command, .shift])

                Divider()

                ForEach(1...9, id: \.self) { i in
                    Button("Tab \(i)") { controller.selectTabAtIndex(i - 1) }
                        .keyboardShortcut(KeyEquivalent(Character("\(i)")), modifiers: .command)
                }
            }

            CommandMenu("Navigation") {
                Button("Open Address Bar") { controller.presentNavigationSurface() }
                    .keyboardShortcut("l", modifiers: .command)
                Button("Hide Address Bar") { controller.dismissNavigationSurface() }
                    .keyboardShortcut(.escape, modifiers: [])
                Button("Find in Page") { controller.toggleFindBar() }
                    .keyboardShortcut("f", modifiers: .command)

                Divider()

                Button("Back")    { controller.goBack() }
                    .keyboardShortcut("[", modifiers: .command)
                Button("Forward") { controller.goForward() }
                    .keyboardShortcut("]", modifiers: .command)
                Button("Reload")  { controller.reload() }
                    .keyboardShortcut("r", modifiers: .command)

                Divider()

                Button("Zoom In")    { controller.zoomIn() }
                    .keyboardShortcut("=", modifiers: .command)
                Button("Zoom Out")   { controller.zoomOut() }
                    .keyboardShortcut("-", modifiers: .command)
                Button("Actual Size") { controller.resetZoom() }
                    .keyboardShortcut("0", modifiers: .command)

                Divider()

                Button("Toggle Reader Mode") { controller.toggleReaderMode() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                Button("Toggle Split View") { controller.toggleSplitView() }
                    .keyboardShortcut("\\", modifiers: [.command, .shift])
            }

            CommandMenu("Workspaces") {
                Button("Manage Workspaces…") { controller.presentWorkspaceManager() }
                    .keyboardShortcut("w", modifiers: [.command, .option])

                Divider()

                Button("Next Workspace") { controller.workspaceStore.switchToNext() }
                    .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
                Button("Previous Workspace") { controller.workspaceStore.switchToPrev() }
                    .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
            }

            CommandMenu("Bookmarks") {
                Button("Bookmark This Page") { controller.bookmarkCurrentTab() }
                    .keyboardShortcut("d", modifiers: .command)
            }

            CommandMenu("History") {
                Button("Search History…") { controller.presentHistoryFinder() }
                    .keyboardShortcut("h", modifiers: [.command, .shift])
            }

            CommandGroup(replacing: .appSettings) {
                Button("Settings") { controller.openSettings() }
                    .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

// MARK: - BrowserController

@MainActor
final class BrowserController: ObservableObject {
    let store: TabStateStore
    let runtimeRegistry: TabRuntimeRegistry
    let historyStore: HistoryStore
    let bookmarkStore: BookmarkStore
    let workspaceStore: WorkspaceStore
    let downloadCoordinator: DownloadCoordinator
    let dialogPresenter: JSDialogPresenter
    private let persistence: TabSessionPersistence
    private let memoryManager: TabMemoryManager
    private var cancellables: Set<AnyCancellable> = []

    // Find bar state surfaced to BrowserWindowView
    @Published var isFindBarVisible = false
    @Published var findQuery = ""
    @Published var findMatchFound: Bool? = nil

    // Workspace manager sheet
    @Published var isWorkspaceManagerPresented = false

    // Reader mode per-tab
    @Published var readerModeActiveTabIDs: Set<UUID> = []

    init() {
        let store = TabStateStore()
        let runtimeRegistry = TabRuntimeRegistry()
        let persistence = TabSessionPersistence()
        let historyStore = HistoryStore()
        let bookmarkStore = BookmarkStore()
        let workspaceStore = WorkspaceStore()
        let downloadCoordinator = DownloadCoordinator()
        let dialogPresenter = JSDialogPresenter()

        self.store = store
        self.runtimeRegistry = runtimeRegistry
        self.persistence = persistence
        self.historyStore = historyStore
        self.bookmarkStore = bookmarkStore
        self.workspaceStore = workspaceStore
        self.downloadCoordinator = downloadCoordinator
        self.dialogPresenter = dialogPresenter
        self.memoryManager = TabMemoryManager(store: store, runtimeRegistry: runtimeRegistry)

        runtimeRegistry.onOpenNewTabRequest = { [weak self] url in
            self?.newTab(input: url.absoluteString == "about:blank" ? nil : url.absoluteString)
        }
        runtimeRegistry.onLoadingChange = { [weak self] tabID, isLoading in
            self?.store.setLoading(isLoading, for: tabID)
        }
        runtimeRegistry.onProgressChange = { [weak self] tabID, progress in
            self?.store.setProgress(progress, for: tabID)
        }
        runtimeRegistry.onDownloadStarted = { [weak downloadCoordinator] download in
            downloadCoordinator?.handle(download)
        }
        runtimeRegistry.onDialogRequest = { [weak dialogPresenter] request in
            dialogPresenter?.present(request)
        }
        runtimeRegistry.onPageTintChange = { [weak self] tabID, tint in
            // If sampling fails, keep the UI neutral by clearing the tint.
            self?.store.setPageTint(tint, for: tabID)
        }

        store.bootstrap(with: persistence.load())
        bindPersistence()
        bindWorkspace()
        memoryManager.start()

        // Async: load content rule list and apply to registry
        Task { [weak runtimeRegistry] in
            if let rules = await ContentBlocker.ruleList() {
                runtimeRegistry?.contentRuleList = rules
            }
        }
    }

    // MARK: - Tab access

    var selectedTab: TabState? { store.selectedTab }

    func presentFinder() {
        store.isNavigationSurfacePresented = false
        store.isFinderPresented = true
    }

    func dismissFinder() { store.isFinderPresented = false }

    func presentHistoryFinder() {
        store.isNavigationSurfacePresented = false
        store.isFinderPresented = false
        store.isHistoryFinderPresented = true
    }

    func dismissHistoryFinder() { store.isHistoryFinderPresented = false }

    func presentNavigationSurface() {
        store.isFinderPresented = false
        store.isNavigationSurfacePresented = true
    }

    func dismissNavigationSurface() { store.isNavigationSurfacePresented = false }

    func presentWorkspaceManager() {
        isWorkspaceManagerPresented = true
    }

    func dismissWorkspaceManager() {
        isWorkspaceManagerPresented = false
    }

    func openSettings() {
        let settingsURL = InternalRoute.settings.urlString
        if let existing = store.tabs.first(where: { $0.urlString == settingsURL }) {
            store.selectTab(existing.id)
        } else {
            let tab = store.createTab(initialInput: settingsURL, select: true)
            store.updateNavigation(id: tab.id, title: InternalRoute.settings.title, url: nil)
        }
        dismissFinder(); dismissNavigationSurface()
    }

    func newTab(input: String? = nil, openNavigationSurface: Bool = false) {
        let url: String
        if let input { url = input }
        else {
            let configured = BrowserSettings.shared.newTabURL
            url = (configured == "about:blank" || configured.isEmpty) ? "about:blank" : configured
        }
        _ = store.createTab(initialInput: url, select: true)

        if openNavigationSurface {
            presentNavigationSurface()
        }
    }

    func newPrivateTab(input: String? = nil) {
        _ = store.createTab(initialInput: input ?? "about:blank", select: true, isPrivate: true)
    }

    func closeTab(_ id: UUID) {
        runtimeRegistry.discardWebView(for: id)
        store.closeTab(id)
    }

    func closeSelectedTab() {
        guard let id = store.selectedTabID else { return }
        closeTab(id)
    }

    func reopenLastClosedTab() {
        guard let entry = historyStore.popMostRecentEntry() else { return }
        let alreadyOpen = store.tabs.contains { $0.urlString == entry.urlString }
        if alreadyOpen {
            historyStore.prependEntry(entry)
            return
        }
        newTab(input: entry.urlString)
    }

    func selectTab(_ id: UUID) {
        store.selectTab(id)
        dismissFinder(); dismissNavigationSurface()
    }

    func selectTabAtIndex(_ index: Int) { store.selectTabAtIndex(index) }
    func selectNextTab() { store.selectNextTab() }
    func selectPrevTab() { store.selectPrevTab() }
    func togglePin(_ id: UUID) { store.togglePin(id) }

    func navigateSelected(to input: String) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if InternalRoute.parse(trimmed) == .settings { openSettings(); return }

        guard let tab = store.activeTab else { return }
        store.updateAddressInput(trimmed, for: tab.id)
        let webView = runtimeRegistry.webView(for: tab) { [weak self] tabID, title, url in
            self?.store.updateNavigation(id: tabID, title: title, url: url)
        }
        if let url = BrowserSettings.shared.resolve(input: trimmed) {
            webView.load(URLRequest(url: url))
        }
        dismissNavigationSurface()
    }

    func navigationDidUpdate(tabID: UUID, title: String?, url: URL?) {
        store.updateNavigation(id: tabID, title: title, url: url)
        let isPrivate = store.tabs.first(where: { $0.id == tabID })?.isPrivate ?? false
        if !isPrivate { historyStore.record(title: title, url: url) }
    }

    /// The tab ID that navigation commands (back/forward/reload/navigate/zoom/find) target.
    var activeTabID: UUID? { store.activeTabID }

    func goBack()    { guard let id = activeTabID else { return }; runtimeRegistry.goBack(tabID: id) }
    func goForward() { guard let id = activeTabID else { return }; runtimeRegistry.goForward(tabID: id) }
    func reload()    { guard let id = activeTabID else { return }; runtimeRegistry.reload(tabID: id) }

    // MARK: - Zoom

    func zoomIn() {
        guard let id = activeTabID else { return }
        store.setZoom(runtimeRegistry.zoomIn(tabID: id), for: id)
    }

    func zoomOut() {
        guard let id = activeTabID else { return }
        store.setZoom(runtimeRegistry.zoomOut(tabID: id), for: id)
    }

    func resetZoom() {
        guard let id = activeTabID else { return }
        store.setZoom(runtimeRegistry.resetZoom(tabID: id), for: id)
    }

    // MARK: - Find in page

    func toggleFindBar() {
        if isFindBarVisible { closeFindBar() } else { isFindBarVisible = true }
    }

    func closeFindBar() {
        isFindBarVisible = false
        findQuery = ""
        findMatchFound = nil
        if let id = activeTabID { runtimeRegistry.clearFind(in: id) }
    }

    func findNext() {
        guard let id = activeTabID else { return }
        runtimeRegistry.findNext(findQuery, in: id) { [weak self] found in
            self?.findMatchFound = found
        }
    }

    func findPrev() {
        guard let id = activeTabID else { return }
        runtimeRegistry.findPrev(findQuery, in: id) { [weak self] found in
            self?.findMatchFound = found
        }
    }

    // MARK: - Reader mode

    func toggleReaderMode() {
        guard let id = activeTabID else { return }
        if readerModeActiveTabIDs.contains(id) {
            runtimeRegistry.deactivateReaderMode(tabID: id)
            readerModeActiveTabIDs.remove(id)
        } else {
            runtimeRegistry.activateReaderMode(tabID: id)
            readerModeActiveTabIDs.insert(id)
        }
    }

    // MARK: - Bookmarks

    func bookmarkCurrentTab() {
        guard let tab = selectedTab, let url = tab.resolvedURL else { return }
        if bookmarkStore.contains(urlString: url.absoluteString) {
            bookmarkStore.removeByURL(url.absoluteString)
        } else {
            bookmarkStore.add(title: tab.title, urlString: url.absoluteString)
        }
    }

    // MARK: - Split view

    func toggleSplitView() {
        if store.splitTabID != nil {
            store.splitTabID = nil
        } else {
            guard let id = store.selectedTabID else { return }
            let other = store.visibleTabs
                .filter { $0.id != id }
                .sorted { $0.lastAccessedAt > $1.lastAccessedAt }
                .first
            store.splitTabID = other?.id
        }
    }

    func openSplitPicker() {
        // Present the tab finder; the view layer handles routing into the split slot
        store.isFinderPresented = true
        store.splitPickerPending = true
    }

    func setSplitTab(_ id: UUID) {
        guard id != store.selectedTabID else { return }
        store.splitTabID = id
        store.splitPickerPending = false
        store.splitFocusedSide = .secondary
    }

    func closeSplitSide(_ side: TabStateStore.SplitSide) {
        store.closeSplitSide(side)
    }

    func focusSplitSide(_ side: TabStateStore.SplitSide) {
        store.focusSplitSide(side)
    }

    // MARK: - Memory / persistence helpers

    func runManualMemoryTrim() { memoryManager.trimNow() }

    private func bindPersistence() {
        store.$tabs
            .combineLatest(store.$selectedTabID)
            .debounce(for: .milliseconds(250), scheduler: DispatchQueue.main)
            .sink { [weak self] _, _ in
                guard let self else { return }
                self.persistence.save(self.store.sessionSnapshot())
            }
            .store(in: &cancellables)
    }

    private func bindWorkspace() {
        workspaceStore.$activeWorkspaceID
            .sink { [weak self] id in
                self?.store.activeWorkspaceID = id
            }
            .store(in: &cancellables)
    }

}
