import AppKit
import WebKit

/// WKWebView subclass that intercepts the native "Download Image" context menu
/// item, which does NOT go through WKDownloadDelegate by default.
///
/// Strategy: when "Download Image" is clicked, we piggy-back on
/// "Open Image in New Window" to get the image URL, then call
/// webView.startDownload so the download flows through WKDownloadDelegate.
///
/// Also overrides performKeyEquivalent so that app-level keyboard shortcuts
/// (e.g. Cmd+W, Cmd+T) are not consumed by the web content. When the WebView
/// is first responder—e.g. on media player or file-viewing pages—it would
/// otherwise swallow these before they reach the menu bar. Returning false
/// for reserved shortcuts lets them propagate to the app's commands.
final class ContextMenuWebView: WKWebView {

    enum PendingDownloadAction {
        case image
    }

    var pendingDownloadAction: PendingDownloadAction?
    private var cachedOpenImageInNewWindowItem: NSMenuItem?

    /// App-reserved key equivalents that must propagate to the menu bar instead
    /// of being handled by web content. (modifiers, character) for character keys.
    private static let reservedCharacterShortcuts: [(NSEvent.ModifierFlags, Character)] = [
        (.command, "t"),
        ([.command, .shift], "n"),
        (.command, "k"),
        (.command, "w"),
        ([.command, .shift], "t"),
        (.command, "l"),
        (.command, "f"),
        (.command, "r"),
        (.command, "="),
        (.command, "-"),
        (.command, "0"),
        ([.command, .shift], "r"),
        ([.command, .shift], "\\"),
        (.command, "["),
        (.command, "]"),
        ([.command, .shift], "h"),
        (.command, "d"),
        ([.command, .shift], "]"),
        ([.command, .shift], "["),
        (.command, ","),
        ([.command, .option], "w"),
    ] + (1...9).map { (.command, Character("\($0)")) }

    /// (modifiers, keyCode) for special keys (e.g. arrows). Left = 123, right = 124 (HID usage).
    private static let reservedKeyCodeShortcuts: [(NSEvent.ModifierFlags, UInt16)] = [
        ([.command, .option], 123),
        ([.command, .option], 124),
    ]

    private static let relevantModifiers: NSEvent.ModifierFlags = [.command, .shift, .option]

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection(Self.relevantModifiers)
        let char = event.charactersIgnoringModifiers?.first

        for (reservedMods, reservedChar) in Self.reservedCharacterShortcuts {
            if mods == reservedMods, char == reservedChar {
                return false
            }
        }
        for (reservedMods, reservedCode) in Self.reservedKeyCodeShortcuts {
            if mods == reservedMods, event.keyCode == reservedCode {
                return false
            }
        }
        return super.performKeyEquivalent(with: event)
    }

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        cachedOpenImageInNewWindowItem = menu.items.first {
            $0.identifier?.rawValue == "WKMenuItemIdentifierOpenImageInNewWindow"
        }

        for item in menu.items {
            if item.identifier?.rawValue == "WKMenuItemIdentifierDownloadImage" {
                item.target = self
                item.action = #selector(interceptDownloadImage)
            }
        }

        super.willOpenMenu(menu, with: event)
    }

    override func didCloseMenu(_ menu: NSMenu, with event: NSEvent?) {
        super.didCloseMenu(menu, with: event)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.pendingDownloadAction = nil
            self?.cachedOpenImageInNewWindowItem = nil
        }
    }

    @objc private func interceptDownloadImage(_ sender: NSMenuItem) {
        pendingDownloadAction = .image
        guard let item = cachedOpenImageInNewWindowItem,
              let action = item.action else { return }
        NSApp.sendAction(action, to: item.target, from: item)
    }
}
