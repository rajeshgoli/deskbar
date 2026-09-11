import AppKit
import Testing

@testable import DeskBar

private func window(
    pid: pid_t = 1,
    cgWindowID: CGWindowID = 1,
    appName: String = "Terminal",
    title: String = "Window",
    isMinimized: Bool = false,
    isHidden: Bool = false
) -> WindowInfo {
    WindowInfo(
        pid: pid,
        cgWindowID: cgWindowID,
        appName: appName,
        title: title,
        icon: nil,
        bundleIdentifier: "com.apple.Terminal",
        isMinimized: isMinimized,
        isHidden: isHidden
    )
}

private func trayApplication(pid: pid_t, name: String) -> TrayApplicationInfo {
    TrayApplicationInfo(
        pid: pid,
        bundleIdentifier: "com.example.\(name)",
        name: name,
        icon: nil,
        bundleURL: nil,
        runningApplication: nil
    )
}

@Test
func minimizedWindowLeavesTheTaskZoneEvenWhenItsAppHasOtherWindows() {
    // The reported bug: minimizing one Terminal window left a greyed tab eating task-zone width
    // because the old rule only moved an app to the tray once *every* window was minimized.
    let windows = [
        window(cgWindowID: 1, title: "visible"),
        window(cgWindowID: 2, title: "minimized", isMinimized: true)
    ]

    let taskWindows = windows.filter(WindowManager.belongsInTaskZone)
    let trayWindows = windows.filter(WindowManager.belongsInMinimizedTray)

    #expect(taskWindows.map(\.title) == ["visible"])
    #expect(trayWindows.map(\.title) == ["minimized"])
}

@Test
func taskZoneAndMinimizedTrayNeverClaimTheSameWindow() {
    let windows = [
        window(cgWindowID: 1),
        window(cgWindowID: 2, isMinimized: true),
        window(cgWindowID: 3, isHidden: true),
        window(cgWindowID: 4, isMinimized: true, isHidden: true)
    ]

    for candidate in windows {
        #expect(
            !(WindowManager.belongsInTaskZone(candidate)
                && WindowManager.belongsInMinimizedTray(candidate))
        )
    }

    // A hidden app is an app-level state, so it stays with the app-level tray icon.
    #expect(windows.filter(WindowManager.belongsInTaskZone).map(\.cgWindowID) == [1])
    #expect(windows.filter(WindowManager.belongsInMinimizedTray).map(\.cgWindowID) == [2])
}

@Test
func trayDropsTheAppIconWhenItsWindowsAreAlreadyShownAsMinimizedItems() {
    // Otherwise an app with every window minimized appears twice in the tray: once as an app
    // icon (it has no visible windows) and again as its per-window items.
    let applications = [trayApplication(pid: 1, name: "Terminal"), trayApplication(pid: 2, name: "Notes")]
    let minimizedWindows = [window(pid: 1, cgWindowID: 10, isMinimized: true)]

    let result = RunningAppTrayView.trayApplications(
        applications,
        excludingOwnersOf: minimizedWindows
    )

    #expect(result.map(\.name) == ["Notes"])
}

@Test
func trayKeepsAppIconsWhenNothingIsMinimized() {
    let applications = [trayApplication(pid: 1, name: "Terminal"), trayApplication(pid: 2, name: "Notes")]

    let result = RunningAppTrayView.trayApplications(applications, excludingOwnersOf: [])

    #expect(result.map(\.name) == ["Terminal", "Notes"])
}

@Test
func onlyBusyAppErrorsCountAsTransientEnumerationFailures() {
    // Carrying an app's cached windows forward is only safe while the failure is expected to
    // clear on its own. `.apiDisabled` — Accessibility revoked mid-session — must not qualify,
    // or every app's windows would be pinned as phantoms until permission came back.
    #expect(AccessibilityService.isTransientEnumerationFailure(.cannotComplete))

    for error in [AXError.apiDisabled, .invalidUIElement, .notImplemented, .attributeUnsupported, .noValue, .failure] {
        #expect(!AccessibilityService.isTransientEnumerationFailure(error))
    }
}
