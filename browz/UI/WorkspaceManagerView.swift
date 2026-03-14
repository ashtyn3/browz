import SwiftUI

struct WorkspaceManagerView: View {
    @ObservedObject var store: WorkspaceStore
    let onDismiss: () -> Void

    @State private var newName = ""
    @State private var newEmoji = "🌐"
    @FocusState private var isCreateFocused: Bool

    private let palette: FinderPalette

    init(store: WorkspaceStore, pageTint: PageTint? = nil, onDismiss: @escaping () -> Void = {}) {
        self.store = store
        self.onDismiss = onDismiss
        self.palette = FinderPalette.make(pageTint: pageTint)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            workspaceList
            Divider().overlay(palette.divider)
            createSection
        }
        .frame(width: 380)
        .background(palette.background.opacity(0.90))
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(palette.stroke, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 32, y: 14)
        .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Workspaces")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.labelPrimary)
                Text(store.workspaces.isEmpty
                     ? "No workspaces yet"
                     : "\(store.workspaces.count) workspace\(store.workspaces.count == 1 ? "" : "s")")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.labelSecondary)
            }
            Spacer()
            Button { onDismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(palette.labelSecondary)
                    .frame(width: 22, height: 22)
                    .background(Color.black.opacity(0.06), in: Circle())
            }
            .buttonStyle(.plain)
            .hoverElevated(cornerRadius: 11, baseOpacity: 0, hoverOpacity: 0.10)
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    // MARK: - List

    private var workspaceList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 2) {
                WorkspaceRow(
                    emoji: "⊞",
                    name: "All Tabs",
                    isActive: store.activeWorkspaceID == nil,
                    canDelete: false,
                    palette: palette,
                    onSelect: { store.switchTo(nil); onDismiss() },
                    onDelete: {}
                )

                if !store.workspaces.isEmpty {
                    Divider()
                        .overlay(palette.divider)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                }

                ForEach(store.workspaces) { ws in
                    WorkspaceRow(
                        emoji: ws.emoji,
                        name: ws.name,
                        isActive: store.activeWorkspaceID == ws.id,
                        canDelete: true,
                        palette: palette,
                        onSelect: { store.switchTo(ws.id); onDismiss() },
                        onDelete: { store.delete(ws.id) }
                    )
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
        .frame(maxHeight: 300)
    }

    // MARK: - Create section

    private var createSection: some View {
        HStack(spacing: 10) {
            WorkspaceEmojiPicker(emoji: $newEmoji)

            TextField("New workspace…", text: $newName)
                .font(.system(size: 13))
                .foregroundStyle(palette.labelPrimary)
                .textFieldStyle(.plain)
                .focused($isCreateFocused)
                .onSubmit { createWorkspace() }

            if !newName.trimmingCharacters(in: .whitespaces).isEmpty {
                Button { createWorkspace() } label: {
                    Image(systemName: "return")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
                .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .animation(.spring(response: 0.22, dampingFraction: 0.82), value: newName.isEmpty)
    }

    // MARK: - Actions

    private func createWorkspace() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let ws = store.create(name: name, emoji: newEmoji)
        store.switchTo(ws.id)
        newName = ""
        newEmoji = "🌐"
        isCreateFocused = false
        onDismiss()
    }
}

// MARK: - Row

private struct WorkspaceRow: View {
    let emoji: String
    let name: String
    let isActive: Bool
    let canDelete: Bool
    let palette: FinderPalette
    let onSelect: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 0) {
            // Active indicator bar
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(isActive ? Color.accentColor : Color.clear)
                .frame(width: 3, height: 22)
                .padding(.trailing, 9)
                .animation(.spring(response: 0.25, dampingFraction: 0.85), value: isActive)

            // Emoji bubble
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isActive ? Color.accentColor.opacity(0.13) : palette.input)
                    .frame(width: 34, height: 34)
                    .animation(.easeOut(duration: 0.15), value: isActive)
                Text(emoji).font(.system(size: 16))
            }

            // Name
            Text(name)
                .font(.system(size: 13, weight: isActive ? .medium : .regular))
                .foregroundStyle(palette.labelPrimary)
                .lineLimit(1)
                .padding(.leading, 11)

            Spacer()

            // Active checkmark
            if isActive {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.accentColor)
                    .padding(.trailing, canDelete ? 8 : 0)
                    .transition(.scale(scale: 0.7).combined(with: .opacity))
            }

            // Delete — only on hover
            if canDelete && isHovered {
                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(palette.labelSecondary)
                        .frame(width: 20, height: 20)
                        .background(Color.black.opacity(0.07), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isActive
                      ? Color.accentColor.opacity(0.07)
                      : (isHovered ? palette.rowHover : Color.clear))
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture { onSelect() }
        .animation(.easeOut(duration: 0.11), value: isHovered)
        .animation(.spring(response: 0.25, dampingFraction: 0.85), value: isActive)
    }
}

// MARK: - Emoji picker

private struct WorkspaceEmojiPicker: View {
    @Binding var emoji: String
    private let options = ["🌐", "💼", "🏠", "📚", "🎮", "🎵", "🛒", "✈️", "🔬", "💡", "🎨", "🏋️", "🍕", "💻", "🔒"]

    var body: some View {
        Menu {
            ForEach(options, id: \.self) { e in
                Button(e) { emoji = e }
            }
        } label: {
            Text(emoji)
                .font(.system(size: 16))
                .frame(width: 34, height: 34)
                .background(Color.black.opacity(0.05), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .menuStyle(.borderlessButton)
        .frame(width: 34)
    }
}
