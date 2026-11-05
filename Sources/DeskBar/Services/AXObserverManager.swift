import AppKit
import ApplicationServices

/// Full discovery wins over title-only work in a coalesced notification burst.
struct AXRefreshBatch {
    private(set) var titleElements: [AXUIElement] = []
    private(set) var needsFullRefresh = false

    mutating func add(_ notification: CFString, element: AXUIElement) {
        guard !needsFullRefresh else { return }
        guard notification == kAXTitleChangedNotification as CFString,
              titleElements.count < 64 else {
            needsFullRefresh = true
            titleElements.removeAll()
            return
        }
        if !titleElements.contains(where: { CFEqual($0, element) }) {
            titleElements.append(element)
        }
    }
}

final class AXObserverManager {
    private weak var windowManager: WindowManager?
    private let debouncer = Debouncer()
    private var workspaceObservers: [NSObjectProtocol] = []
    private var observers: [pid_t: AXObserver] = [:]
    private var pendingRefresh = AXRefreshBatch()
    private static let installRetryDelay: TimeInterval = 1
    private static let maximumInstallAttempts = 60

    private let notificationNames: [CFString] = [
        kAXCreatedNotification as CFString,
        kAXUIElementDestroyedNotification as CFString,
        kAXWindowMiniaturizedNotification as CFString,
        kAXWindowDeminiaturizedNotification as CFString,
        kAXFocusedWindowChangedNotification as CFString,
        kAXMainWindowChangedNotification as CFString,
        kAXTitleChangedNotification as CFString,
        kAXWindowResizedNotification as CFString
    ]

    init(windowManager: WindowManager) {
        self.windowManager = windowManager
        registerWorkspaceObservers()
        installObserversForRunningApps()
    }

    deinit {
        workspaceObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)

        for observer in observers.values {
            CFRunLoopRemoveSource(
                CFRunLoopGetMain(),
                AXObserverGetRunLoopSource(observer),
                .defaultMode
            )
        }
    }

    private func registerWorkspaceObservers() {
        let notificationCenter = NSWorkspace.shared.notificationCenter

        workspaceObservers.append(
            notificationCenter.addObserver(
                forName: NSWorkspace.didLaunchApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard
                    let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                    application.activationPolicy == .regular
                else {
                    return
                }

                self?.installObserver(for: application)
            }
        )

        workspaceObservers.append(
            notificationCenter.addObserver(
                forName: NSWorkspace.didTerminateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard
                    let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                else {
                    return
                }

                self?.removeObserver(for: application.processIdentifier)
            }
        )
    }

    private func installObserversForRunningApps() {
        for application in NSWorkspace.shared.runningApplications where application.activationPolicy == .regular {
            installObserver(for: application)
        }
    }

    private func installObserver(for application: NSRunningApplication, attempt: Int = 0) {
        let pid = application.processIdentifier
        guard observers[pid] == nil, !application.isTerminated else {
            return
        }

        guard !AXUnresponsiveApplications.shared.shouldSkip(pid) else {
            scheduleInstallRetry(for: application, after: attempt)
            return
        }

        var observer: AXObserver?
        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        let error = AXObserverCreate(pid, observerCallback, &observer)

        guard error == .success, let observer else {
            return
        }

        let appElement = AXUIElementCreateApplication(pid)
        AccessibilityService.limitToBackgroundTimeout(appElement)
        for notification in notificationNames {
            let result = AXObserverAddNotification(observer, appElement, notification, context)
            AXUnresponsiveApplications.shared.record(result, for: pid)

            // An app that is still launching cannot answer yet. Each further registration
            // would wait out its own timeout, so retry the whole set once it responds.
            if AccessibilityService.isTransientEnumerationFailure(result) {
                scheduleInstallRetry(for: application, after: attempt)
                return
            }
        }

        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .defaultMode
        )

        observers[pid] = observer

        // Windows the app opened while it was not yet observable produced no notifications.
        if attempt > 0 {
            windowManager?.refresh()
        }
    }

    private func scheduleInstallRetry(for application: NSRunningApplication, after attempt: Int) {
        guard attempt < Self.maximumInstallAttempts else {
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.installRetryDelay) { [weak self] in
            self?.installObserver(for: application, attempt: attempt + 1)
        }
    }

    private func removeObserver(for pid: pid_t) {
        guard let observer = observers.removeValue(forKey: pid) else {
            return
        }

        CFRunLoopRemoveSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .defaultMode
        )
    }

    fileprivate func handleAXNotification(_ notification: CFString, element: AXUIElement) {
        if notification == kAXFocusedWindowChangedNotification as CFString ||
            notification == kAXMainWindowChangedNotification as CFString {
            windowManager?.notifyFocusMayHaveChanged()
        }

        pendingRefresh.add(notification, element: element)

        debouncer.debounce { [weak self] in
            guard let self else { return }
            let batch = self.pendingRefresh
            self.pendingRefresh = AXRefreshBatch()
            if batch.needsFullRefresh {
                self.windowManager?.refresh()
            } else {
                self.windowManager?.refreshTitles(for: batch.titleElements)
            }
        }
    }

    fileprivate func handleWindowResized(_ element: AXUIElement) {
        windowManager?.adjustWindowForTaskbar(element)
    }
}

private let observerCallback: AXObserverCallback = { _, element, notification, refcon in
    guard let refcon else {
        return
    }

    let manager = Unmanaged<AXObserverManager>.fromOpaque(refcon).takeUnretainedValue()

    if notification == kAXWindowResizedNotification as CFString {
        manager.handleWindowResized(element)
    }

    manager.handleAXNotification(notification, element: element)
}
