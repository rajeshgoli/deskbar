import Foundation
import Testing
@testable import DeskBar

@MainActor
struct SwitcherExclusionManagerTests {
    @Test
    func addPersistsTrimsAndPostsNotification() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let manager = SwitcherExclusionManager(defaults: defaults)
        var notificationCount = 0
        let observer = NotificationCenter.default.addObserver(
            forName: SwitcherExclusionManager.didChangeNotification,
            object: nil,
            queue: nil
        ) { _ in
            notificationCount += 1
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        manager.add(bundleIdentifier: "  com.example.app  ")
        manager.add(bundleIdentifier: "com.example.app")
        manager.add(bundleIdentifier: "   ")

        #expect(manager.isExcluded(bundleIdentifier: "com.example.app"))
        #expect(manager.excludedBundleIDs == ["com.example.app"])
        #expect(Set(defaults.stringArray(forKey: "switcherExcludedApps") ?? []) == ["com.example.app"])
        #expect(notificationCount == 1)
    }

    @Test
    func removePersistsAndPostsNotification() {
        let (defaults, suiteName) = makeDefaults()
        defaults.set(["com.example.app"], forKey: "switcherExcludedApps")
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let manager = SwitcherExclusionManager(defaults: defaults)
        #expect(manager.isExcluded(bundleIdentifier: "com.example.app"))

        var notificationCount = 0
        let observer = NotificationCenter.default.addObserver(
            forName: SwitcherExclusionManager.didChangeNotification,
            object: nil,
            queue: nil
        ) { _ in
            notificationCount += 1
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        manager.remove(bundleIdentifier: "com.example.app")
        manager.remove(bundleIdentifier: "com.example.app")

        #expect(!manager.isExcluded(bundleIdentifier: "com.example.app"))
        #expect((defaults.stringArray(forKey: "switcherExcludedApps") ?? []).isEmpty)
        #expect(notificationCount == 1)
    }

    @Test
    func loadsPersistedExclusions() {
        let (defaults, suiteName) = makeDefaults()
        defaults.set(["com.example.a", "com.example.b"], forKey: "switcherExcludedApps")
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let manager = SwitcherExclusionManager(defaults: defaults)

        #expect(manager.excludedBundleIDs == ["com.example.a", "com.example.b"])
    }

    private func makeDefaults() -> (UserDefaults, String) {
        let suiteName = "SwitcherExclusionManagerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }
}
