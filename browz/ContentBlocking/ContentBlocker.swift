import Foundation
import WebKit

/// Compiles a WKContentRuleList for ad and tracker blocking.
enum ContentBlocker {
    private static let identifier = "com.local.aob.rules.v2"

    static func ruleList() async -> WKContentRuleList? {
        guard let store = WKContentRuleListStore.default() else { return nil }
        if let cached = try? await store.contentRuleList(forIdentifier: identifier) {
            return cached
        }
        let json = buildJSON()
        return try? await store.compileContentRuleList(forIdentifier: identifier,
                                                       encodedContentRuleList: json)
    }

    // MARK: - Rule construction

    private static func buildJSON() -> String {
        var rules: [[String: Any]] = []

        // Analytics & tag managers
        rules += block(patterns: [
            "google-analytics\\.com",
            "googletagmanager\\.com",
            "googletagservices\\.com",
            "google-analytics\\.com/analytics\\.js",
            "stats\\.g\\.doubleclick\\.net",
        ], types: ["script", "fetch", "xmlhttprequest"])

        // Advertising networks
        rules += block(patterns: [
            "doubleclick\\.net",
            "googlesyndication\\.com",
            "adservice\\.google\\.",
            "adnxs\\.com",
            "ads\\.yahoo\\.com",
            "advertising\\.com",
            "outbrain\\.com",
            "taboola\\.com",
            "moatads\\.com",
            "adroll\\.com",
            "criteo\\.com",
            "adsrvr\\.org",
        ], types: ["script", "fetch", "image", "xmlhttprequest"])

        // Social trackers
        rules += block(patterns: [
            "connect\\.facebook\\.net",
            "platform\\.twitter\\.com",
            "platform\\.linkedin\\.com/",
            "assets\\.pinterest\\.com",
        ], types: ["script"])

        // Behavioral/session trackers
        rules += block(patterns: [
            "hotjar\\.com",
            "fullstory\\.com",
            "segment\\.com/analytics",
            "mixpanel\\.com",
            "amplitude\\.com",
            "heap-api\\.com",
            "intercom\\.io",
            "clearbit\\.com",
            "quantserve\\.com",
            "scorecardresearch\\.com",
        ], types: ["script", "fetch", "xmlhttprequest"])

        guard let data = try? JSONSerialization.data(withJSONObject: rules, options: .prettyPrinted),
              let json = String(data: data, encoding: .utf8) else { return "[]" }
        return json
    }

    private static func block(patterns: [String], types: [String]) -> [[String: Any]] {
        patterns.map { pattern in
            [
                "trigger": [
                    "url-filter": "^https?://([a-z0-9-]+\\.)*\(pattern)",
                    "resource-type": types,
                ] as [String: Any],
                "action": ["type": "block"] as [String: Any],
            ]
        }
    }
}
