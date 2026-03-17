import Foundation

@MainActor
final class TabMemoryManager {
    private weak var store: TabStateStore?
    private let runtimeRegistry: TabRuntimeRegistry
    private var periodicTask: Task<Void, Never>?
    private var pressureSource: DispatchSourceMemoryPressure?

    init(store: TabStateStore, runtimeRegistry: TabRuntimeRegistry) {
        self.store = store
        self.runtimeRegistry = runtimeRegistry
    }

    func start() {
        startPeriodicPass()
        startPressureMonitor()
    }

    func stop() {
        periodicTask?.cancel()
        periodicTask = nil
        pressureSource?.cancel()
        pressureSource = nil
    }

    func trimNow() {
        // Manual trims should be aggressive — ignore age thresholds so the
        // user can free memory immediately.
        applyPolicy(discardLimit: 1, minAgeSeconds: nil)
    }

    private func startPeriodicPass() {
        periodicTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 20_000_000_000)
                await MainActor.run {
                    let limit = BrowserSettings.shared.backgroundTabDiscardLimit
                    // Be conservative: only discard background tabs that have
                    // been inactive for a while. This prevents recently used
                    // tabs from unexpectedly reloading when you return to them.
                    //
                    // Currently we require at least 30 minutes of inactivity
                    // before a tab becomes eligible for periodic discard.
                    let minAge: TimeInterval = 30 * 60
                    self.applyPolicy(discardLimit: limit, minAgeSeconds: minAge)
                }
            }
        }
    }

    private func startPressureMonitor() {
        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: .global(qos: .userInitiated)
        )
        source.setEventHandler { [weak self] in
            Task { @MainActor in
                // Under real system memory pressure we ignore age thresholds
                // and aggressively discard older background tabs.
                self?.applyPolicy(discardLimit: 5, minAgeSeconds: nil)
            }
        }
        source.resume()
        pressureSource = source
    }

    private func applyPolicy(discardLimit: Int, minAgeSeconds: TimeInterval?) {
        guard let store else { return }
        guard store.tabs.count > 1 else { return }
        guard let selectedID = store.selectedTabID else { return }

        var protectedIDs = Set([selectedID])
        if let splitID = store.splitTabID { protectedIDs.insert(splitID) }
        let discardIDs = store.discardCandidates(
            excluding: protectedIDs,
            maxCount: discardLimit,
            minAgeSeconds: minAgeSeconds
        )

        for id in discardIDs {
            store.setLifecycle(.discarded, for: id)
            runtimeRegistry.discardWebView(for: id)
        }
    }
}
