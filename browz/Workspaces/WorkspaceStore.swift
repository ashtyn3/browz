import Foundation
import Combine

@MainActor
final class WorkspaceStore: ObservableObject {
    @Published private(set) var workspaces: [Workspace] = []
    @Published var activeWorkspaceID: UUID? = nil   // nil = show all tabs

    private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AOB", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("workspaces.json")
    }()

    init() { load() }

    var activeWorkspace: Workspace? {
        workspaces.first { $0.id == activeWorkspaceID }
    }

    @discardableResult
    func create(name: String, emoji: String = "🌐") -> Workspace {
        let ws = Workspace(name: name, emoji: emoji)
        workspaces.append(ws)
        save()
        return ws
    }

    func delete(_ id: UUID) {
        workspaces.removeAll { $0.id == id }
        if activeWorkspaceID == id { activeWorkspaceID = nil }
        save()
    }

    func rename(_ id: UUID, name: String, emoji: String) {
        guard let idx = workspaces.firstIndex(where: { $0.id == id }) else { return }
        workspaces[idx].name = name
        workspaces[idx].emoji = emoji
        save()
    }

    func switchTo(_ id: UUID?) {
        activeWorkspaceID = id
    }

    func switchToNext() {
        let ids: [UUID?] = [nil] + workspaces.map(\.id)
        guard let current = ids.firstIndex(where: { $0 == activeWorkspaceID }),
              current + 1 < ids.count else {
            activeWorkspaceID = nil
            return
        }
        activeWorkspaceID = ids[current + 1]
    }

    func switchToPrev() {
        let ids: [UUID?] = [nil] + workspaces.map(\.id)
        guard let current = ids.firstIndex(where: { $0 == activeWorkspaceID }),
              current > 0 else { return }
        activeWorkspaceID = ids[current - 1]
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([Workspace].self, from: data) else { return }
        workspaces = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(workspaces) else { return }
        try? data.write(to: fileURL)
    }
}
