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
    @ObservedObject private var bookmarkStore: BookmarkStore
    @ObservedObject private var workspaceStore: WorkspaceStore
    @ObservedObject private var settings = BrowserSettings.shared
    @StateObject private var suggestionService = SuggestionService()
    @State private var addressInput: String = ""
    @State private var selectedSuggestionIndex: Int? = nil
    @State private var isDownloadHUDVisible: Bool = false
    @State private var showWorkspaceManager = false
    @FocusState private var isAddressFocused: Bool

    init(controller: BrowserController) {
        self.controller = controller
        _store = ObservedObject(initialValue: controller.store)
        _downloadCoordinator = ObservedObject(initialValue: controller.downloadCoordinator)
        _dialogPresenter = ObservedObject(initialValue: controller.dialogPresenter)
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
        }
        .sheet(isPresented: $store.isFinderPresented) {
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
                    }
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
                    }
                )
            }
        }
        .sheet(isPresented: $showWorkspaceManager) {
            WorkspaceManagerView(store: workspaceStore)
        }
        .sheet(isPresented: $store.isHistoryFinderPresented) {
            HistoryFuzzyFinder(
                historyStore: controller.historyStore,
                onCreate: { input in
                    controller.newTab(input: input)
                    controller.dismissHistoryFinder()
                }
            )
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
            if store.isHistoryFinderPresented { controller.dismissHistoryFinder() }
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
        }
        .background(.ultraThinMaterial)
        .background(
            WindowCloseInterceptor {
                controller.closeSelectedTab()
                return false
            }
        )
        .frame(minWidth: 980, minHeight: 680)
    }

    // MARK: - Helpers (all respect the focused split side)

    private var activeTab: TabState? { store.activeTab }

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
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded {
            if !isFocused { store.focusSplitSide(side) }
        })
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
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                navBtn("chevron.left",    action: controller.goBack)
                navBtn("chevron.right",   action: controller.goForward)
                navBtn("arrow.clockwise", action: controller.reload)

                TextField("URL or search", text: $addressInput)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(labelPrimary)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(stroke, lineWidth: 1))
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

                navBtn("xmark", action: {
                    suggestionService.clear()
                    controller.dismissNavigationSurface()
                })
            }
            .padding(10)

            if !suggestionService.suggestions.isEmpty {
                Divider().overlay(Color.black.opacity(0.06)).padding(.horizontal, 10)
                VStack(spacing: 2) {
                    ForEach(Array(suggestionService.suggestions.enumerated()), id: \.offset) { idx, suggestion in
                        suggestionRow(suggestion, index: idx)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
        }
        .frame(maxWidth: 720)
        .background(surfaceElevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(stroke, lineWidth: 1))
        .shadow(color: .black.opacity(0.12), radius: 16, y: 5)
        .animation(.easeOut(duration: 0.12), value: suggestionService.suggestions.count)
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
        .background(isSelected ? Color.black.opacity(0.06) : Color.clear,
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
        .background(surfaceElevated, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(stroke, lineWidth: 1))
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

