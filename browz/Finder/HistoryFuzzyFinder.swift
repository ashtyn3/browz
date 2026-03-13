import SwiftUI
import AppKit

struct HistoryFuzzyFinder: View {
    let historyStore: HistoryStore
    var headerLabel: String? = nil
    let onCreate: (String) -> Void

    private let palette: FinderPalette

    @State private var query: String = ""
    @State private var hoveredID: UUID? = nil
    @State private var selectedIndex: Int? = nil
    @State private var keyMonitor: Any? = nil
    @FocusState private var isFocused: Bool

    private static let notifNext = Notification.Name("browz.historyFinder.selectNext")
    private static let notifPrev = Notification.Name("browz.historyFinder.selectPrev")

    init(
        historyStore: HistoryStore,
        headerLabel: String? = nil,
        pageTint: PageTint? = nil,
        onCreate: @escaping (String) -> Void
    ) {
        self.historyStore = historyStore
        self.headerLabel = headerLabel
        self.onCreate = onCreate
        self._query = State(initialValue: "")
        self._hoveredID = State(initialValue: nil)
        self._selectedIndex = State(initialValue: nil)
        self._keyMonitor = State(initialValue: nil)
        self._isFocused = FocusState()
        self.palette = FinderPalette.make(pageTint: pageTint)
    }

    private var results: [HistoryEntry] {
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return Array(historyStore.entries.prefix(40))
        }
        return historyStore.search(query: query, limit: 50)
    }

    private var hasOpenInNewTabRow: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && results.isEmpty
    }

    private var listCount: Int {
        results.count + (hasOpenInNewTabRow ? 1 : 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let label = headerLabel {
                HStack {
                    Image(systemName: "clock.arrow.circlepath")
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
            if listCount > 0 { selectedIndex = 0 }
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
            let count = listCount
            guard count > 0 else { return }
            selectedIndex = min((selectedIndex ?? -1) + 1, count - 1)
        }
        .onReceive(NotificationCenter.default.publisher(for: Self.notifPrev)) { _ in
            guard let idx = selectedIndex else { return }
            selectedIndex = idx > 0 ? idx - 1 : nil
        }
    }

    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(palette.iconTint)
                .frame(width: 20)

            TextField("Search history…", text: $query)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(palette.labelPrimary)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .onChange(of: query) { selectedIndex = nil }
                .onSubmit { activateSelected() }

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

    private var resultsList: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(Array(results.enumerated()), id: \.element.id) { i, entry in
                    historyRow(entry, listIndex: i)
                }
                if hasOpenInNewTabRow {
                    openInNewTabRow(listIndex: results.count)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        }
        .frame(maxHeight: 460)
    }

    private func historyRow(_ entry: HistoryEntry, listIndex: Int) -> some View {
        let isHovered = hoveredID == entry.id
        let isSel = selectedIndex == listIndex

        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(palette.input)
                    .frame(width: 32, height: 32)
                Image(systemName: "clock")
                    .font(.system(size: 12))
                    .foregroundStyle(palette.labelTertiary)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(palette.labelPrimary)
                    .lineLimit(1)
                Text(entry.urlString)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.labelSecondary)
                    .lineLimit(1)
            }

            Spacer()
            if isHovered || isSel { kbdChip("↵") }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSel ? palette.rowSelected : (isHovered ? palette.rowHover : Color.clear))
        )
        .contentShape(Rectangle())
        .onHover { hoveredID = $0 ? entry.id : nil }
        .onTapGesture {
            onCreate(entry.urlString)
        }
        .hoverElevated(cornerRadius: 10, baseOpacity: 0.0, hoverOpacity: 0.08)
    }

    private func openInNewTabRow(listIndex: Int) -> some View {
        let isSelected = selectedIndex == listIndex
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
                Text("Search web in new tab")
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

    private var footer: some View {
        HStack(spacing: 16) {
            HStack(spacing: 4) {
                kbdChip("↵")
                Text("open in new tab")
                    .font(.system(size: 10))
                    .foregroundStyle(palette.labelTertiary)
            }
            HStack(spacing: 4) {
                kbdChip("^N/P")
                Text("navigate")
                    .font(.system(size: 10))
                    .foregroundStyle(palette.labelTertiary)
            }
            Spacer()
            Text("\(historyStore.entries.count) in history")
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

    private func activateSelected() {
        if hasOpenInNewTabRow && selectedIndex == results.count {
            onCreate(query)
            return
        }
        if let idx = selectedIndex, idx < results.count {
            onCreate(results[idx].urlString)
            return
        }
        if let first = results.first {
            onCreate(first.urlString)
        } else if hasOpenInNewTabRow {
            onCreate(query)
        }
    }
}
