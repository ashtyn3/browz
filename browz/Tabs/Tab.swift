import Foundation

enum TabLifecycle: String, Codable {
    case active
    case suspended
    case discarded
}

struct TabState: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var urlString: String
    var isPinned: Bool
    var lastAccessedAt: Date
    var lifecycle: TabLifecycle
    /// Not persisted — private tabs never survive across sessions.
    var isPrivate: Bool
    /// Which workspace this tab belongs to (nil = default / all-tabs view).
    var workspaceID: UUID?

    init(
        id: UUID = UUID(),
        title: String = "New Tab",
        urlString: String = "about:blank",
        isPinned: Bool = false,
        lastAccessedAt: Date = .now,
        lifecycle: TabLifecycle = .active,
        isPrivate: Bool = false,
        workspaceID: UUID? = nil
    ) {
        self.id = id
        self.title = title
        self.urlString = urlString
        self.isPinned = isPinned
        self.lastAccessedAt = lastAccessedAt
        self.lifecycle = lifecycle
        self.isPrivate = isPrivate
        self.workspaceID = workspaceID
    }

    // MARK: Codable — isPrivate excluded (always false on decode)

    enum CodingKeys: String, CodingKey {
        case id, title, urlString, isPinned, lastAccessedAt, lifecycle, workspaceID
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id             = try c.decode(UUID.self,         forKey: .id)
        title          = try c.decode(String.self,       forKey: .title)
        urlString      = try c.decode(String.self,       forKey: .urlString)
        isPinned       = try c.decode(Bool.self,         forKey: .isPinned)
        lastAccessedAt = try c.decode(Date.self,         forKey: .lastAccessedAt)
        lifecycle      = try c.decode(TabLifecycle.self, forKey: .lifecycle)
        workspaceID    = try c.decodeIfPresent(UUID.self, forKey: .workspaceID)
        isPrivate      = false
    }

    var resolvedURL: URL? {
        BrowserSettings.shared.resolve(input: urlString)
    }
}

struct PersistedTabSession: Codable {
    var tabs: [TabState]
    var selectedTabID: UUID?
}
