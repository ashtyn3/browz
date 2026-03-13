import SwiftUI
import AppKit

// MARK: - Palette tokens
private let accentBar    = Color(red: 0.20, green: 0.20, blue: 0.22)
private let privateColor = Color(red: 0.38, green: 0.28, blue: 0.68)

// MARK: - Navigable item

private enum FinderItem {
    case tab(TabState)
    case bookmark(BookmarkEntry)
    case history(HistoryEntry)
    case openURL(String)
}

struct TabFuzzyFinder: View {
    let tabs: [TabState]
    let selectedTabID: UUID?
    let historyStore: HistoryStore
    let bookmarkStore: BookmarkStore
    var headerLabel: String? = nil
    let onSelect: (UUID) -> Void
    let onClose: (UUID) -> Void
    let onTogglePin: (UUID) -> Void
    let onCreate: (String) -> Void

    private let palette: FinderPalette

    @State private var query: String = ""
    @State private var hoveredTabID: UUID? = nil
    @State private var selectedIndex: Int? = nil
    @State private var keyMonitor: Any? = nil
    @FocusState private var isFocused: Bool

    private static let notifNext = Notification.Name("browz.finder.selectNext")
    private static let notifPrev = Notification.Name("browz.finder.selectPrev")

    init(
        tabs: [TabState],
        selectedTabID: UUID?,
        historyStore: HistoryStore,
        bookmarkStore: BookmarkStore,
        headerLabel: String? = nil,
        onSelect: @escaping (UUID) -> Void,
        onClose: @escaping (UUID) -> Void,
        onTogglePin: @escaping (UUID) -> Void,
        onCreate: @escaping (String) -> Void,
        pageTint: PageTint? = nil
    ) {
        self.tabs = tabs
        self.selectedTabID = selectedTabID
        self.historyStore = historyStore
        self.bookmarkStore = bookmarkStore
        self.headerLabel = headerLabel
        self.onSelect = onSelect
        self.onClose = onClose
        self.onTogglePin = onTogglePin
        self.onCreate = onCreate
        self._query = State(initialValue: "")
        self._hoveredTabID = State(initialValue: nil)
        self._selectedIndex = State(initialValue: nil)
        self._keyMonitor = State(initialValue: nil)
        self._isFocused = FocusState()
        self.palette = FinderPalette.make(pageTint: pageTint)
    }

    // MARK: - Computed lists

    private var rankedTabs: [TabState] {
        let scored: [(TabState, Int)] = tabs.map { tab in
            let haystack = "\(tab.title) \(tab.urlString)"
            let base = FuzzyMatch.score(query: query, candidate: haystack)
            let recencyBonus = Int(Date.now.timeIntervalSince(tab.lastAccessedAt) * -0.01)
            return (tab, base + recencyBonus)
        }
        let filtered = scored.filter { query.isEmpty || $0.1 > 0 }
        return filtered.sorted { lhs, rhs in
            lhs.1 != rhs.1 ? lhs.1 > rhs.1 : lhs.0.lastAccessedAt > rhs.0.lastAccessedAt
        }.map(\.0)
    }

    private var allItems: [FinderItem] {
        var items: [FinderItem] = rankedTabs.map { .tab($0) }
        if items.isEmpty && !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            items.append(.openURL(query))
        }
        return items
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let label = headerLabel {
                HStack {
                    Image(systemName: "rectangle.split.2x1")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(palette.labelSecondary)
                    Text(label)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(palette.labelSecondary)
                    Spacer()
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 9)
                .background(Color.black.opacity(0.025))
                Divider().overlay(palette.divider)
            }
            searchBar
            Divider().overlay(palette.divider)
            resultsList
            footer
        }
        .frame(width: 580)
        .background(Color.white.opacity(0.87))
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.10), radius: 30, y: 12)
        .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
        .onAppear {
            if allItems.count > 0 { selectedIndex = 0 }
            isFocused = true
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                let ctrl = event.modifierFlags.contains(.control)
                let plain = event.modifierFlags.intersection([.shift, .option, .command, .control]).isEmpty
                let isNext = (ctrl && event.keyCode == 45) || (plain && event.keyCode == 125)
                let isPrev = (ctrl && event.keyCode == 35) || (plain && event.keyCode == 126)
                if isNext { NotificationCenter.default.post(name: Self.notifNext, object: nil); return nil }
                if isPrev { NotificationCenter.default.post(name: Self.notifPrev, object: nil); return nil }
                return event
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { isFocused = true }
        }
        .onDisappear {
            if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
        }
        .onReceive(NotificationCenter.default.publisher(for: Self.notifNext)) { _ in
            let count = allItems.count
            guard count > 0 else { return }
            selectedIndex = min((selectedIndex ?? -1) + 1, count - 1)
        }
        .onReceive(NotificationCenter.default.publisher(for: Self.notifPrev)) { _ in
            guard let idx = selectedIndex else { return }
            selectedIndex = idx > 0 ? idx - 1 : nil
        }
    }

    // MARK: - Search bar

    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(palette.iconTint)
                .frame(width: 20)

            TextField("Find tab or search web…", text: $query)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(palette.labelPrimary)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .onChange(of: query) { selectedIndex = nil }
                .onSubmit { activateSelected() }
                .onKeyPress(phases: .down) { press in
                    handleNavKey(press)
                }

            if !query.isEmpty {
                Button {
                    query = ""
                    selectedIndex = nil
                    isFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(palette.labelTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
    }

    // MARK: - Results

    /// Approximate height per row (padding + content); used so the list sizes to content and the panel stays compact.
    private static let rowHeight: CGFloat = 52
    private static let listVerticalPadding: CGFloat = 16
    private static let listMaxHeight: CGFloat = 460

    private var resultsList: some View {
        let tabList   = rankedTabs
        let tabOffset = 0
        let rowCount  = tabList.isEmpty && !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 1 : tabList.count
        let contentHeight = CGFloat(rowCount) * Self.rowHeight + Self.listVerticalPadding
        let listHeight = min(contentHeight, Self.listMaxHeight)

        return ScrollView {
            LazyVStack(spacing: 2) {
                if !tabList.isEmpty {
                    ForEach(Array(tabList.enumerated()), id: \.element.id) { i, tab in
                        tabRow(tab, listIndex: tabOffset + i)
                    }
                }

                if tabList.isEmpty && !query.isEmpty {
                    openURLRow
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        }
        .frame(height: listHeight)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(palette.labelTertiary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var openURLRow: some View {
        let isSelected = selectedIndex == 0
        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(palette.input)
                    .frame(width: 32, height: 32)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.iconTint)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Open URL or search")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(palette.labelPrimary)
                Text(query)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.labelSecondary)
                    .lineLimit(1)
            }

            Spacer()
                    kbdChip("↵")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? palette.rowSelected : palette.rowHover)
        )
        .contentShape(Rectangle())
        .onTapGesture { onCreate(query) }
        .hoverElevated(cornerRadius: 10, baseOpacity: 0.0, hoverOpacity: 0.10)
    }

    // MARK: - Tab row

    private func tabRow(_ tab: TabState, listIndex: Int) -> some View {
        let isActive   = tab.id == selectedTabID
        let isHovered  = hoveredTabID == tab.id
        let isSel      = selectedIndex == listIndex
        let rowAccent  = tab.isPrivate ? privateColor : accentBar

        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isActive ? rowAccent.opacity(0.10) : palette.input)
                    .frame(width: 32, height: 32)
                Image(systemName: tab.isPrivate ? "shield.fill" : "globe")
                    .font(.system(size: 13))
                    .foregroundStyle(isActive ? rowAccent : (tab.isPrivate ? privateColor.opacity(0.55) : palette.labelTertiary))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(tab.title)
                    .font(.system(size: 13, weight: isActive ? .semibold : .medium))
                    .foregroundStyle(isActive ? rowAccent : palette.labelPrimary)
                    .lineLimit(1)
                Text(tab.urlString)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.labelSecondary)
                    .lineLimit(1)
            }

            Spacer()

            HStack(spacing: 6) {
                if tab.isPrivate && !isHovered && !isActive && !isSel {
                    Image(systemName: "shield.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(privateColor.opacity(0.50))
                }
                if tab.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(palette.labelTertiary)
                }
                if isHovered || isActive || isSel {
                    rowAction(icon: tab.isPinned ? "pin.slash" : "pin") {
                        onTogglePin(tab.id)
                    }
                    rowAction(icon: "xmark") {
                        onClose(tab.id)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(rowBg(isActive: isActive, isSel: isSel, isHovered: isHovered))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isActive ? rowAccent.opacity(0.18) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onHover { hoveredTabID = $0 ? tab.id : nil }
        .onTapGesture { onSelect(tab.id) }
        .hoverElevated(cornerRadius: 10, baseOpacity: 0.0, hoverOpacity: 0.10)
    }

    private func rowBg(isActive: Bool, isSel: Bool, isHovered: Bool) -> Color {
        if isActive { return accentBar.opacity(0.07) }
        if isSel    { return palette.rowSelected }
        if isHovered { return palette.rowHover }
        return .clear
    }

    private func rowAction(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(palette.labelSecondary)
                .frame(width: 24, height: 24)
                .background(palette.input, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 16) {
            HStack(spacing: 4) {
                kbdChip("↵")
                Text("open")
                    .font(.system(size: 10))
                    .foregroundStyle(palette.labelTertiary)
            }
            HStack(spacing: 4) {
                kbdChip("^N/P")
                Text("navigate")
                    .font(.system(size: 10))
                    .foregroundStyle(palette.labelTertiary)
            }
            HStack(spacing: 4) {
                kbdChip("⌘W")
                Text("close")
                    .font(.system(size: 10))
                    .foregroundStyle(palette.labelTertiary)
            }
            Spacer()
            Text("\(tabs.count) tab\(tabs.count == 1 ? "" : "s") · \(bookmarkStore.bookmarks.count) bookmark\(bookmarkStore.bookmarks.count == 1 ? "" : "s")")
                .font(.system(size: 10))
                .foregroundStyle(palette.labelTertiary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.87))
        .overlay(
            Rectangle()
                .fill(Color.white.opacity(0.35))
                .frame(height: 1),
            alignment: .top
        )
    }

    private func kbdChip(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(palette.labelSecondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(palette.stroke, lineWidth: 1)
                    )
            )
    }

    // MARK: - Key handling

    @discardableResult
    private func handleNavKey(_ press: KeyPress) -> KeyPress.Result {
        let isCtrl  = press.modifiers == .control
        let isPlain = press.modifiers.isEmpty

        let goNext = (isCtrl && press.key == KeyEquivalent("n"))
                  || (isPlain && press.key == .downArrow)
        let goPrev = (isCtrl && press.key == KeyEquivalent("p"))
                  || (isPlain && press.key == .upArrow)

        let count = allItems.count
        guard count > 0 else { return .ignored }

        if goNext {
            selectedIndex = min((selectedIndex ?? -1) + 1, count - 1)
            return .handled
        }
        if goPrev {
            guard let idx = selectedIndex else { return .ignored }
            selectedIndex = idx > 0 ? idx - 1 : nil
            return .handled
        }
        return .ignored
    }

    private func activateSelected() {
        let items = allItems
        if let idx = selectedIndex, idx < items.count {
            activate(items[idx])
        } else if let first = items.first {
            activate(first)
        }
    }

    private func activate(_ item: FinderItem) {
        switch item {
        case .tab(let t):        onSelect(t.id)
        case .bookmark(let b):   onCreate(b.urlString)
        case .history(let h):    onCreate(h.urlString)
        case .openURL(let q):    onCreate(q)
        }
    }
}
