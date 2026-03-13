import Foundation
import Combine

// MARK: - Search Engine

enum SearchEngine: String, CaseIterable, Identifiable, Codable {
    case duckDuckGo = "DuckDuckGo"
    case google     = "Google"
    case bing       = "Bing"
    case brave      = "Brave Search"
    case kagi       = "Kagi"
    case custom     = "Custom"

    var id: String { rawValue }

    var searchBaseURL: String {
        switch self {
        case .duckDuckGo: return "https://duckduckgo.com/?q="
        case .google:     return "https://www.google.com/search?q="
        case .bing:       return "https://www.bing.com/search?q="
        case .brave:      return "https://search.brave.com/search?q="
        case .kagi:       return "https://kagi.com/search?q="
        case .custom:     return ""
        }
    }

    var homepageURL: String {
        switch self {
        case .duckDuckGo: return "https://duckduckgo.com"
        case .google:     return "https://www.google.com"
        case .bing:       return "https://www.bing.com"
        case .brave:      return "https://search.brave.com"
        case .kagi:       return "https://kagi.com"
        case .custom:     return ""
        }
    }
}

// MARK: - New Tab Page

enum NewTabPage: String, CaseIterable, Identifiable, Codable {
    case searchEngine = "Search Engine Homepage"
    case blank        = "Blank Page"
    case custom       = "Custom URL"

    var id: String { rawValue }
}

// MARK: - Browser Settings

final class BrowserSettings: ObservableObject {
    static let shared = BrowserSettings()

    @Published var searchEngine: SearchEngine {
        didSet { persist("searchEngine", searchEngine.rawValue) }
    }
    @Published var customSearchBaseURL: String {
        didSet { persist("customSearchBaseURL", customSearchBaseURL) }
    }

    @Published var newTabPage: NewTabPage {
        didSet { persist("newTabPage", newTabPage.rawValue) }
    }
    @Published var customNewTabURL: String {
        didSet { persist("customNewTabURL", customNewTabURL) }
    }

    @Published var backgroundTabDiscardLimit: Int {
        didSet { persist("backgroundTabDiscardLimit", backgroundTabDiscardLimit) }
    }
    @Published var restoreSessionOnLaunch: Bool {
        didSet { persist("restoreSessionOnLaunch", restoreSessionOnLaunch) }
    }
    @Published var developerExtrasEnabled: Bool {
        didSet { persist("developerExtrasEnabled", developerExtrasEnabled) }
    }
    @Published var googleSignInCompatibilityMode: Bool {
        didSet { persist("googleSignInCompatibilityMode", googleSignInCompatibilityMode) }
    }
    @Published var blockThirdPartyCookies: Bool {
        didSet { persist("blockThirdPartyCookies", blockThirdPartyCookies) }
    }
    @Published var contentBlockingEnabled: Bool {
        didSet { persist("contentBlockingEnabled", contentBlockingEnabled) }
    }
    @Published var readerFontSize: Double {
        didSet { persist("readerFontSize", readerFontSize) }
    }

    private let defaults = UserDefaults.standard

    private init() {
        self.searchEngine          = SearchEngine(rawValue: UserDefaults.standard.string(forKey: "searchEngine") ?? "") ?? .duckDuckGo
        self.customSearchBaseURL   = UserDefaults.standard.string(forKey: "customSearchBaseURL") ?? ""
        self.newTabPage            = NewTabPage(rawValue: UserDefaults.standard.string(forKey: "newTabPage") ?? "") ?? .blank
        self.customNewTabURL       = UserDefaults.standard.string(forKey: "customNewTabURL") ?? ""
        self.backgroundTabDiscardLimit = (UserDefaults.standard.object(forKey: "backgroundTabDiscardLimit") as? Int) ?? 8
        self.restoreSessionOnLaunch    = (UserDefaults.standard.object(forKey: "restoreSessionOnLaunch") as? Bool) ?? true
        self.developerExtrasEnabled    = (UserDefaults.standard.object(forKey: "developerExtrasEnabled") as? Bool) ?? true
        self.googleSignInCompatibilityMode = (UserDefaults.standard.object(forKey: "googleSignInCompatibilityMode") as? Bool) ?? true
        self.blockThirdPartyCookies    = (UserDefaults.standard.object(forKey: "blockThirdPartyCookies") as? Bool) ?? false
        self.contentBlockingEnabled    = (UserDefaults.standard.object(forKey: "contentBlockingEnabled") as? Bool) ?? true
        self.readerFontSize            = (UserDefaults.standard.object(forKey: "readerFontSize") as? Double) ?? 18.0
    }

    // MARK: - URL Resolution

    /// Resolves a raw user input (query or URL string) to a navigable URL.
    func resolve(input: String) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Internal browser pages — rendered natively, never loaded into WebKit.
        if let url = URL(string: trimmed), url.scheme == "aob" {
            return nil
        }

        // Pass through special URLs (about:, data:, blob:, etc.) directly.
        if let url = URL(string: trimmed), let scheme = url.scheme,
           ["about", "data", "blob", "file"].contains(scheme) {
            return url
        }

        // Treat as direct URL if it has a scheme or looks like a hostname.
        if let url = URL(string: trimmed), url.scheme != nil, url.host != nil {
            return url
        }
        // Add https:// if it looks like a bare domain (no spaces, contains a dot).
        if !trimmed.contains(" "), trimmed.contains("."),
           let url = URL(string: "https://\(trimmed)") {
            return url
        }

        return searchURL(for: trimmed)
    }

    func searchURL(for query: String) -> URL? {
        let base: String
        if searchEngine == .custom {
            base = customSearchBaseURL
        } else {
            base = searchEngine.searchBaseURL
        }
        guard !base.isEmpty,
              let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }
        return URL(string: base + encoded)
    }

    var newTabURL: String {
        switch newTabPage {
        case .searchEngine:
            return searchEngine == .custom
                ? (customSearchBaseURL.isEmpty ? "about:blank" : customSearchBaseURL)
                : searchEngine.homepageURL
        case .blank:
            return "about:blank"
        case .custom:
            return customNewTabURL.isEmpty ? "about:blank" : customNewTabURL
        }
    }

    // MARK: - Private

    private func persist(_ key: String, _ value: some Any) {
        defaults.set(value, forKey: key)
    }
}
