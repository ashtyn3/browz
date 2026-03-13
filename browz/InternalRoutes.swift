import Foundation

/// Internal browser pages (browz://) rendered natively instead of in WebKit.
/// Add new cases and handle them in the router to extend internal pages.
enum InternalRoute: String, CaseIterable {
    case settings = "settings"

    /// URL scheme for internal pages.
    static let scheme = "browz"

    /// Canonical URL string for this route (e.g. "browz://settings").
    var urlString: String { "\(Self.scheme)://\(rawValue)" }

    /// Human-readable title for the tab.
    var title: String {
        switch self {
        case .settings: return "Settings"
        }
    }

    /// Parses a URL string into an internal route if it is a valid browz:// (or legacy aob://) URL.
    static func parse(_ urlString: String) -> InternalRoute? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let host = url.host?.lowercased(), !host.isEmpty else {
            return nil
        }
        let s = url.scheme?.lowercased()
        guard s == scheme || s == "aob" else { return nil }
        return InternalRoute(rawValue: host)
    }

    /// Returns true if the URL string is an internal page (browz:// or legacy aob://).
    static func isInternalURL(_ urlString: String) -> Bool {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed) else { return false }
        let s = url.scheme?.lowercased()
        return s == scheme || s == "aob"
    }
}
