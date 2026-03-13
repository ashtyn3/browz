import SwiftUI
import AppKit
import Combine

/// Observes Command key state for live UI feedback (e.g. brightening shortcut hints).
final class CommandKeyObserver: ObservableObject {
    @Published var isCommandKeyHeld = false
    private var monitor: Any?

    init() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            DispatchQueue.main.async {
                self?.isCommandKeyHeld = event.modifierFlags.contains(.command)
            }
            return event
        }
    }

    deinit {
        if let m = monitor { NSEvent.removeMonitor(m) }
    }
}

/// Low-contrast keyboard shortcut reference shown on a single blank tab (when enabled in settings).
/// Brightens when Command is held for live feedback.
struct StartScreenView: View {
    @StateObject private var commandObserver = CommandKeyObserver()

    private static let dimOpacity = 0.35
    private static let brightOpacity = 0.82
    private var labelOpacity: Double { commandObserver.isCommandKeyHeld ? Self.brightOpacity : Self.dimOpacity }
    private var chipOpacity: Double { commandObserver.isCommandKeyHeld ? 0.22 : 0.12 }

    var body: some View {
        VStack(spacing: 16) {
            row("⌘K", "Find tab")
            row("⌘L", "Open address bar")
            row("⌘T", "New tab")
            row("⌘W", "Close tab")
            row("⌘,", "Settings")
        }
        .padding(40)
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.12), value: commandObserver.isCommandKeyHeld)
    }

    private func row(_ keys: String, _ action: String) -> some View {
        let base = Color(red: 0.08, green: 0.08, blue: 0.10)
        return HStack(spacing: 12) {
            Text(keys)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(base.opacity(labelOpacity))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(base.opacity(chipOpacity), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            Text(action)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(base.opacity(labelOpacity))
        }
    }
}
