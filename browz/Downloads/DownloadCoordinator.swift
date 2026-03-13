import Foundation
import WebKit
import Combine

final class DownloadCoordinator: NSObject, ObservableObject {
    @Published private(set) var items: [DownloadItem] = []

    private var registry: [ObjectIdentifier: (itemID: UUID, dest: URL?)] = [:]

    func handle(_ download: WKDownload) {
        print("[DL] DownloadCoordinator.handle called, setting delegate")
        download.delegate = self
    }

    func remove(_ item: DownloadItem) {
        items.removeAll { $0.id == item.id }
    }

    func clearCompleted() {
        items.removeAll { $0.isTerminal }
    }
}

// MARK: - WKDownloadDelegate

extension DownloadCoordinator: WKDownloadDelegate {
    func download(
        _ download: WKDownload,
        decideDestinationUsing response: URLResponse,
        suggestedFilename: String,
        completionHandler: @escaping (URL?) -> Void
    ) {
        print("[DL] decideDestination called for '\(suggestedFilename)'")
        let downloadsDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        let base = downloadsDir?.appendingPathComponent(suggestedFilename)
        let finalDest = base.map { uniqueURL(for: $0) }
        completionHandler(finalDest)

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let item = DownloadItem(
                filename: finalDest?.lastPathComponent ?? suggestedFilename,
                sourceURL: response.url,
                expectedBytes: response.expectedContentLength
            )
            self.items.append(item)
            self.registry[ObjectIdentifier(download)] = (item.id, finalDest)
        }
    }

    func downloadDidFinish(_ download: WKDownload) {
        print("[DL] downloadDidFinish")
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  let entry = self.registry[ObjectIdentifier(download)],
                  let index = self.items.firstIndex(where: { $0.id == entry.itemID }),
                  let dest = entry.dest else { return }
            self.items[index].state = .complete(dest)
            self.registry.removeValue(forKey: ObjectIdentifier(download))
        }
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        print("[DL] didFailWithError: \(error)")
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  let entry = self.registry[ObjectIdentifier(download)],
                  let index = self.items.firstIndex(where: { $0.id == entry.itemID }) else { return }
            self.items[index].state = .failed(error.localizedDescription)
            self.registry.removeValue(forKey: ObjectIdentifier(download))
        }
    }

    private func uniqueURL(for url: URL) -> URL {
        guard FileManager.default.fileExists(atPath: url.path) else { return url }
        let dir  = url.deletingLastPathComponent()
        let name = url.deletingPathExtension().lastPathComponent
        let ext  = url.pathExtension
        var i = 2
        while true {
            let suffix = ext.isEmpty ? "\(name) \(i)" : "\(name) \(i).\(ext)"
            let candidate = dir.appendingPathComponent(suffix)
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            i += 1
        }
    }
}
