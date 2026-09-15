import AppKit

enum AppsLauncher {
    private static let appsBundleIdentifier = "com.apple.apps.launcher"
    private static let appsPath = "/System/Applications/Apps.app"
    private static let legacyLaunchpadPath = "/System/Applications/Launchpad.app"

    struct LauncherTarget {
        let name: String
        let tooltip: String
        let icon: NSImage?
    }

    /// Opens the configured launcher target. `.hidden` is a no-op (the button
    /// is not shown in that mode, but the shortcut path shares this entry).
    static func open(settings: TaskbarSettings) {
        switch settings.launcherButtonAction {
        case .systemApps:
            openSystemApps()
        case .customApp:
            openCustomApp(settings: settings)
        case .customCommand:
            openCustomCommand(settings.launcherCustomCommand)
        case .hidden:
            break
        }
    }

    /// Resolves the display target for the launcher button. Unresolvable custom
    /// targets fall back to the system Apps target so the button stays usable.
    static func resolve(settings: TaskbarSettings) -> LauncherTarget {
        switch settings.launcherButtonAction {
        case .systemApps, .hidden:
            return LauncherTarget(name: "Apps", tooltip: "Apps", icon: icon())
        case .customApp:
            if let url = customAppURL(settings: settings) {
                let name = FileManager.default.displayName(atPath: url.path)
                return LauncherTarget(
                    name: name,
                    tooltip: name,
                    icon: NSWorkspace.shared.icon(forFile: url.path).scaled(to: NSSize(width: 32, height: 32))
                )
            }
            print("DeskBar: custom launcher app unresolved, falling back to Apps")
            return LauncherTarget(name: "Apps", tooltip: "Apps", icon: icon())
        case .customCommand:
            let command = settings.launcherCustomCommand.trimmingCharacters(in: .whitespacesAndNewlines)
            if let url = commandURL(from: command) {
                let name = url.host ?? "Link"
                return LauncherTarget(name: name, tooltip: command, icon: templateIcon(named: "link"))
            }
            return LauncherTarget(
                name: "Custom",
                tooltip: command.isEmpty ? "Custom" : command,
                icon: templateIcon(named: "terminal")
            )
        }
    }

    // MARK: - System Apps (legacy behavior)

    static func open() {
        openSystemApps()
    }

    private static func openSystemApps() {
        LauncherApplicationActivator.launch(
            bundleIdentifier: appsBundleIdentifier,
            applicationURL: applicationURL()
        )
    }

    static func applicationURL() -> URL? {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: appsBundleIdentifier) {
            return url
        }

        for path in [appsPath, legacyLaunchpadPath] where FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }

        return nil
    }

    static func icon() -> NSImage? {
        if let url = applicationURL() {
            return NSWorkspace.shared.icon(forFile: url.path).scaled(to: NSSize(width: 32, height: 32))
        }

        return templateIcon(named: "square.grid.3x3.fill")
    }

    // MARK: - Custom targets

    static func customAppURL(settings: TaskbarSettings) -> URL? {
        if let path = settings.launcherCustomAppPath,
           !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }

        if let bundleID = settings.launcherCustomAppBundleID,
           !bundleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return url
        }

        return nil
    }

    private static func openCustomApp(settings: TaskbarSettings) {
        guard let url = customAppURL(settings: settings) else {
            print("DeskBar: custom launcher app unresolved, opening Apps instead")
            openSystemApps()
            return
        }

        LauncherApplicationActivator.launch(
            bundleIdentifier: settings.launcherCustomAppBundleID ?? "",
            applicationURL: url
        )
    }

    private static func openCustomCommand(_ command: String) {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            print("DeskBar: launcher custom command is empty")
            return
        }

        if let url = commandURL(from: trimmed) {
            if NSWorkspace.shared.open(url) {
                return
            }
            print("DeskBar: failed to open launcher URL \(trimmed)")
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", trimmed]
        do {
            try process.run()
        } catch {
            print("DeskBar: failed to run launcher command: \(error)")
        }
    }

    /// Interprets the command as a URL only when it parses as an absolute URL
    /// with a scheme (http://, file://, custom schemes). Anything else is a
    /// shell command.
    static func commandURL(from command: String) -> URL? {
        guard let url = URL(string: command),
              let scheme = url.scheme,
              !scheme.isEmpty
        else {
            return nil
        }
        return url
    }

    private static func templateIcon(named symbolName: String) -> NSImage? {
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        image?.isTemplate = true
        return image
    }
}
