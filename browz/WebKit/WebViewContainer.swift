import SwiftUI
import WebKit

struct WebViewContainer: NSViewRepresentable {
    let tab: TabState
    let runtimeRegistry: TabRuntimeRegistry
    let onNavigationUpdate: (UUID, String?, URL?) -> Void

    // makeNSView returns a bare container — updateNSView (always called right
    // after makeNSView and on every re-render) does all the actual work.
    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        let target = runtimeRegistry.webView(for: tab, callback: onNavigationUpdate)

        // Nothing to do if the right webview is already hosted.
        guard container.subviews.first !== target else { return }

        // Remove whatever is currently hosted.
        container.subviews.forEach { $0.removeFromSuperview() }

        // autoresizingMask + immediate frame avoids the zero-size flash
        // that occurs when constraints aren't applied until the next layout pass.
        target.translatesAutoresizingMaskIntoConstraints = true
        target.autoresizingMask = [.width, .height]
        target.frame = container.bounds
        container.addSubview(target)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: ()) {
        nsView.subviews.forEach { $0.removeFromSuperview() }
    }
}
