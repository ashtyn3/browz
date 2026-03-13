import Foundation

struct BookmarkEntry: Identifiable, Codable {
    let id: UUID
    var title: String
    var urlString: String
    let savedAt: Date

    init(id: UUID = UUID(), title: String, urlString: String, savedAt: Date = .now) {
        self.id = id
        self.title = title
        self.urlString = urlString
        self.savedAt = savedAt
    }
}
