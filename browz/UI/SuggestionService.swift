import Foundation

@MainActor
final class SuggestionService: ObservableObject {
    @Published private(set) var suggestions: [String] = []

    private var fetchTask: Task<Void, Never>?

    func update(query: String) {
        fetchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        // Skip obvious non-search inputs
        guard !trimmed.isEmpty,
              !trimmed.contains("://"),
              !trimmed.hasPrefix("about:"),
              !trimmed.hasPrefix("aob:") else {
            suggestions = []
            return
        }

        fetchTask = Task {
            try? await Task.sleep(nanoseconds: 200_000_000) // 200 ms debounce
            guard !Task.isCancelled else { return }
            let results = await Self.fetch(query: trimmed)
            guard !Task.isCancelled else { return }
            suggestions = results
        }
    }

    func clear() {
        fetchTask?.cancel()
        suggestions = []
    }

    // MARK: - Networking

    private static func fetch(query: String) async -> [String] {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return []
        }

        // Pick endpoint based on configured engine
        let engine = BrowserSettings.shared.searchEngine
        let urlString: String
        switch engine {
        case .google:
            urlString = "https://suggestqueries.google.com/complete/search?client=firefox&q=\(encoded)"
        default:
            // DuckDuckGo's endpoint works as a reasonable fallback for all other engines
            urlString = "https://duckduckgo.com/ac/?q=\(encoded)&type=list"
        }

        guard let url = URL(string: urlString) else { return [] }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return parseOpenSearch(data)
        } catch {
            return []
        }
    }

    /// Parses the OpenSearch Suggestions format: ["query", ["sug1", "sug2", ...], ...]
    private static func parseOpenSearch(_ data: Data) -> [String] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [Any],
              json.count >= 2,
              let items = json[1] as? [String] else { return [] }
        return Array(items.prefix(6))
    }
}
