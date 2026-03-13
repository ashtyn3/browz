import AppKit
import WebKit

/// WKWebView subclass that intercepts the native "Download Image" context menu
/// item, which does NOT go through WKDownloadDelegate by default.
///
/// Strategy: when "Download Image" is clicked, we piggy-back on
/// "Open Image in New Window" to get the image URL, then call
/// webView.startDownload so the download flows through WKDownloadDelegate.
final class ContextMenuWebView: WKWebView {

    enum PendingDownloadAction {
        case image
    }

    var pendingDownloadAction: PendingDownloadAction?
    private var cachedOpenImageInNewWindowItem: NSMenuItem?

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
