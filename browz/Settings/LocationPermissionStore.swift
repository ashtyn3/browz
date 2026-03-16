import Foundation

/// Persists per-origin location permission (allow/deny) so we don't prompt every time.
final class LocationPermissionStore {
    private let defaults = UserDefaults.standard
    private let key = "browz.locationPermissionByHost"

    func get(host: String) -> Bool? {
        guard !host.isEmpty else { return nil }
        let dict = defaults.dictionary(forKey: key) as? [String: Bool]
        return dict?[host]
    }

    func set(host: String, allowed: Bool) {
        guard !host.isEmpty else { return }
        var dict = (defaults.dictionary(forKey: key) as? [String: Bool]) ?? [:]
        dict[host] = allowed
        defaults.set(dict, forKey: key)
    }
}
