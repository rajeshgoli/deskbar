import Foundation
import Testing
@testable import DeskBar

struct PermissionsManagerTests {
    @Test(arguments: [14, 15, 26])
    func olderMacOSVersionsUseAccessibilityName(majorVersion: Int) {
        #expect(PermissionsManager.accessibilityPermissionName(majorVersion: majorVersion) == "Accessibility")
    }

    @Test(arguments: [27, 28])
    func macOS27AndLaterUseDeviceControlAndDataAccessName(majorVersion: Int) {
        #expect(PermissionsManager.accessibilityPermissionName(majorVersion: majorVersion) == "Device Control and Data Access")
    }

    @Test
    func accessibilitySettingsURLsPreferModernSystemSettingsLink() {
        #expect(
            PermissionsManager.accessibilitySettingsURLs.map(\.absoluteString) == [
                "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
                "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
            ]
        )
    }
}
