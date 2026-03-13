import Foundation

final class TabSessionPersistence {
    private let fileManager: FileManager
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func load() -> PersistedTabSession? {
        guard let sessionURL = sessionFileURL(),
              fileManager.fileExists(atPath: sessionURL.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: sessionURL)
            var session = try decoder.decode(PersistedTabSession.self, from: data)
            session.tabs = session.tabs.map { tab in
                var t = tab
                if let route = InternalRoute.parse(tab.urlString), route.urlString != tab.urlString {
                    t.urlString = route.urlString
                }
                return t
            }
            return session
        } catch {
            return nil
        }
    }

    func save(_ session: PersistedTabSession) {
        guard let sessionURL = sessionFileURL() else { return }

        do {
            let directory = sessionURL.deletingLastPathComponent()
            if !fileManager.fileExists(atPath: directory.path) {
                try fileManager.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true,
                    attributes: nil
                )
            }

            let data = try encoder.encode(session)
            try data.write(to: sessionURL, options: .atomic)
        } catch {
            // Persistence is best-effort for MVP.
        }
    }

    private func sessionFileURL() -> URL? {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("brows", isDirectory: true)
            .appendingPathComponent("tabs-session.json")
    }
}
