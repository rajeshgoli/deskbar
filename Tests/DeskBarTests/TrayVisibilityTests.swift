import AppKit
import Testing
@testable import DeskBar

@MainActor
struct TrayVisibilityTests {
    @Test
    func hiddenAppsSurviveReloadAndCanBeRestoredIndividually() {
        withDefaults { defaults in
            let settings = TaskbarSettings(defaults: defaults)
            settings.hideTrayApp(bundleIdentifier: "com.example.agentbar", name: "AgentBar")
            settings.hideTrayApp(bundleIdentifier: "com.example.other", name: "Other")

            let reloaded = TaskbarSettings(defaults: defaults)
            #expect(reloaded.hiddenTrayApps["com.example.agentbar"] == "AgentBar")
            reloaded.showTrayApp(bundleIdentifier: "com.example.agentbar")
            #expect(TaskbarSettings(defaults: defaults).hiddenTrayApps == ["com.example.other": "Other"])
            reloaded.showAllTrayApps()
            #expect(TaskbarSettings(defaults: defaults).hiddenTrayApps.isEmpty)
        }
    }

    @Test
    func hiddenAppsStayHiddenAfterTheirProcessIDChanges() {
        let applications = [
            application(pid: 123, bundleIdentifier: "com.example.agentbar"),
            application(pid: 456, bundleIdentifier: "com.example.agentbar"),
            application(pid: 789, bundleIdentifier: "com.example.visible"),
            application(pid: 999, bundleIdentifier: nil)
        ]
        let result = RunningAppTrayView.trayApplications(
            applications,
            excludingOwnersOf: [],
            hiddenBundleIdentifiers: ["com.example.agentbar"]
        )
        #expect(result.map(\.pid) == [789, 999])
    }

    @Test
    func disablingHidingShowsIconsWithoutDiscardingSavedChoices() {
        withDefaults { defaults in
            let settings = TaskbarSettings(defaults: defaults)
            #expect(settings.enableTrayIconHiding)
            settings.hideTrayApp(bundleIdentifier: "com.example.agentbar", name: "AgentBar")
            settings.enableTrayIconHiding = false
            let reloaded = TaskbarSettings(defaults: defaults)
            #expect(!reloaded.enableTrayIconHiding)
            #expect(reloaded.hiddenTrayApps["com.example.agentbar"] == "AgentBar")
            let applications = [application(pid: 123, bundleIdentifier: "com.example.agentbar")]
            let visible = RunningAppTrayView.trayApplications(applications, excludingOwnersOf: [], hiddenBundleIdentifiers: Set(reloaded.hiddenTrayApps.keys), hidingEnabled: reloaded.enableTrayIconHiding)
            #expect(visible.map(\.pid) == [123])
        }
    }

    @Test
    func hideMenuUpdatesTrayPreferencesWithoutRequiringAnAppToHaveWindows() throws {
        try withDefaults { defaults in
            let settings = TaskbarSettings(defaults: defaults)
            let view = TrayIconView(
                application: application(pid: 123, bundleIdentifier: "com.example.agentbar"),
                pinnedAppManager: PinnedAppManager(defaults: defaults),
                hideFromTray: {
                    settings.hideTrayApp(bundleIdentifier: "com.example.agentbar", name: "AgentBar")
                }
            )
            let hide = try #require(view.makeContextMenu().items.first { $0.title == "Hide from Tray" })
            #expect(hide.isEnabled)
            let action = try #require(hide.action)
            _ = view.perform(action, with: hide)
            #expect(settings.hiddenTrayApps["com.example.agentbar"] == "AgentBar")
        }
    }

    @Test
    func recoveryButtonRemainsWhenNoAppsAreRunningAndRestoresSavedIcons() throws {
        try withDefaults { defaults in
            let settings = TaskbarSettings(defaults: defaults)
            settings.showSystemResourceWidget = false
            settings.hideTrayApp(bundleIdentifier: "com.example.agentbar", name: "AgentBar")
            settings.hideTrayApp(bundleIdentifier: "com.example.other", name: "Other")
            let pinnedApps = PinnedAppManager(defaults: defaults)
            let view = RunningAppTrayView(
                windowManager: WindowManager(pinnedAppManager: pinnedApps),
                pinnedAppManager: pinnedApps,
                settings: settings,
                systemResourceMonitor: SystemResourceMonitor(),
                displayID: CGDirectDisplayID.max
            )
            #expect(view.plannedContentWidth(visibleApplicationCapacity: 0) == 33)
            let button = try #require(view.subviews.flatMap(\.subviews).compactMap { $0 as? NSButton }.first)
            #expect(!button.isHidden)

            let restore = try #require(view.makeOverflowMenu().items.first { $0.title == "Show Hidden Apps" }?.submenu)
            let agentBar = try #require(restore.items.first { $0.title == "AgentBar" })
            let restoreAction = try #require(agentBar.action)
            _ = view.perform(restoreAction, with: agentBar)
            #expect(settings.hiddenTrayApps == ["com.example.other": "Other"])
            #expect(TaskbarSettings(defaults: defaults).hiddenTrayApps == settings.hiddenTrayApps)

            let showAll = try #require(restore.items.first { $0.title == "Show All" })
            let restoreAllAction = try #require(showAll.action)
            _ = view.perform(restoreAllAction, with: showAll)
            view.refresh()
            #expect(settings.hiddenTrayApps.isEmpty)
            #expect(view.preferredContentWidth() == 0)
            #expect(button.isHidden)
        }
    }

    private func application(pid: pid_t, bundleIdentifier: String?) -> TrayApplicationInfo {
        TrayApplicationInfo(pid: pid, bundleIdentifier: bundleIdentifier, name: "AgentBar", icon: nil, bundleURL: nil, runningApplication: nil)
    }

    private func withDefaults<T>(_ body: (UserDefaults) throws -> T) rethrows -> T {
        let suiteName = "TrayVisibilityTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        return try body(defaults)
    }
}
