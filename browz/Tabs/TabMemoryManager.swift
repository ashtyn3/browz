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
        applyPolicy(discardLimit: 1)
    }

    private func startPeriodicPass() {
        periodicTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 20_000_000_000)
                await MainActor.run {
                    let limit = BrowserSettings.shared.backgroundTabDiscardLimit
                    self.applyPolicy(discardLimit: limit)
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
                self?.applyPolicy(discardLimit: 5)
            }
        }
        source.resume()
        pressureSource = source
    }

    private func applyPolicy(discardLimit: Int) {
        guard let store else { return }
        guard store.tabs.count > 1 else { return }
        guard let selectedID = store.selectedTabID else { return }

        var protectedIDs = Set([selectedID])
        if let splitID = store.splitTabID { protectedIDs.insert(splitID) }
        let discardIDs = store.discardCandidates(excluding: protectedIDs, maxCount: discardLimit)

        for id in discardIDs {
            store.setLifecycle(.discarded, for: id)
            runtimeRegistry.discardWebView(for: id)
        }
    }
}
