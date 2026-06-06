import AppKit
import CoreGraphics

struct SMTaskWindowPlanner {
    private struct BackedAgentTab {
        let annotation: SMAgentWindowAnnotation
        let sourceWindow: WindowInfo
    }

    static func scopedWindows(
        baseWindows: [WindowInfo],
        annotations: [SMAgentWindowAnnotation],
        terminalTabCountByWindowID: [CGWindowID: Int],
        showAgentTitles: Bool,
        frameProvider: (WindowInfo) -> CGRect?
    ) -> [WindowInfo] {
        let terminalWindows = baseWindows.filter {
            $0.bundleIdentifier == SMPluginService.terminalBundleIdentifier
        }
        let terminalWindowsByID = Dictionary(
            preservingFirstValues: terminalWindows.compactMap { window -> (CGWindowID, WindowInfo)? in
                guard let cgWindowID = window.cgWindowID else {
                    return nil
                }

                return (cgWindowID, window)
            }
        )
        let backedAgentTabs = annotations.compactMap { annotation -> BackedAgentTab? in
            guard
                let sourceWindow = matchingTerminalWindow(
                    for: annotation,
                    terminalWindows: terminalWindows,
                    terminalWindowsByID: terminalWindowsByID,
                    frameProvider: frameProvider
                )
            else {
                return nil
            }

            return BackedAgentTab(annotation: annotation, sourceWindow: sourceWindow)
        }

        guard !backedAgentTabs.isEmpty else {
            return baseWindows
        }

        let backedAgentTabsBySourceWindowID = Dictionary(
            grouping: backedAgentTabs,
            by: { $0.sourceWindow.id }
        )
        var scopedWindows: [WindowInfo] = []
        var emittedSourceWindowIDs = Set<String>()

        for window in baseWindows {
            guard window.bundleIdentifier == SMPluginService.terminalBundleIdentifier else {
                scopedWindows.append(window)
                continue
            }

            guard let tabs = backedAgentTabsBySourceWindowID[window.id] else {
                scopedWindows.append(window)
                continue
            }

            if terminalWindowHasNonAgentTabs(
                windowID: tabs.first?.sourceWindow.cgWindowID ?? tabs.first?.annotation.terminalWindowID,
                agentTabCount: tabs.count,
                terminalTabCountByWindowID: terminalTabCountByWindowID
            ) {
                scopedWindows.append(window)
            }

            scopedWindows.append(
                contentsOf: tabs.map {
                    virtualAgentWindow(
                        for: $0,
                        showAgentTitles: showAgentTitles
                    )
                }
            )
            emittedSourceWindowIDs.insert(window.id)
        }

        let unplacedAgentTabs = backedAgentTabs.filter {
            !emittedSourceWindowIDs.contains($0.sourceWindow.id)
        }
        scopedWindows.append(
            contentsOf: unplacedAgentTabs.map {
                virtualAgentWindow(
                    for: $0,
                    showAgentTitles: showAgentTitles
                )
            }
        )

        return scopedWindows
    }

    static func virtualWindowID(for annotation: SMAgentWindowAnnotation) -> String {
        "sm-agent:\(annotation.sessionID)"
    }

    private static func matchingTerminalWindow(
        for annotation: SMAgentWindowAnnotation,
        terminalWindows: [WindowInfo],
        terminalWindowsByID: [CGWindowID: WindowInfo],
        frameProvider: (WindowInfo) -> CGRect?
    ) -> WindowInfo? {
        if let sourceWindow = terminalWindowsByID[annotation.terminalWindowID] {
            return sourceWindow
        }

        guard let annotationFrame = annotation.terminalFrame else {
            return nil
        }

        return terminalWindows.first { window in
            guard let windowFrame = frameProvider(window) else {
                return false
            }

            return terminalFrame(annotationFrame, matches: windowFrame)
        }
    }

    private static func virtualAgentWindow(
        for tab: BackedAgentTab,
        showAgentTitles: Bool
    ) -> WindowInfo {
        let annotation = tab.annotation
        let sourceWindow = tab.sourceWindow

        return WindowInfo(
            pid: sourceWindow.pid,
            cgWindowID: nil,
            provisionalID: virtualWindowID(for: annotation),
            appName: sourceWindow.appName,
            title: showAgentTitles ? annotation.friendlyName : sourceWindow.title,
            icon: sourceWindow.icon,
            bundleIdentifier: sourceWindow.bundleIdentifier,
            isMinimized: sourceWindow.isMinimized,
            isHidden: sourceWindow.isHidden,
            isProvisional: true
        )
    }

    private static func terminalWindowHasNonAgentTabs(
        windowID: CGWindowID?,
        agentTabCount: Int,
        terminalTabCountByWindowID: [CGWindowID: Int]
    ) -> Bool {
        guard agentTabCount > 0 else {
            return false
        }

        guard
            let windowID,
            let terminalTabCount = terminalTabCountByWindowID[windowID]
        else {
            return true
        }

        return terminalTabCount > agentTabCount
    }

    private static func terminalFrame(_ lhs: CGRect, matches rhs: CGRect) -> Bool {
        let tolerance: CGFloat = 4
        return abs(lhs.minX - rhs.minX) <= tolerance &&
            abs(lhs.minY - rhs.minY) <= tolerance &&
            abs(lhs.width - rhs.width) <= tolerance &&
            abs(lhs.height - rhs.height) <= tolerance
    }
}
