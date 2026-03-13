import Foundation

enum DownloadState {
    case downloading
    case complete(URL)
    case failed(String)
}

struct DownloadItem: Identifiable {
    let id = UUID()
    let filename: String
    let sourceURL: URL?

    var state: DownloadState = .downloading
    var expectedBytes: Int64 = -1

    init(filename: String, sourceURL: URL?, expectedBytes: Int64 = -1) {
        self.filename = filename
        self.sourceURL = sourceURL
        self.expectedBytes = expectedBytes
    }

    var isTerminal: Bool {
        if case .downloading = state { return false }
        return true
    }

    var sizeLabel: String {
        switch state {
        case .downloading:
            return expectedBytes > 0 ? formatBytes(expectedBytes) : "Downloading…"
        case .complete:
            return expectedBytes > 0 ? formatBytes(expectedBytes) : "Complete"
        case .failed(let msg):
            return msg
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let mb = Double(bytes) / 1_048_576
        return mb >= 1 ? String(format: "%.1f MB", mb) : "\(max(bytes / 1024, 1)) KB"
    }
}
