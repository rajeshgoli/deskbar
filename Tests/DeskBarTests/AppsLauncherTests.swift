import Foundation
import Testing
@testable import DeskBar

struct AppsLauncherTests {
    @Test
    func defaultSettingsResolveToSystemApps() {
        let settings = makeSettings()

        let target = AppsLauncher.resolve(settings: settings)

        #expect(target.name == "Apps")
        #expect(target.tooltip == "Apps")
    }

    @Test
    func hiddenActionResolvesToBenignFallback() {
        let settings = makeSettings()
        settings.launcherButtonAction = .hidden

        let target = AppsLauncher.resolve(settings: settings)

        #expect(target.name == "Apps")
    }

    @Test
    func customCommandURLResolvesToHost() {
        let settings = makeSettings()
        settings.launcherButtonAction = .customCommand
        settings.launcherCustomCommand = "https://example.com/some/path"

        let target = AppsLauncher.resolve(settings: settings)

        #expect(target.name == "example.com")
        #expect(target.tooltip == "https://example.com/some/path")
        #expect(AppsLauncher.commandURL(from: "https://example.com/some/path") != nil)
    }

    @Test
    func customCommandShellResolvesToCustom() {
        let settings = makeSettings()
        settings.launcherButtonAction = .customCommand
        settings.launcherCustomCommand = "open -a TextEdit ~/notes.txt"

        let target = AppsLauncher.resolve(settings: settings)

        #expect(target.name == "Custom")
        #expect(AppsLauncher.commandURL(from: "open -a TextEdit ~/notes.txt") == nil)
        #expect(AppsLauncher.commandURL(from: "") == nil)
        #expect(AppsLauncher.commandURL(from: "   ") == nil)
    }

    @Test
    func unresolvableCustomAppFallsBackToApps() {
        let settings = makeSettings()
        settings.launcherButtonAction = .customApp
        settings.launcherCustomAppBundleID = "com.example.does-not-exist"
        settings.launcherCustomAppPath = "/nonexistent/Nowhere.app"

        #expect(AppsLauncher.customAppURL(settings: settings) == nil)
        #expect(AppsLauncher.resolve(settings: settings).name == "Apps")
    }

    private func makeSettings() -> TaskbarSettings {
        let suiteName = "AppsLauncherTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return TaskbarSettings(defaults: defaults)
    }
}
