import SwiftUI
import AppKit

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
    @State private var selectedIndex: Int? = nil
    @State private var keyMonitor: Any? = nil
    @FocusState private var isFocused: Bool

    private static let notifNext = Notification.Name("browz.finder.selectNext")
    private static let notifPrev = Notification.Name("browz.finder.selectPrev")

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
                .foregroundStyle(iconTint)
                .frame(width: 20)

            TextField("Find tab or search web…", text: $query)
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
        let tabOffset = 0

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
        .hoverElevated(cornerRadius: 10, baseOpacity: 0.0, hoverOpacity: 0.10)
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
