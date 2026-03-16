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
    /// Optional callback to reorder tabs in the owning store.
    /// The first ID is the dragged tab, the second is the tab it should appear before.
    let onMoveTab: ((UUID, UUID) -> Void)?
    /// The secondary split tab ID, if a split is currently active.
    var splitTabID: UUID? = nil
    /// Called with the ejected tab's ID when the user drags it out of the split group.
    let onBreakSplit: ((UUID) -> Void)?

    private let palette: FinderPalette

    @State private var query: String = ""
    @State private var hoveredTabID: UUID? = nil
    @State private var selectedIndex: Int? = nil
    @State private var keyMonitor: Any? = nil
    @State private var draggingTabID: UUID? = nil
    @State private var dragOrder: [UUID]? = nil
    @State private var reorderHoveredTabID: UUID? = nil
    @FocusState private var isFocused: Bool
    /// Horizontal drag offset per split-tab row (for the eject gesture).
    @State private var splitDragOffsets: [UUID: CGFloat] = [:]
    /// The tab currently mid-eject (animating out).
    @State private var splitEjectingID: UUID? = nil

    private static let notifNext = Notification.Name("browz.finder.selectNext")
    private static let notifPrev = Notification.Name("browz.finder.selectPrev")
    /// Horizontal drag distance required to eject a split tab.
    private static let ejectThreshold: CGFloat = 72

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
        pageTint: PageTint? = nil,
        onMoveTab: ((UUID, UUID) -> Void)? = nil,
        splitTabID: UUID? = nil,
        onBreakSplit: ((UUID) -> Void)? = nil
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
        self.onMoveTab = onMoveTab
        self.splitTabID = splitTabID
        self.onBreakSplit = onBreakSplit
        self.palette = FinderPalette.make(pageTint: pageTint)
    }

    // MARK: - Computed lists

    private var rankedTabs: [TabState] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        // When there's no search query, keep the order identical to the tab strip
        // (or the in-progress drag order) so reordering feels predictable.
        guard !trimmed.isEmpty else {
            if let dragOrder {
                let byID = Dictionary(uniqueKeysWithValues: tabs.map { ($0.id, $0) })
                return dragOrder.compactMap { byID[$0] }
            }
            return tabs
        }

        let scored: [(TabState, Int)] = tabs.map { tab in
            let haystack = "\(tab.title) \(tab.urlString)"
            let base = FuzzyMatch.score(query: trimmed, candidate: haystack)
            let recencyBonus = Int(Date.now.timeIntervalSince(tab.lastAccessedAt) * -0.01)
            return (tab, base + recencyBonus)
        }
        let filtered = scored.filter { $0.1 > 0 }
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
        .background(Color.white.opacity(0.80))
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.10), radius: 30, y: 12)
        .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
        .onAppear {
            if !allItems.isEmpty {
                // Start selection on the current tab so Ctrl+N / Ctrl+P first move is relative to it.
                let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    if splitTabID != nil {
                        selectedIndex = 3 // first row of flatList (after split card)
                    } else if let idx = rankedTabs.firstIndex(where: { $0.id == selectedTabID }) {
                        selectedIndex = idx
                    } else {
                        selectedIndex = 0
                    }
                } else {
                    selectedIndex = 0
                }
            }
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
                .onChange(of: query) {
                    selectedIndex = nil
                    draggingTabID = nil
                    dragOrder = nil
                }
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
        let trimmed   = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let isSearching = !trimmed.isEmpty
        let canReorder = !isSearching && onMoveTab != nil

        // When query is empty and a split is active, separate the pair from the rest.
        let showSplitCard = !isSearching && splitTabID != nil
        let splitIDs: Set<UUID> = showSplitCard
            ? [selectedTabID, splitTabID].compactMap { $0 }.reduce(into: Set()) { $0.insert($1) }
            : []
        let primaryTab   = showSplitCard ? tabs.first(where: { $0.id == selectedTabID }) : nil
        let secondaryTab = showSplitCard ? tabs.first(where: { $0.id == splitTabID })    : nil

        let flatList: [TabState] = {
            let base = rankedTabs
            if showSplitCard { return base.filter { !splitIDs.contains($0.id) } }
            return base
        }()

        // Row count accounts for the split card (counts as 2 rows + extra padding).
        let splitCardRows: Int = (primaryTab != nil || secondaryTab != nil) ? 3 : 0
        let rowCount = (flatList.isEmpty && isSearching) ? 1 : flatList.count + splitCardRows
        let contentHeight = CGFloat(rowCount) * Self.rowHeight + Self.listVerticalPadding
        let listHeight = min(contentHeight, Self.listMaxHeight)

        // Flat-list index offset so keyboard selectedIndex still works.
        let indexOffset = splitCardRows

        return ScrollView {
            LazyVStack(spacing: 2) {
                if let primary = primaryTab {
                    splitPairCard(primary: primary, secondary: secondaryTab)
                        .padding(.bottom, 4)
                }
                if !flatList.isEmpty {
                    ForEach(Array(flatList.enumerated()), id: \.element.id) { i, tab in
                        tabRow(tab, listIndex: i + indexOffset, canReorder: canReorder)
                    }
                }
                if flatList.isEmpty && !query.isEmpty {
                    openURLRow
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            // Spring-animate rows into new positions as drag order changes.
            .animation(.spring(response: 0.28, dampingFraction: 0.82), value: dragOrder)
            // Single gesture on the whole container — never invalidated by row reordering.
            .gesture(canReorder ? listReorderGesture : nil)
        }
        .frame(height: listHeight)
    }

    // MARK: - Drag-to-reorder (container-level gesture)

    /// Row height + LazyVStack row spacing = one slot.
    private static let slotHeight: CGFloat = rowHeight + 2

    /// Convert a Y coordinate (local to the LazyVStack including its padding) into a row index.
    private func rowSlot(_ y: CGFloat, count: Int) -> Int {
        let adjusted = y - 8                     // subtract top padding
        let raw = Int(adjusted / Self.slotHeight)
        return min(max(raw, 0), count - 1)
    }

    private var listReorderGesture: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .local)
            .onChanged { value in
                let current = rankedTabs    // always reads current dragOrder when set
                guard !current.isEmpty else { return }

                if draggingTabID == nil {
                    // First event — pick up the row under the finger.
                    let idx = rowSlot(value.startLocation.y, count: current.count)
                    draggingTabID = current[idx].id
                    dragOrder     = current.map(\.id)
                    NSCursor.closedHand.push()
                }

                guard let dragID = draggingTabID,
                      var order  = dragOrder else { return }

                let targetIdx   = rowSlot(value.location.y, count: order.count)
                guard let fromIdx = order.firstIndex(of: dragID),
                      targetIdx != fromIdx else { return }

                order.remove(at: fromIdx)
                order.insert(dragID, at: targetIdx)
                dragOrder = order
            }
            .onEnded { _ in
                commitDragOrder()
            }
    }

    private func commitDragOrder() {
        defer {
            draggingTabID = nil
            dragOrder     = nil
            NSCursor.pop()   // restore open-hand / arrow
        }
        guard let onMoveTab, let finalOrder = dragOrder else { return }

        // Walk left-to-right, calling moveTab for each element not yet in place.
        // Simulate the same moves on a local copy so sibling IDs stay correct.
        var sim = tabs.map(\.id)
        for (i, finalID) in finalOrder.enumerated() {
            guard let fromIdx = sim.firstIndex(of: finalID), fromIdx != i else { continue }
            sim.remove(at: fromIdx)
            sim.insert(finalID, at: i)
            // "move finalID before the tab currently sitting at i+1"
            guard i + 1 < sim.count else { continue }
            onMoveTab(finalID, sim[i + 1])
        }
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

    // MARK: - Split pair card

    private func splitPairCard(primary: TabState, secondary: TabState?) -> some View {
        VStack(spacing: 0) {
            splitTabRow(primary)
            if let secondary {
                splitDivider
                splitTabRow(secondary)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(accentBar.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(accentBar.opacity(0.22), lineWidth: 1)
        )
    }

    private var splitDivider: some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(accentBar.opacity(0.15))
                .frame(height: 1)

            // Badge sits in the middle of the divider, not over any tab content
            HStack(spacing: 3) {
                Image(systemName: "rectangle.split.2x1")
                    .font(.system(size: 9, weight: .semibold))
                Text("Split")
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(accentBar.opacity(0.50))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(accentBar.opacity(0.07))
                    .overlay(Capsule().strokeBorder(accentBar.opacity(0.15), lineWidth: 0.5))
            )
            .fixedSize()

            Rectangle()
                .fill(accentBar.opacity(0.15))
                .frame(height: 1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    private func splitTabRow(_ tab: TabState) -> some View {
        let offset = splitDragOffsets[tab.id] ?? 0
        let absOffset = abs(offset)
        let isEjecting = splitEjectingID == tab.id
        let isHov = hoveredTabID == tab.id
        let isAct = tab.id == selectedTabID

        return ZStack(alignment: .center) {
            // "drag to break split" hint — fades in as the user drags
            if absOffset > 6 {
                Text("drag to break split")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(accentBar.opacity(min(Double(absOffset) / Double(Self.ejectThreshold), 0.55)))
                    .allowsHitTesting(false)
            }

            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isAct ? accentBar.opacity(0.10) : palette.input)
                        .frame(width: 32, height: 32)
                    FaviconView(
                        urlString: tab.urlString,
                        isPrivate: tab.isPrivate,
                        fallbackColor: isAct ? accentBar : (tab.isPrivate ? privateColor.opacity(0.55) : palette.labelTertiary)
                    )
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(tab.title)
                        .font(.system(size: 13, weight: isAct ? .semibold : .medium))
                        .foregroundStyle(isAct ? accentBar : palette.labelPrimary)
                        .lineLimit(1)
                    Text(tab.urlString)
                        .font(.system(size: 11))
                        .foregroundStyle(palette.labelSecondary)
                        .lineLimit(1)
                }

                Spacer()

                if isHov {
                    HStack(spacing: 4) {
                        rowAction(icon: tab.isPinned ? "pin.slash" : "pin") { onTogglePin(tab.id) }
                        rowAction(icon: "xmark") { onClose(tab.id) }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .offset(x: isEjecting ? (offset > 0 ? 320 : -320) : offset)
        .rotationEffect(.degrees(Double(offset) * 0.04))
        .scaleEffect(1.0 - min(absOffset / 600, 0.05))
        .opacity(isEjecting ? 0 : 1)
        .animation(isEjecting
            ? .spring(response: 0.3, dampingFraction: 0.75)
            : .interactiveSpring(response: 0.25, dampingFraction: 0.8),
                   value: isEjecting ? 1.0 : Double(offset))
        .onHover { over in
            hoveredTabID = over ? tab.id : nil
            if over { NSCursor.openHand.push() } else { NSCursor.pop() }
        }
        .onTapGesture { onSelect(tab.id) }
        .gesture(
            DragGesture(minimumDistance: 10, coordinateSpace: .local)
                .onChanged { value in
                    let dx = value.translation.width
                    splitDragOffsets[tab.id] = dx
                }
                .onEnded { value in
                    let dx = value.translation.width
                    if abs(dx) >= Self.ejectThreshold {
                        // Commit the eject: fly out then break.
                        splitEjectingID = tab.id
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
                            onBreakSplit?(tab.id)
                            splitEjectingID = nil
                            splitDragOffsets[tab.id] = nil
                        }
                    } else {
                        // Snap back.
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.65)) {
                            splitDragOffsets[tab.id] = nil
                        }
                    }
                }
        )
    }

    // MARK: - Tab row

    private func tabRow(_ tab: TabState, listIndex: Int, canReorder: Bool = false) -> some View {
        let isActive        = tab.id == selectedTabID
        let isHovered       = hoveredTabID == tab.id
        let isSel           = selectedIndex == listIndex
        let isDragging      = draggingTabID == tab.id
        let anyDragging     = draggingTabID != nil
        let showHandle      = canReorder && isHovered && !anyDragging
        let rowAccent       = tab.isPrivate ? privateColor : accentBar

        return HStack(spacing: 12) {
            // Drag handle / favicon slot
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isActive ? rowAccent.opacity(0.10) : palette.input)
                    .frame(width: 32, height: 32)
                if showHandle {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(palette.labelTertiary)
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                } else {
                    FaviconView(
                        urlString: tab.urlString,
                        isPrivate: tab.isPrivate,
                        fallbackColor: isActive ? rowAccent : (tab.isPrivate ? privateColor.opacity(0.55) : palette.labelTertiary)
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }
            }
            .animation(.easeInOut(duration: 0.15), value: showHandle)

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
                if (isHovered || isActive || isSel) && !anyDragging {
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
                .fill(isDragging
                    ? Color.white.opacity(0.92)
                    : rowBg(isActive: isActive, isSel: isSel, isHovered: isHovered))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    isDragging
                        ? Color.black.opacity(0.06)
                        : (isActive ? rowAccent.opacity(0.18) : Color.clear),
                    lineWidth: 1
                )
        )
        .shadow(
            color: isDragging ? .black.opacity(0.10) : .clear,
            radius: isDragging ? 12 : 0,
            y: isDragging ? 4 : 0
        )
        .scaleEffect(isDragging ? 1.02 : 1.0)
        .opacity(anyDragging && !isDragging ? 0.75 : 1.0)
        .animation(.spring(response: 0.22, dampingFraction: 0.75), value: isDragging)
        .contentShape(Rectangle())
        .onHover { over in
            hoveredTabID = over ? tab.id : nil
            if canReorder {
                if over { NSCursor.openHand.push() } else { NSCursor.pop() }
            }
        }
        .onTapGesture { onSelect(tab.id) }
        .hoverElevated(cornerRadius: 10, baseOpacity: 0.0, hoverOpacity: isDragging ? 0.0 : 0.10)
        .zIndex(isDragging ? 1 : 0)
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
        .background(Color.white.opacity(0.80))
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
