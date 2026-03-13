import Foundation
import Combine

@MainActor
final class BookmarkStore: ObservableObject {
    @Published private(set) var bookmarks: [BookmarkEntry] = []

    private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AOB", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("bookmarks.json")
    }()

    init() { load() }

    func add(title: String, urlString: String) {
        guard !contains(urlString: urlString) else { return }
        bookmarks.append(BookmarkEntry(title: title, urlString: urlString))
        save()
    }

    func remove(id: UUID) {
        bookmarks.removeAll { $0.id == id }
        save()
    }

    func removeByURL(_ urlString: String) {
        bookmarks.removeAll { $0.urlString == urlString }
        save()
    }

    func contains(urlString: String) -> Bool {
        bookmarks.contains { $0.urlString == urlString }
    }

    func search(query: String) -> [BookmarkEntry] {
        guard !query.isEmpty else { return bookmarks }
        let q = query.lowercased()
        return bookmarks.filter {
            $0.title.lowercased().contains(q) || $0.urlString.lowercased().contains(q)
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([BookmarkEntry].self, from: data) else { return }
        bookmarks = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(bookmarks) else { return }
        try? data.write(to: fileURL)
    }
}
