import Foundation
import Combine

@MainActor
final class HistoryStore: ObservableObject {
    @Published private(set) var entries: [HistoryEntry] = []

    private let maxEntries = 5_000
    private var saveTask: Task<Void, Never>?

    private static var fileURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = support.appendingPathComponent("com.local.aob")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.json")
    }

    init() {
        load()
    }

    // MARK: - Recording

    func record(title: String?, url: URL?) {
        guard let url,
              let scheme = url.scheme,
              ["http", "https"].contains(scheme) else { return }

        let urlString = url.absoluteString
        let resolvedTitle = title?.isEmpty == false ? title! : urlString

        if let index = entries.firstIndex(where: { $0.urlString == urlString }) {
            entries[index].title = resolvedTitle
            entries[index].visitedAt = .now
            // move to front
            let updated = entries.remove(at: index)
            entries.insert(updated, at: 0)
        } else {
            entries.insert(HistoryEntry(title: resolvedTitle, urlString: urlString, visitedAt: .now), at: 0)
            if entries.count > maxEntries {
                entries = Array(entries.prefix(maxEntries))
            }
        }

        scheduleSave()
    }

    func clear() {
        entries = []
        try? FileManager.default.removeItem(at: Self.fileURL)
    }

    // MARK: - Search

    func search(query: String, limit: Int = 7) -> [HistoryEntry] {
        guard !query.isEmpty else { return [] }
        return entries
            .compactMap { entry -> (HistoryEntry, Int)? in
                let haystack = "\(entry.title) \(entry.urlString)"
                let score = FuzzyMatch.score(query: query, candidate: haystack)
                return score > 0 ? (entry, score) : nil
            }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map(\.0)
    }

    // MARK: - Persistence

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: Self.fileURL)
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.fileURL),
              let decoded = try? JSONDecoder().decode([HistoryEntry].self, from: data) else { return }
        entries = decoded
    }
}
