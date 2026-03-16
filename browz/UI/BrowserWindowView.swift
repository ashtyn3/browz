import SwiftUI

private let surface         = Color.white.opacity(0.82)
private let surfaceElevated = Color.white.opacity(0.94)
private let stroke          = Color.black.opacity(0.09)
private let labelPrimary    = Color(red: 0.08, green: 0.08, blue: 0.09)
private let labelSecondary  = Color(red: 0.08, green: 0.08, blue: 0.09).opacity(0.50)

struct BrowserWindowView: View {
    @ObservedObject var controller: BrowserController
    @ObservedObject private var store: TabStateStore
    @ObservedObject private var downloadCoordinator: DownloadCoordinator
    @ObservedObject private var dialogPresenter: JSDialogPresenter
    @ObservedObject private var permissionPresenter: PermissionPresenter
    @ObservedObject private var bookmarkStore: BookmarkStore
    @ObservedObject private var workspaceStore: WorkspaceStore
    @ObservedObject private var settings = BrowserSettings.shared
    @StateObject private var suggestionService = SuggestionService()
    @State private var addressInput: String = ""
    @State private var selectedSuggestionIndex: Int? = nil
    @State private var isDownloadHUDVisible: Bool = false
    @FocusState private var isAddressFocused: Bool

    init(controller: BrowserController) {
        self.controller = controller
        _store = ObservedObject(initialValue: controller.store)
        _downloadCoordinator = ObservedObject(initialValue: controller.downloadCoordinator)
        _dialogPresenter = ObservedObject(initialValue: controller.dialogPresenter)
        _permissionPresenter = ObservedObject(initialValue: controller.permissionPresenter)
        _bookmarkStore = ObservedObject(initialValue: controller.bookmarkStore)
        _workspaceStore = ObservedObject(initialValue: controller.workspaceStore)
        _addressInput = State(initialValue: controller.selectedTab?.urlString ?? "")
    }

    var body: some View {
        ZStack(alignment: .top) {
            contentArea
                .padding(10)

            if store.isNavigationSurfacePresented {
                navigationSurface
                    .padding(.top, 40)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .zIndex(2)
                    .animation(.spring(duration: 0.22), value: store.isNavigationSurfacePresented)
                    .onAppear {
                        addressInput = store.activeTab?.urlString ?? ""
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            isAddressFocused = true
                        }
                    }
            }

            // Tab finder (Cmd+K) and history finder as in-window overlays — same layer as nav, so they get true liquid glass over the tinted window.
            if store.isFinderPresented {
                finderOverlay
            }
            if store.isHistoryFinderPresented {
                historyFinderOverlay
            }
            if controller.isWorkspaceManagerPresented {
                workspaceManagerOverlay
            }
        }
        .onChange(of: store.selectedTabID) {
            addressInput = store.activeTab?.urlString ?? ""
        }
        .onChange(of: store.splitFocusedSide) {
            addressInput = store.activeTab?.urlString ?? ""
        }
        .onChange(of: store.isNavigationSurfacePresented) {
            if !store.isNavigationSurfacePresented {
                isAddressFocused = false
                suggestionService.clear()
                selectedSuggestionIndex = nil
            }
        }
        .onExitCommand {
            if controller.isWorkspaceManagerPresented { controller.dismissWorkspaceManager() }
            else if store.isHistoryFinderPresented { controller.dismissHistoryFinder() }
            else if store.isFinderPresented { controller.dismissFinder() }
            else if store.isNavigationSurfacePresented { controller.dismissNavigationSurface() }
            else if controller.isFindBarVisible { controller.closeFindBar() }
        }
        .overlay(alignment: .bottomTrailing) {
            if !downloadCoordinator.items.isEmpty && isDownloadHUDVisible {
                DownloadHUD(coordinator: downloadCoordinator, onClose: {
                    withAnimation(.spring(duration: 0.25)) { isDownloadHUDVisible = false }
                })
                .padding(16)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .animation(.spring(duration: 0.25), value: isDownloadHUDVisible)
            }
        }
        .onChange(of: downloadCoordinator.items.count) { old, new in
            if new > old { withAnimation(.spring(duration: 0.25)) { isDownloadHUDVisible = true } }
        }
        .overlay {
            JSDialogOverlay(presenter: dialogPresenter).zIndex(100)
            PermissionOverlay(presenter: permissionPresenter).zIndex(101)
        }
        .background(windowTintBackground)
        .background(.ultraThinMaterial)
        .background(
            WindowCloseInterceptor {
                controller.closeSelectedTab()
                return false
            }
        )
        .frame(minWidth: 980, minHeight: 680)
        .onChange(of: isAnyOverlayPresented) { _, overlayActive in
            // Freeze / restore CSS :hover on every live page by toggling
            // pointer-events on the document root. This is the only approach
            // that reliably prevents hover bleed-through: AppKit routes
            // mouseMoved to WKWebView's first-responder regardless of what
            // SwiftUI layers are on top, but pointer-events:none makes the
            // web content itself ignore the mouse position entirely.
            controller.runtimeRegistry.setPointerEventsEnabled(!overlayActive)
            if overlayActive { NSCursor.arrow.set() }
        }
    }

    // MARK: - In-window finder overlays (liquid glass over tinted window)

    private var finderOverlay: some View {
        ZStack {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { controller.dismissFinder() }

            if store.splitPickerPending {
                TabFuzzyFinder(
                    tabs: store.visibleTabs.filter { $0.id != store.selectedTabID },
                    selectedTabID: store.splitTabID,
                    historyStore: controller.historyStore,
                    bookmarkStore: controller.bookmarkStore,
                    headerLabel: "Choose tab for split pane",
                    onSelect: { controller.setSplitTab($0) },
                    onClose: { _ in },
                    onTogglePin: { _ in },
                    onCreate: { query in
                        let tab = controller.store.createTab(initialInput: query)
                        controller.setSplitTab(tab.id)
                        controller.dismissFinder()
                    },
                    pageTint: store.activeTabPageTint
                )
                .onDisappear { store.splitPickerPending = false }
            } else {
                TabFuzzyFinder(
                    tabs: store.visibleTabs,
                    selectedTabID: store.selectedTabID,
                    historyStore: controller.historyStore,
                    bookmarkStore: controller.bookmarkStore,
                    onSelect: { controller.selectTab($0) },
                    onClose: { controller.closeTab($0) },
                    onTogglePin: { controller.togglePin($0) },
                    onCreate: { query in
                        controller.newTab(input: query)
                        controller.dismissFinder()
                    },
                    pageTint: store.activeTabPageTint,
                    onMoveTab: { sourceID, targetID in
                        controller.store.moveTab(sourceID, before: targetID)
                    },
                    splitTabID: store.splitTabID,
                    onBreakSplit: { id in
                        if id == store.selectedTabID {
                            controller.store.closeSplitSide(.primary)
                        } else {
                            controller.store.closeSplitSide(.secondary)
                        }
                    }
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .zIndex(5)
        .transition(.opacity)
        .animation(.easeOut(duration: 0.2), value: store.isFinderPresented)
    }

    private var workspaceManagerOverlay: some View {
        ZStack {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { controller.dismissWorkspaceManager() }

            WorkspaceManagerView(
                store: workspaceStore,
                pageTint: store.activeTabPageTint,
                onDismiss: { controller.dismissWorkspaceManager() }
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .zIndex(5)
        .transition(.opacity)
        .animation(.easeOut(duration: 0.2), value: controller.isWorkspaceManagerPresented)
    }

    private var historyFinderOverlay: some View {
        ZStack {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { controller.dismissHistoryFinder() }

            HistoryFuzzyFinder(
                historyStore: controller.historyStore,
                pageTint: store.activeTabPageTint,
                onCreate: { input in
                    controller.newTab(input: input)
                    controller.dismissHistoryFinder()
                }
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .zIndex(5)
        .transition(.opacity)
        .animation(.easeOut(duration: 0.2), value: store.isHistoryFinderPresented)
    }

    // MARK: - Helpers (all respect the focused split side)

    private var activeTab: TabState? { store.activeTab }

    private var activePageTint: PageTint? { store.activeTabPageTint }

    /// True whenever any overlay floats above the web content.
    private var isAnyOverlayPresented: Bool {
        store.isNavigationSurfacePresented
            || store.isFinderPresented
            || store.isHistoryFinderPresented
            || controller.isWorkspaceManagerPresented
    }

    private var windowTintBackground: Color {
        guard let tint = activePageTint else {
            return Color.black.opacity(0.03)
        }
        return Color(red: tint.r, green: tint.g, blue: tint.b).opacity(0.30)
    }

    /// Same tint as window background; use as full-bleed behind sheet content so material picks it up.
    private var sheetTintFill: some View {
        windowTintBackground
            .ignoresSafeArea()
    }

    // MARK: - Page loading indicator

    private func pageLoadingProgressBar(tabID: UUID) -> some View {
        let progress = store.tabProgress[tabID] ?? 0
        let isLoading = store.loadingTabIDs.contains(tabID)
        let visible = isLoading || (progress > 0 && progress < 1)
        let tint = store.tabs.first(where: { $0.id == tabID })?.pageTint
        let accent: Color = tint.map { Color(red: $0.r, green: $0.g, blue: $0.b) } ?? Color.accentColor

        return GeometryReader { geo in
            if visible {
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(accent.opacity(0.25))
                        .frame(height: 3)
                    Rectangle()
                        .fill(accent)
                        .frame(width: max(0, geo.size.width * progress), height: 3)
                        .animation(.easeInOut(duration: 0.15), value: progress)
                }
            }
        }
        .frame(height: visible ? 3 : 0)
        .animation(.easeInOut(duration: 0.2), value: visible)
    }

    // MARK: - Content area (supports split view)

    private var contentArea: some View {
        Group {
            if let splitTab = store.splitTab,
               let primary = store.selectedTab,
               primary.id != splitTab.id {
                splitView(primary: primary, secondary: splitTab)
            } else {
                singlePane
            }
        }
    }

    private func splitView(primary: TabState, secondary: TabState) -> some View {
        HStack(spacing: 6) {
            splitPane(tab: primary, side: .primary)
            splitPane(tab: secondary, side: .secondary)
        }
        .animation(.spring(duration: 0.25), value: store.splitFocusedSide == .primary)
    }

    private func splitPane(tab: TabState, side: TabStateStore.SplitSide) -> some View {
        let isFocused = store.splitFocusedSide == side
        let isLoading = store.loadingTabIDs.contains(tab.id)

        return VStack(spacing: 0) {
            // Per-pane header
            HStack(spacing: 6) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(0.5)
                        .frame(width: 12, height: 12)
                } else {
                    Image(systemName: tab.isPrivate ? "lock.fill" : "globe")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(isFocused ? labelPrimary : labelSecondary)
                }

                Text(tab.title ?? tab.urlString)
                    .font(.system(size: 11, weight: isFocused ? .medium : .regular))
                    .foregroundStyle(isFocused ? labelPrimary : labelSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                // Change tab button (only on secondary, to swap which tab is shown)
                if side == .secondary {
                    Button {
                        store.splitPickerPending = true
                        store.isFinderPresented = true
                    } label: {
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(labelSecondary)
                            .frame(width: 18, height: 18)
                            .background(Color.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 5))
                            .hoverElevated(cornerRadius: 5, hoverOpacity: 0.10)
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    withAnimation(.spring(duration: 0.22)) {
                        controller.closeSplitSide(side)
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(labelSecondary)
                        .frame(width: 18, height: 18)
                        .background(Color.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 5))
                        .hoverElevated(cornerRadius: 5, hoverOpacity: 0.10)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                isFocused
                    ? surfaceElevated
                    : Color.black.opacity(0.02),
                in: Rectangle()
            )
            .overlay(
                Rectangle()
                    .frame(height: 1)
                    .foregroundStyle(stroke),
                alignment: .bottom
            )

            pageLoadingProgressBar(tabID: tab.id)

            // Webview content
            Group {
                if InternalRoute.parse(tab.urlString) == .settings {
                    SettingsTabView()
                } else {
                    VStack(spacing: 0) {
                        WebViewContainer(
                            tab: tab,
                            runtimeRegistry: controller.runtimeRegistry,
                            onNavigationUpdate: controller.navigationDidUpdate(tabID:title:url:)
                        )
                        if controller.isFindBarVisible && isFocused {
                            FindBar(
                                query: $controller.findQuery,
                                matchFound: controller.findMatchFound,
                                onNext: controller.findNext,
                                onPrev: controller.findPrev,
                                onClose: controller.closeFindBar
                            )
                            .padding(8)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .onChange(of: controller.findQuery) {
                        if !controller.findQuery.isEmpty && isFocused { controller.findNext() }
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if !isFocused {
                    store.focusSplitSide(side)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    isFocused ? Color.accentColor.opacity(0.35) : stroke,
                    lineWidth: isFocused ? 1.5 : 1
                )
        )
        .animation(.easeInOut(duration: 0.15), value: controller.isFindBarVisible)
    }

    private var singlePane: some View {
        Group {
            if let tab = store.selectedTab {
                if InternalRoute.parse(tab.urlString) == .settings {
                    SettingsTabView()
                        .styledPane(stroke: stroke)
                } else {
                    let isBlankStart = store.tabs.count == 1 && tab.urlString == "about:blank" && settings.showKeyboardShortcutHelperOnBlank
                    ZStack {
                        VStack(spacing: 0) {
                            pageLoadingProgressBar(tabID: tab.id)
                        WebViewContainer(
                            tab: tab,
                            runtimeRegistry: controller.runtimeRegistry,
                            onNavigationUpdate: controller.navigationDidUpdate(tabID:title:url:)
                        )
                        if controller.isFindBarVisible {
                                FindBar(
                                    query: $controller.findQuery,
                                    matchFound: controller.findMatchFound,
                                    onNext: controller.findNext,
                                    onPrev: controller.findPrev,
                                    onClose: controller.closeFindBar
                                )
                                .padding(8)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                            }
                        }
                        .onChange(of: controller.findQuery) {
                            if !controller.findQuery.isEmpty { controller.findNext() }
                        }
                        if isBlankStart {
                            StartScreenView()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .styledPane(stroke: stroke)
                }
            } else {
                emptyState
            }
        }
        .animation(.spring(duration: 0.2), value: controller.isFindBarVisible)
    }

    private var emptyState: some View {
        ZStack {
            Color.clear
            if settings.showKeyboardShortcutHelperOnBlank {
                StartScreenView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text("No tab selected")
                    .foregroundStyle(labelSecondary)
            }
        }
    }

    // MARK: - Navigation surface

    private var navigationSurface: some View {
        navigationSurfaceContent
            .frame(maxWidth: 720)
            .background(Color.white.opacity(0.80))
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.12), radius: 24, y: 8)
            .animation(.easeOut(duration: 0.12), value: suggestionService.suggestions.count)
    }

    private var navigationSurfaceContent: some View {
        VStack(spacing: 0) {
            navigationBarRow
            if !suggestionService.suggestions.isEmpty {
                Divider().overlay(Color.black.opacity(0.06)).padding(.horizontal, 10)
                navigationSuggestionsList
            }
        }
    }

    private var navigationBarRow: some View {
        HStack(spacing: 6) {
            navBtn("chevron.left",    action: controller.goBack)
            navBtn("chevron.right",   action: controller.goForward)
            navBtn("arrow.clockwise", action: controller.reload)
            navigationAddressField
            navBtn("xmark", action: {
                suggestionService.clear()
                controller.dismissNavigationSurface()
            })
        }
        .padding(10)
    }

    private var navigationAddressField: some View {
        TextField("URL or search", text: $addressInput)
            .font(.system(size: 13, weight: .regular))
            .foregroundStyle(labelPrimary)
            .textFieldStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
            )
            .focused($isAddressFocused)
            .onChange(of: addressInput) {
                selectedSuggestionIndex = nil
                suggestionService.update(query: addressInput)
            }
            .onSubmit {
                let target = selectedSuggestionIndex.map { suggestionService.suggestions[$0] } ?? addressInput
                controller.navigateSelected(to: target)
                suggestionService.clear()
            }
            .onKeyPress(phases: .down) { press in
                let isCtrl  = press.modifiers == .control
                let isPlain = press.modifiers.isEmpty
                let count   = suggestionService.suggestions.count
                guard count > 0 else { return .ignored }
                let goNext = (isCtrl && press.key == KeyEquivalent("n")) || (isPlain && press.key == .downArrow)
                let goPrev = (isCtrl && press.key == KeyEquivalent("p")) || (isPlain && press.key == .upArrow)
                if goNext { selectedSuggestionIndex = min((selectedSuggestionIndex ?? -1) + 1, count - 1); return .handled }
                if goPrev { guard let idx = selectedSuggestionIndex else { return .ignored }; selectedSuggestionIndex = idx > 0 ? idx - 1 : nil; return .handled }
                return .ignored
            }
    }

    private var navigationSuggestionsList: some View {
        VStack(spacing: 2) {
            ForEach(Array(suggestionService.suggestions.enumerated()), id: \.offset) { idx, suggestion in
                suggestionRow(suggestion, index: idx)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private func suggestionRow(_ suggestion: String, index: Int) -> some View {
        let isSelected = selectedSuggestionIndex == index
        return HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(isSelected ? labelPrimary : labelSecondary)
                .frame(width: 16)
            Text(suggestion)
                .font(.system(size: 13))
                .foregroundStyle(isSelected ? labelPrimary : labelSecondary)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(isSelected ? Color.black.opacity(0.10) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .contentShape(Rectangle())
        .onHover { if $0 { selectedSuggestionIndex = index } }
        .onTapGesture {
            controller.navigateSelected(to: suggestion)
            suggestionService.clear()
        }
    }

    // MARK: - Shared sub-views

    private func navBtn(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(labelPrimary)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Color.white.opacity(0.20), lineWidth: 1)
        )
        .hoverElevated(cornerRadius: 7)
    }

}

// MARK: - Pane styling

private extension View {
    func styledPane(stroke: Color) -> some View {
        self
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(stroke, lineWidth: 1))
            .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
    }
}

