import AppKit
import ApplicationServices
import Testing
@testable import DeskBar

@Test func titleNotificationsFromPageTextDoNotTriggerWindowDiscovery() {
    #expect(WindowManager.isWindowTitleNotification(role: kAXWindowRole as String))
    #expect(!WindowManager.isWindowTitleNotification(role: kAXStaticTextRole as String))
    #expect(!WindowManager.isWindowTitleNotification(role: kAXApplicationRole as String))
    #expect(!WindowManager.isWindowTitleNotification(role: nil))
}

@Test func titleEventsCoalesceAndStructuralEventsRequireDiscovery() {
    let first = AXUIElementCreateApplication(100)
    let second = AXUIElementCreateApplication(200)
    var batch = AXRefreshBatch()
    batch.add(kAXTitleChangedNotification as CFString, element: first)
    batch.add(kAXTitleChangedNotification as CFString, element: first)
    batch.add(kAXTitleChangedNotification as CFString, element: second)
    #expect(batch.titleElements.count == 2)
    #expect(!batch.needsFullRefresh)
    batch.add(kAXWindowMiniaturizedNotification as CFString, element: second)
    batch.add(kAXTitleChangedNotification as CFString, element: first)
    #expect(batch.needsFullRefresh)
    #expect(batch.titleElements.isEmpty)
}

@Test func titlePatchPreservesWindowIdentityAndPlacement() {
    let icon = NSImage(size: NSSize(width: 16, height: 16))
    let original = WindowInfo(pid: 100, cgWindowID: 123, appName: "Terminal",
                              title: "Old", icon: icon, bundleIdentifier: "com.apple.Terminal",
                              applicationURL: URL(fileURLWithPath: "/Applications/Terminal.app"),
                              isMinimized: true, isHidden: true)
    let renamed = original.replacingTitle("New")
    #expect(renamed.title == "New")
    #expect(renamed.id == original.id)
    #expect(renamed.icon === icon)
    #expect(renamed.replacingTitle("Old") == original)
}

@Test func smLiveRequestsDoNotUsePersistentCaches() {
    let configuration = SMHTTPClient.configuration()
    #expect(configuration.urlCache == nil)
    #expect(configuration.httpCookieStorage == nil)
    #expect(configuration.requestCachePolicy == .reloadIgnoringLocalCacheData)
    #expect(!configuration.httpShouldSetCookies)
}

@MainActor
@Test func unchangedTaskButtonDoesNotInvalidateLayoutButChangesStillRender() {
    let defaults = UserDefaults(suiteName: "DeskBarTests.energy.\(UUID().uuidString)")!
    let settings = TaskbarSettings(defaults: defaults)
    let original = WindowInfo(pid: 999999, cgWindowID: 42, appName: "Test",
                              title: "Before", icon: nil, bundleIdentifier: "test.energy")
    let button = TaskButtonView(windowInfo: original, isActive: false, hasBadge: false,
                                isAccessibilityAvailable: false, runtimeState: AppRuntimeState(),
                                showsActivityOverlay: false, settings: settings,
                                blacklistManager: BlacklistManager(), activationHandler: { _ in })
    button.layoutSubtreeIfNeeded()
    button.needsLayout = false
    button.update(windowInfo: original, isActive: false, hasBadge: false,
                  isAccessibilityAvailable: false, runtimeState: AppRuntimeState(),
                  showsActivityOverlay: false)
    #expect(!button.needsLayout)
    button.update(windowInfo: original.replacingTitle("After"), isActive: true, hasBadge: false,
                  isAccessibilityAvailable: false, runtimeState: AppRuntimeState(),
                  showsActivityOverlay: false)
    #expect(button.isActive)
    #expect(button.toolTip?.contains("After") == true)
}

@Test func pluginPresentationComparisonDetectsVisibleChanges() {
    let first = TaskButtonPluginMenuConfiguration(buttonTitle: "sm", tintColor: .red,
                                                 showsActionButton: true, menuProvider: { NSMenu() })
    let same = TaskButtonPluginMenuConfiguration(buttonTitle: "sm", tintColor: .red,
                                                showsActionButton: true, menuProvider: { NSMenu() })
    let changed = TaskButtonPluginMenuConfiguration(buttonTitle: "sm", tintColor: .blue,
                                                   showsActionButton: true, menuProvider: { NSMenu() })
    #expect(TaskButtonPluginMenuConfiguration.sameAppearance(first, same))
    #expect(!TaskButtonPluginMenuConfiguration.sameAppearance(first, changed))
    #expect(!TaskButtonPluginMenuConfiguration.sameAppearance(first, nil))
}
