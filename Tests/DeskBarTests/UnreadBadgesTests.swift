import AppKit
import Testing

@testable import DeskBar

@Suite(.serialized)
struct UnreadBadgesTests {
    @Test
    func displayTextNormalisesDockLabels() {
        #expect(UnreadBadges.displayText(for: "3") == "3")
        #expect(UnreadBadges.displayText(for: " 12 ") == "12")
        #expect(UnreadBadges.displayText(for: "250") == "99+")
        #expect(UnreadBadges.displayText(for: "•") == "•")
        #expect(UnreadBadges.displayText(for: "Updating") == "Upda")
        #expect(UnreadBadges.displayText(for: "") == nil)
        #expect(UnreadBadges.displayText(for: nil) == nil)
    }

    @Test
    func labelsAreOnlyUsedWhenCountsAreEnabled() {
        let previous = (UnreadBadges.showsCounts, UnreadBadges.labels)
        defer { (UnreadBadges.showsCounts, UnreadBadges.labels) = previous }

        UnreadBadges.labels = ["com.microsoft.Outlook": "2", "net.whatsapp.WhatsApp": ""]

        UnreadBadges.showsCounts = false
        #expect(UnreadBadges.label(for: "com.microsoft.Outlook") == nil)

        UnreadBadges.showsCounts = true
        #expect(UnreadBadges.label(for: "com.microsoft.Outlook") == "2")
        #expect(UnreadBadges.label(for: "net.whatsapp.WhatsApp") == nil)
        #expect(UnreadBadges.label(for: "unknown") == nil)
        #expect(UnreadBadges.label(for: nil) == nil)
    }

    @Test
    func badgedIconKeepsItsSize() {
        let icon = NSImage(size: NSSize(width: 128, height: 128))
        #expect(icon.withBadgeLabel("7").size == icon.size)
        #expect(icon.withBadgeLabel("99+").size == icon.size)
    }

    @Test
    func pillFollowsTheDisplayedIconSize() {
        // A 32 pt source icon shown at 64 pt: the pill is 28 % of 64 on screen.
        let atLargeSize = UnreadBadges.pillHeight(displayedIconSize: 64, imageHeight: 32)
        #expect(abs(atLargeSize * 64 / 32 - 64 * 0.28) < 0.001)

        // Small icons keep a legible 10 pt pill.
        let atSmallSize = UnreadBadges.pillHeight(displayedIconSize: 24, imageHeight: 32)
        #expect(abs(atSmallSize * 24 / 32 - 10) < 0.001)
    }

    @Test
    func settingDefaultsOffAndPersists() {
        let suiteName = "UnreadBadgesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = TaskbarSettings(defaults: defaults)
        #expect(settings.showUnreadCounts == false)

        settings.showUnreadCounts = true
        #expect(TaskbarSettings(defaults: defaults).showUnreadCounts)
    }
}
