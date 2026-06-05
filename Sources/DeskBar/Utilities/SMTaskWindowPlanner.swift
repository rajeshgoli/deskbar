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

        let agentTabCountBySourceWindowID = Dictionary(
            grouping: backedAgentTabs.compactMap { tab -> CGWindowID? in
                tab.sourceWindow.cgWindowID
            },
            by: { $0 }
        ).mapValues(\.count)
        let nonAgentWindows = baseWindows.filter { window in
            guard window.bundleIdentifier == SMPluginService.terminalBundleIdentifier else {
                return true
            }

            guard
                let cgWindowID = window.cgWindowID,
                agentTabCountBySourceWindowID[cgWindowID] != nil
            else {
                return true
            }

            return terminalWindowHasNonAgentTabs(
                windowID: cgWindowID,
                agentTabCount: agentTabCountBySourceWindowID[cgWindowID] ?? 0,
                terminalTabCountByWindowID: terminalTabCountByWindowID
            )
        }

        let virtualAgentWindows = backedAgentTabs.map { tab in
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

        return nonAgentWindows + virtualAgentWindows
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

    private static func terminalWindowHasNonAgentTabs(
        windowID: CGWindowID,
        agentTabCount: Int,
        terminalTabCountByWindowID: [CGWindowID: Int]
    ) -> Bool {
        guard agentTabCount > 0 else {
            return false
        }

        guard let terminalTabCount = terminalTabCountByWindowID[windowID] else {
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
