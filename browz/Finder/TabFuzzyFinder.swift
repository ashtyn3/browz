import SwiftUI

// MARK: - Palette tokens
private let paletteBg       = Color.white
private let paletteInput    = Color(red: 0.96, green: 0.96, blue: 0.97)
private let paletteStroke   = Color.black.opacity(0.08)
private let paletteDivider  = Color.black.opacity(0.06)
private let accentBar       = Color(red: 0.20, green: 0.20, blue: 0.22)
private let rowHover        = Color(red: 0.95, green: 0.95, blue: 0.96)
private let rowSelected     = Color(red: 0.92, green: 0.92, blue: 0.94)
private let labelPrimary    = Color(red: 0.08, green: 0.08, blue: 0.10)
private let labelSecondary  = Color(red: 0.08, green: 0.08, blue: 0.10).opacity(0.45)
private let labelTertiary   = Color(red: 0.08, green: 0.08, blue: 0.10).opacity(0.28)
private let iconTint        = Color(red: 0.40, green: 0.40, blue: 0.44)
private let privateColor    = Color(red: 0.38, green: 0.28, blue: 0.68)

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

    @State private var query: String = ""
    @State private var hoveredTabID: UUID? = nil
    @State private var hoveredHistoryID: UUID? = nil
    @State private var selectedIndex: Int? = nil
    @FocusState private var isFocused: Bool

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

    private var bookmarkResults: [BookmarkEntry] {
        let openURLs = Set(tabs.map(\.urlString))
        return bookmarkStore.search(query: query).filter { !openURLs.contains($0.urlString) }
    }

    private var historyResults: [HistoryEntry] {
        guard !query.isEmpty else { return [] }
        let openURLs = Set(tabs.map(\.urlString))
        let bookmarkedURLs = Set(bookmarkStore.bookmarks.map(\.urlString))
        return historyStore.search(query: query)
            .filter { !openURLs.contains($0.urlString) && !bookmarkedURLs.contains($0.urlString) }
    }

    private var allItems: [FinderItem] {
        var items: [FinderItem] = rankedTabs.map { .tab($0) }
        items += bookmarkResults.map { .bookmark($0) }
        items += historyResults.map { .history($0) }
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
                        .foregroundStyle(labelSecondary)
                    Text(label)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(labelSecondary)
                    Spacer()
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 9)
                .background(Color.black.opacity(0.025))
                Divider().overlay(paletteDivider)
            }
            searchBar
            Divider().overlay(paletteDivider)
            resultsList
            footer
        }
        .frame(width: 580)
        .background(paletteBg)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(paletteStroke, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.10), radius: 30, y: 12)
        .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
        .onAppear { isFocused = true }
    }

    // MARK: - Search bar

    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(iconTint)
                .frame(width: 20)

            TextField("Search tabs, history, type a URL…", text: $query)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(labelPrimary)
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
                        .foregroundStyle(labelTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
    }

    // MARK: - Results

    private var resultsList: some View {
        let tabList   = rankedTabs
        let bkList    = bookmarkResults
        let histList  = historyResults
        let tabOffset = 0
        let bkOffset  = tabList.count
        let histOffset = tabList.count + bkList.count
        let multiSection = [!tabList.isEmpty, !bkList.isEmpty, !histList.isEmpty].filter { $0 }.count > 1

        return ScrollView {
            LazyVStack(spacing: 2) {
                if !tabList.isEmpty {
                    if multiSection { sectionLabel("Open Tabs") }
                    ForEach(Array(tabList.enumerated()), id: \.element.id) { i, tab in
                        tabRow(tab, listIndex: tabOffset + i)
                    }
                }

                if !bkList.isEmpty {
                    sectionLabel("Bookmarks").padding(.top, tabList.isEmpty ? 0 : 6)
                    ForEach(Array(bkList.enumerated()), id: \.element.id) { i, bk in
                        bookmarkRow(bk, listIndex: bkOffset + i)
                    }
                }

                if !histList.isEmpty {
                    sectionLabel("History").padding(.top, (tabList.isEmpty && bkList.isEmpty) ? 0 : 6)
                    ForEach(Array(histList.enumerated()), id: \.element.id) { i, entry in
                        historyRow(entry, listIndex: histOffset + i)
                    }
                }

                if tabList.isEmpty && bkList.isEmpty && histList.isEmpty && !query.isEmpty {
                    openURLRow
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        }
        .frame(maxHeight: 460)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(labelTertiary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var openURLRow: some View {
        let isSelected = selectedIndex == 0
        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(paletteInput)
                    .frame(width: 32, height: 32)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(iconTint)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Open URL or search")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(labelPrimary)
                Text(query)
                    .font(.system(size: 11))
                    .foregroundStyle(labelSecondary)
                    .lineLimit(1)
            }

            Spacer()
            kbdChip("↵")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? rowSelected : rowHover)
        )
        .contentShape(Rectangle())
        .onTapGesture { onCreate(query) }
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
                    .fill(isActive ? rowAccent.opacity(0.10) : paletteInput)
                    .frame(width: 32, height: 32)
                Image(systemName: tab.isPrivate ? "shield.fill" : "globe")
                    .font(.system(size: 13))
                    .foregroundStyle(isActive ? rowAccent : (tab.isPrivate ? privateColor.opacity(0.55) : labelTertiary))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(tab.title)
                    .font(.system(size: 13, weight: isActive ? .semibold : .medium))
                    .foregroundStyle(isActive ? rowAccent : labelPrimary)
                    .lineLimit(1)
                Text(tab.urlString)
                    .font(.system(size: 11))
                    .foregroundStyle(labelSecondary)
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
                        .foregroundStyle(labelTertiary)
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
    }

    // MARK: - Bookmark row

    private func bookmarkRow(_ entry: BookmarkEntry, listIndex: Int) -> some View {
        let isHovered = hoveredHistoryID == entry.id
        let isSel     = selectedIndex == listIndex

        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(paletteInput)
                    .frame(width: 32, height: 32)
                Image(systemName: "star.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(red: 0.9, green: 0.65, blue: 0.1).opacity(0.8))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(labelPrimary)
                    .lineLimit(1)
                Text(entry.urlString)
                    .font(.system(size: 11))
                    .foregroundStyle(labelSecondary)
                    .lineLimit(1)
            }

            Spacer()
            if isHovered || isSel { kbdChip("↵") }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(rowBg(isActive: false, isSel: isSel, isHovered: isHovered))
        )
        .contentShape(Rectangle())
        .onHover { hoveredHistoryID = $0 ? entry.id : nil }
        .onTapGesture { onCreate(entry.urlString) }
    }

    // MARK: - History row

    private func historyRow(_ entry: HistoryEntry, listIndex: Int) -> some View {
        let isHovered = hoveredHistoryID == entry.id
        let isSel     = selectedIndex == listIndex

        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(paletteInput)
                    .frame(width: 32, height: 32)
                Image(systemName: "clock")
                    .font(.system(size: 12))
                    .foregroundStyle(labelTertiary)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(labelPrimary)
                    .lineLimit(1)
                Text(entry.urlString)
                    .font(.system(size: 11))
                    .foregroundStyle(labelSecondary)
                    .lineLimit(1)
            }

            Spacer()

            if isHovered || isSel {
                kbdChip("↵")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(rowBg(isActive: false, isSel: isSel, isHovered: isHovered))
        )
        .contentShape(Rectangle())
        .onHover { hoveredHistoryID = $0 ? entry.id : nil }
        .onTapGesture { onCreate(entry.urlString) }
    }

    private func rowBg(isActive: Bool, isSel: Bool, isHovered: Bool) -> Color {
        if isActive { return accentBar.opacity(0.07) }
        if isSel    { return rowSelected }
        if isHovered { return rowHover }
        return .clear
    }

    private func rowAction(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(labelSecondary)
                .frame(width: 24, height: 24)
                .background(paletteInput, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
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
                    .foregroundStyle(labelTertiary)
            }
            HStack(spacing: 4) {
                kbdChip("^N/P")
                Text("navigate")
                    .font(.system(size: 10))
                    .foregroundStyle(labelTertiary)
            }
            HStack(spacing: 4) {
                kbdChip("⌘W")
                Text("close")
                    .font(.system(size: 10))
                    .foregroundStyle(labelTertiary)
            }
            Spacer()
            Text("\(tabs.count) tab\(tabs.count == 1 ? "" : "s") · \(bookmarkStore.bookmarks.count) bookmark\(bookmarkStore.bookmarks.count == 1 ? "" : "s")")
                .font(.system(size: 10))
                .foregroundStyle(labelTertiary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color(red: 0.97, green: 0.97, blue: 0.98))
        .overlay(
            Rectangle()
                .fill(paletteDivider)
                .frame(height: 1),
            alignment: .top
        )
    }

    private func kbdChip(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(labelSecondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(paletteStroke, lineWidth: 1)
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
