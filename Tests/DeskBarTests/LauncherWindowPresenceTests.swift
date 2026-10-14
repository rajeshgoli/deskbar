import Testing
@testable import DeskBar

@Test
func backgroundAppReopensDespiteRetainedWindowServerSurfaces() {
    var queriedCGWindows = false
    func retainedSurfaces() -> Bool {
        queriedCGWindows = true
        return true
    }

    let hasWindows = LauncherApplicationActivator.hasApplicationWindows(
        accessibilityWindows: false,
        cgWindows: retainedSurfaces()
    )

    #expect(!hasWindows)
    #expect(!queriedCGWindows)
    #expect(TrayActivationPlanner.action(bundleIdentifier: "net.whatsapp.WhatsApp", hasAnyWindows: hasWindows) == .reopenApplication)
}

@Test
func existingAccessibleWindowsDoNotReopenTheApp() {
    let hasWindows = LauncherApplicationActivator.hasApplicationWindows(
        accessibilityWindows: true,
        cgWindows: false
    )

    #expect(hasWindows)
    #expect(TrayActivationPlanner.action(bundleIdentifier: "com.example.app", hasAnyWindows: hasWindows) == .activateApplication)
}

@Test(arguments: [true, false])
func unavailableAccessibilityUsesWindowServerFallback(cgWindows: Bool) {
    #expect(LauncherApplicationActivator.hasApplicationWindows(accessibilityWindows: nil, cgWindows: cgWindows) == cgWindows)
}
