import AppKit
import SwiftUI

struct WindowCloseInterceptor: NSViewRepresentable {
    let onWindowShouldClose: () -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(onWindowShouldClose: onWindowShouldClose)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            if let window = view.window {
                configure(window, coordinator: context.coordinator)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window {
                configure(window, coordinator: context.coordinator)
            }
        }
    }

    private func configure(_ window: NSWindow, coordinator: Coordinator) {
        if window.delegate !== coordinator {
            window.delegate = coordinator
        }

        // Keep the shell translucent so web content/background materials remain
        // visible edge-to-edge (including the titlebar region).
        window.isOpaque = false
        window.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.18)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.titlebarSeparatorStyle = .none
        window.isMovableByWindowBackground = true
        window.styleMask.insert(.fullSizeContentView)
        window.toolbar = nil
        if let themeFrame = window.contentView?.superview {
            themeFrame.wantsLayer = true
            themeFrame.layer?.backgroundColor = NSColor.clear.cgColor
        }
        if let titlebarContainer = window.standardWindowButton(.closeButton)?.superview {
            titlebarContainer.wantsLayer = true
            titlebarContainer.layer?.backgroundColor = NSColor.clear.cgColor
        }

        // Keep native traffic lights in their standard location but allow
        // the app to hide/show them in sync with the Zen-style sidebar.
        NotificationCenter.default.addObserver(
            forName: .browzSidebarVisibilityChanged,
            object: nil,
            queue: .main
        ) { [weak window] note in
            guard let window,
                  let visible = note.userInfo?["visible"] as? Bool,
                  let close = window.standardWindowButton(.closeButton),
                  let mini  = window.standardWindowButton(.miniaturizeButton),
                  let zoom  = window.standardWindowButton(.zoomButton) else { return }
            close.isHidden = !visible
            mini.isHidden  = !visible
            zoom.isHidden  = !visible
        }
    }

    final class Coordinator: NSObject, NSWindowDelegate {
        private let onWindowShouldClose: () -> Bool

        init(onWindowShouldClose: @escaping () -> Bool) {
            self.onWindowShouldClose = onWindowShouldClose
            super.init()
        }

        func windowShouldClose(_ sender: NSWindow) -> Bool {
            onWindowShouldClose()
        }
    }
}
