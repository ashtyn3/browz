import Foundation

/// Lightweight, hashable representation of a page-derived tint color.
/// Stored on `TabState` but not persisted across launches.
struct PageTint: Hashable {
    let r: Double
    let g: Double
    let b: Double
    /// Whether the sampled page is overall dark; used to adjust UI contrast.
    let isDark: Bool
}

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
    /// Per-tab page tint sampled from content; not persisted.
    var pageTint: PageTint?

    init(
        id: UUID = UUID(),
        title: String = "New Tab",
        urlString: String = "about:blank",
        isPinned: Bool = false,
        lastAccessedAt: Date = .now,
        lifecycle: TabLifecycle = .active,
        isPrivate: Bool = false,
        workspaceID: UUID? = nil,
        pageTint: PageTint? = nil
    ) {
        self.id = id
        self.title = title
        self.urlString = urlString
        self.isPinned = isPinned
        self.lastAccessedAt = lastAccessedAt
        self.lifecycle = lifecycle
        self.isPrivate = isPrivate
        self.workspaceID = workspaceID
        self.pageTint = pageTint
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
        pageTint       = nil
    }

    var resolvedURL: URL? {
        BrowserSettings.shared.resolve(input: urlString)
    }
}

struct PersistedTabSession: Codable {
    var tabs: [TabState]
    var selectedTabID: UUID?
}
