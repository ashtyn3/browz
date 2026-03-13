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

        // Make the shell itself translucent; content decides opacity.
        window.isOpaque = false
        window.backgroundColor = .clear
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.styleMask.insert(.fullSizeContentView)
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
