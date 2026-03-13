import SwiftUI

struct WorkspaceManagerView: View {
    @ObservedObject var store: WorkspaceStore
    @Environment(\.dismiss) private var dismiss

    @State private var newName = ""
    @State private var newEmoji = "🌐"
    @State private var editingID: UUID? = nil

    private let bg    = Color.white
    private let row   = Color(red: 0.96, green: 0.96, blue: 0.97)
    private let label = Color(red: 0.08, green: 0.08, blue: 0.10)
    private let sec   = Color(red: 0.08, green: 0.08, blue: 0.10).opacity(0.45)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            workspaceList
            Divider()
            createRow
        }
        .frame(width: 360)
        .background(bg)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 24, y: 8)
    }

    private var header: some View {
        HStack {
            Text("Workspaces")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(label)
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(sec)
                    .frame(width: 20, height: 20)
                    .background(Color.black.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var workspaceList: some View {
        ScrollView {
            VStack(spacing: 4) {
                // "All Tabs" row
                workspaceRow(
                    id: nil, emoji: "⊞", name: "All Tabs",
                    isActive: store.activeWorkspaceID == nil
                )
                ForEach(store.workspaces) { ws in
                    workspaceRow(id: ws.id, emoji: ws.emoji, name: ws.name,
                                 isActive: store.activeWorkspaceID == ws.id)
                }
            }
            .padding(8)
        }
        .frame(maxHeight: 300)
    }

    private func workspaceRow(id: UUID?, emoji: String, name: String, isActive: Bool) -> some View {
        HStack(spacing: 10) {
            Text(emoji).font(.system(size: 16))
                .frame(width: 30, height: 30)
                .background(isActive ? Color.black.opacity(0.07) : row,
                             in: RoundedRectangle(cornerRadius: 8))

            Text(name)
                .font(.system(size: 13, weight: isActive ? .semibold : .regular))
                .foregroundStyle(label)

            Spacer()

            if isActive {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }

            if let id {
                Button {
                    store.delete(id)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundStyle(sec)
                        .frame(width: 24, height: 24)
                        .background(Color.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            isActive ? Color.black.opacity(0.04) : Color.clear,
            in: RoundedRectangle(cornerRadius: 10)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            store.switchTo(id)
            dismiss()
        }
    }

    private var createRow: some View {
        HStack(spacing: 8) {
            TextField("＋ New workspace", text: $newName)
                .font(.system(size: 13))
                .foregroundStyle(label)
                .textFieldStyle(.plain)
                .onSubmit { createWorkspace() }

            Spacer()

            EmojiPicker(emoji: $newEmoji)

            Button("Add") { createWorkspace() }
                .font(.system(size: 12, weight: .semibold))
                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private func createWorkspace() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let ws = store.create(name: name, emoji: newEmoji)
        store.switchTo(ws.id)
        newName = ""
        newEmoji = "🌐"
        dismiss()
    }
}

// Minimal inline emoji picker
private struct EmojiPicker: View {
    @Binding var emoji: String
    private let options = ["🌐", "💼", "🏠", "📚", "🎮", "🎵", "🛒", "✈️", "🔬", "💡"]

    var body: some View {
        Menu {
            ForEach(options, id: \.self) { e in
                Button(e) { emoji = e }
            }
        } label: {
            Text(emoji).font(.system(size: 16))
                .frame(width: 30, height: 30)
                .background(Color.black.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
        }
        .menuStyle(.borderlessButton)
        .frame(width: 36)
    }
}
