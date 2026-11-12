import AppKit
import Testing

@testable import DeskBar

struct BackgroundColorSettingTests {
    @Test
    func hexRoundTripsAndAcceptsSixDigitColours() {
        #expect(StoredColor(hex: "#000000")?.hex == "#000000FF")
        #expect(StoredColor(hex: "#1E90FF80")?.hex == "#1E90FF80")
        #expect(StoredColor(hex: "1e90ff")?.hex == "#1E90FFFF")
        #expect(StoredColor(hex: "#12345") == nil)
        #expect(StoredColor(hex: "#GGGGGG") == nil)
    }

    @Test
    func darkColoursAskForLightText() {
        #expect(StoredColor.black.isDark)
        #expect(StoredColor(hex: "#FFFFFF")?.isDark == false)
    }

    @Test
    func defaultsToTheSystemMaterialAndPersistsTheChoice() {
        let suiteName = "BackgroundColorSettingTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = TaskbarSettings(defaults: defaults)
        #expect(settings.useCustomBackgroundColor == false)
        #expect(settings.backgroundColor == .black)

        settings.useCustomBackgroundColor = true
        settings.backgroundColor = StoredColor(hex: "#20304080")!

        let reloaded = TaskbarSettings(defaults: defaults)
        #expect(reloaded.useCustomBackgroundColor)
        #expect(reloaded.backgroundColor.hex == "#20304080")
    }

    @Test
    func unreadableStoredColourFallsBackToBlack() {
        let suiteName = "BackgroundColorSettingTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("not a colour", forKey: "backgroundColor")
        #expect(TaskbarSettings(defaults: defaults).backgroundColor == .black)
    }
}

struct BackgroundColorConversionTests {
    @Test
    func aColourWithoutAnSRGBEquivalentFallsBackToBlack() {
        let pattern = NSColor(patternImage: NSImage(size: NSSize(width: 2, height: 2)))
        #expect(StoredColor(pattern) == .black)
    }
}
