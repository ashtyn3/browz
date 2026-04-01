import SwiftUI

struct TabSidebarView: View {
    let tabs: [TabState]
    let selectedTabID: UUID?
    let splitTabID: UUID?

    let onSelect: (UUID) -> Void
    let onClose: (UUID) -> Void
    let onTogglePin: (UUID) -> Void

    private let sidebarBg  = Color(red: 0.96, green: 0.96, blue: 0.97)
    private let activeBg   = Color.black.opacity(0.07)
    private let hoverBg    = Color.black.opacity(0.03)
    private let labelColor = Color(red: 0.08, green: 0.08, blue: 0.10)
    private let secondary  = Color(red: 0.08, green: 0.08, blue: 0.10).opacity(0.55)

    @State private var hoveredID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            list
                .padding(.top, 48)
        }
        .frame(width: 204)
        .frame(maxHeight: .infinity)
        .background(.ultraThinMaterial)
        .overlay(
            Rectangle()
                .fill(Color.black.opacity(0.1))
                .frame(width: 1),
            alignment: .trailing
        )
    }

    private var trafficLightsRow: some View {
        HStack(spacing: 6) {
            // Reserve space for the real macOS traffic lights; they are
            // actually attached to the NSWindow titlebar and visually
            // overlap this area when the sidebar is visible.
            Color.clear.frame(width: 80, height: 32)
            Spacer()
        }
        .padding(.horizontal, 8)
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: 2) {
                ForEach(tabs, id: \.id) { tab in
                    row(for: tab)
                }
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 8)
        }
    }

    private func row(for tab: TabState) -> some View {
        let isActive = tab.id == selectedTabID

        return HStack(spacing: 8) {
            Text(tab.title.isEmpty ? tab.urlString : tab.title)
                .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                .foregroundStyle(isActive ? labelColor : secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            if hoveredID == tab.id {
                HStack(spacing: 4) {
                    Button {
                        onTogglePin(tab.id)
                    } label: {
                        Image(systemName: tab.isPinned ? "pin.slash" : "pin")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(secondary)
                            .frame(width: 16, height: 16)
                    }
                    .buttonStyle(.plain)

                    Button {
                        onClose(tab.id)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(secondary)
                            .frame(width: 16, height: 16)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isActive ? activeBg : (hoveredID == tab.id ? hoverBg : Color.clear))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect(tab.id)
        }
        .onHover { over in
            hoveredID = over ? tab.id : nil
        }
    }
}

