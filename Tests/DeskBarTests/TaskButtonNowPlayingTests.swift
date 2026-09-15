import AppKit
import Testing
@testable import DeskBar

struct TaskButtonNowPlayingTests {
    @MainActor
    @Test
    func playingSnapshotOverridesMatchingWindowTitle() {
        let settings = makeSettings()
        settings.showNowPlayingTitles = true
        let service = NowPlayingService()
        service.publishSnapshotForTesting(
            NowPlayingSnapshot.makeSnapshot(
                title: "Midnight City",
                artist: "M83",
                bundleIdentifier: "com.apple.Music",
                isPlaying: true
            )
        )

        let button = makeButton(settings: settings, nowPlayingService: service)

        #expect(button.resolvedTitleForTesting() == "M83 – Midnight City")
    }

    @MainActor
    @Test
    func nonMatchingBundleFallsBackToWindowTitle() {
        let settings = makeSettings()
        settings.showNowPlayingTitles = true
        let service = NowPlayingService()
        service.publishSnapshotForTesting(
            NowPlayingSnapshot.makeSnapshot(
                title: "Midnight City",
                artist: "M83",
                bundleIdentifier: "com.apple.Music",
                isPlaying: true
            )
        )

        let button = makeButton(
            settings: settings,
            nowPlayingService: service,
            bundleIdentifier: "com.spotify.client",
            title: "Spotify"
        )

        #expect(button.resolvedTitleForTesting() == "Spotify")
    }

    @MainActor
    @Test
    func disabledSettingFallsBackToWindowTitle() {
        let settings = makeSettings()
        settings.showNowPlayingTitles = false
        let service = NowPlayingService()
        service.publishSnapshotForTesting(
            NowPlayingSnapshot.makeSnapshot(
                title: "Midnight City",
                artist: "M83",
                bundleIdentifier: "com.apple.Music",
                isPlaying: true
            )
        )

        let button = makeButton(settings: settings, nowPlayingService: service)

        #expect(button.resolvedTitleForTesting() == "MiniPlayer")
    }

    @MainActor
    @Test
    func noSnapshotFallsBackToWindowTitle() {
        let settings = makeSettings()
        settings.showNowPlayingTitles = true
        let service = NowPlayingService()

        let button = makeButton(settings: settings, nowPlayingService: service)

        #expect(button.resolvedTitleForTesting() == "MiniPlayer")
    }

    // MARK: - Helpers

    @MainActor
    private func makeSettings() -> TaskbarSettings {
        let suiteName = "TaskButtonNowPlayingTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return TaskbarSettings(defaults: defaults)
    }

    @MainActor
    private func makeButton(
        settings: TaskbarSettings,
        nowPlayingService: NowPlayingService,
        bundleIdentifier: String? = "com.apple.Music",
        title: String = "MiniPlayer"
    ) -> TaskButtonView {
        TaskButtonView(
            windowInfo: WindowInfo(
                pid: 123,
                cgWindowID: 456,
                appName: "Music",
                title: title,
                icon: nil,
                bundleIdentifier: bundleIdentifier
            ),
            isActive: false,
            hasBadge: false,
            isAccessibilityAvailable: true,
            runtimeState: AppRuntimeState(),
            showsActivityOverlay: false,
            settings: settings,
            blacklistManager: BlacklistManager(),
            nowPlayingService: nowPlayingService,
            activationHandler: { _ in }
        )
    }
}
