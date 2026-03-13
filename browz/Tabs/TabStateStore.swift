import Combine
import Foundation

@MainActor
final class TabStateStore: ObservableObject {
    @Published private(set) var tabs: [TabState] = []
    @Published var selectedTabID: UUID?
    @Published var isFinderPresented: Bool = false
    @Published var isNavigationSurfacePresented: Bool = false
    @Published private(set) var loadingTabIDs: Set<UUID> = []
    @Published private(set) var tabProgress: [UUID: Double] = [:]
    @Published private(set) var tabZoom: [UUID: Double] = [:]
    /// Second tab shown in split view; nil = single-pane mode.
    @Published var splitTabID: UUID? = nil
    /// Which split pane responds to keyboard navigation.
    @Published var splitFocusedSide: SplitSide = .primary
    /// True while the user is picking a tab to fill the split secondary pane.
    @Published var splitPickerPending: Bool = false
    /// Active workspace filter — nil shows all tabs.
    @Published var activeWorkspaceID: UUID? = nil

    enum SplitSide { case primary, secondary }

    var selectedTab: TabState? {
        guard let selectedTabID else { return nil }
        return tabs.first(where: { $0.id == selectedTabID })
    }

    var splitTab: TabState? {
        guard let splitTabID else { return nil }
        return tabs.first(where: { $0.id == splitTabID })
    }

    /// The tab that keyboard navigation currently targets.
    var activeTabID: UUID? {
        (splitTabID != nil && splitFocusedSide == .secondary) ? splitTabID : selectedTabID
    }

    var activeTab: TabState? {
        guard let id = activeTabID else { return nil }
        return tabs.first(where: { $0.id == id })
    }

    /// Tabs visible in the current workspace filter.
    var visibleTabs: [TabState] {
        guard let wsID = activeWorkspaceID else { return tabs }
        return tabs.filter { $0.workspaceID == wsID }
    }

    func bootstrap(with persisted: PersistedTabSession?) {
        if let persisted, !persisted.tabs.isEmpty {
            tabs = persisted.tabs
            selectedTabID = persisted.selectedTabID ?? persisted.tabs.first?.id
            if let selectedTabID {
                markTabAsActive(selectedTabID)
            }
            return
        }

        let defaultTab = TabState()
        tabs = [defaultTab]
        selectedTabID = defaultTab.id
    }

    func createTab(initialInput: String = "about:blank", select: Bool = true, isPrivate: Bool = false) -> TabState {
        var tab = TabState(urlString: initialInput, isPrivate: isPrivate, workspaceID: activeWorkspaceID)
        if !select {
            tab.lifecycle = .suspended
        }
        tabs.append(tab)
        if select {
            selectedTabID = tab.id
            markTabAsActive(tab.id)
        }
        return tab
    }

    func closeTab(_ id: UUID) {
        tabs.removeAll(where: { $0.id == id })
        guard !tabs.isEmpty else {
            let replacement = TabState()
            tabs = [replacement]
            selectedTabID = replacement.id
            return
        }

        if selectedTabID == id {
            selectedTabID = tabs.first?.id
            if let selectedTabID {
                markTabAsActive(selectedTabID)
            }
        }
    }

    func selectTab(_ id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        selectedTabID = id
        markTabAsActive(id)
    }

    func updateNavigation(id: UUID, title: String?, url: URL?) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        if let title, !title.isEmpty {
            tabs[index].title = title
        }
        if let url {
            tabs[index].urlString = url.absoluteString
        }
        tabs[index].lastAccessedAt = .now
    }

    func updateAddressInputForSelectedTab(_ input: String) {
        guard let selectedTabID,
              let index = tabs.firstIndex(where: { $0.id == selectedTabID }) else { return }
        tabs[index].urlString = input
    }

    func togglePin(_ id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].isPinned.toggle()
    }

    func setLifecycle(_ lifecycle: TabLifecycle, for id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].lifecycle = lifecycle
    }

    func markTabAsActive(_ id: UUID) {
        for index in tabs.indices {
            if tabs[index].id == id {
                tabs[index].lifecycle = .active
                tabs[index].lastAccessedAt = .now
            } else if tabs[index].lifecycle == .active {
                tabs[index].lifecycle = .suspended
            }
        }
    }

    func discardCandidates(excluding protectedIDs: Set<UUID>, maxCount: Int) -> [UUID] {
        guard maxCount > 0 else { return [] }
        let sorted = tabs
            .filter { !protectedIDs.contains($0.id) && !$0.isPinned }
            .sorted(by: { $0.lastAccessedAt < $1.lastAccessedAt })
        return Array(sorted.prefix(maxCount).map(\.id))
    }

    func setLoading(_ loading: Bool, for id: UUID) {
        if loading {
            loadingTabIDs.insert(id)
            tabProgress[id] = 0
        } else {
            loadingTabIDs.remove(id)
            tabProgress.removeValue(forKey: id)
        }
    }

    func setProgress(_ progress: Double, for id: UUID) {
        tabProgress[id] = progress
    }

    func setZoom(_ zoom: Double, for id: UUID) {
        tabZoom[id] = zoom
    }

    func selectTabAtIndex(_ index: Int) {
        let pool = visibleTabs
        guard index >= 0 && index < pool.count else { return }
        selectTab(pool[index].id)
    }

    func selectNextTab() {
        let pool = visibleTabs
        guard pool.count > 1,
              let cur = pool.firstIndex(where: { $0.id == selectedTabID }) else { return }
        selectTab(pool[(cur + 1) % pool.count].id)
    }

    func selectPrevTab() {
        let pool = visibleTabs
        guard pool.count > 1,
              let cur = pool.firstIndex(where: { $0.id == selectedTabID }) else { return }
        selectTab(pool[(cur - 1 + pool.count) % pool.count].id)
    }

    func toggleSplitTab(_ id: UUID) {
        splitTabID = (splitTabID == id) ? nil : id
        if splitTabID != nil { splitFocusedSide = .primary }
    }

    func focusSplitSide(_ side: SplitSide) {
        guard splitTabID != nil else { return }
        splitFocusedSide = side
    }

    /// Close one pane of the split. If primary is closed, secondary becomes primary.
    func closeSplitSide(_ side: SplitSide) {
        switch side {
        case .secondary:
            splitTabID = nil
            splitFocusedSide = .primary
        case .primary:
            if let sid = splitTabID {
                selectedTabID = sid
                splitTabID = nil
                splitFocusedSide = .primary
            }
        }
    }

    func updateAddressInput(_ input: String, for tabID: UUID) {
        guard let idx = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        tabs[idx].urlString = input
    }

    func sessionSnapshot() -> PersistedTabSession {
        let publicTabs = tabs.filter { !$0.isPrivate }
        let resolvedID = publicTabs.contains(where: { $0.id == selectedTabID }) ? selectedTabID : publicTabs.last?.id
        return PersistedTabSession(tabs: publicTabs, selectedTabID: resolvedID)
    }
}
