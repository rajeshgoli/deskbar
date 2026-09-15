import AppKit
import Combine

/// Switcher-only exclusion list. Unlike the taskbar blacklist, excluded apps
/// stay visible on the taskbar — their windows are just skipped by the
/// Option-Tab window switcher (e.g. game-streaming clients like Moonlight
/// whose fullscreen sessions the switcher overlay would disturb).
final class SwitcherExclusionManager: ObservableObject {
    static let didChangeNotification = Notification.Name("SwitcherExclusionManager.didChange")

    @Published var excludedBundleIDs: Set<String>

    private let defaults: UserDefaults
    private let defaultsKey = "switcherExcludedApps"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedBundleIDs = defaults.stringArray(forKey: defaultsKey) ?? []
        excludedBundleIDs = Set(storedBundleIDs)
    }

    func add(bundleIdentifier: String) {
        let trimmedBundleIdentifier = bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBundleIdentifier.isEmpty else {
            return
        }

        let (inserted, _) = excludedBundleIDs.insert(trimmedBundleIdentifier)
        guard inserted else {
            return
        }

        persistAndNotify()
    }

    func remove(bundleIdentifier: String) {
        let trimmedBundleIdentifier = bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard excludedBundleIDs.remove(trimmedBundleIdentifier) != nil else {
            return
        }

        persistAndNotify()
    }

    func isExcluded(bundleIdentifier: String) -> Bool {
        excludedBundleIDs.contains(bundleIdentifier)
    }

    private func persistAndNotify() {
        defaults.set(Array(excludedBundleIDs).sorted(), forKey: defaultsKey)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }
}
