import AppKit
import Combine

/// Keeps a user's dismissal separate from automatic full-screen visibility changes.
final class TaskbarVisibilityController {
    private let panel: TaskbarPanel
    private let settings: TaskbarSettings
    private var scrollMonitor: Any?
    private var revealPanel: NSPanel?
    private let revealView = TaskbarRevealView()
    private var isAvailable = false
    private var settingsCancellable: AnyCancellable?
    private(set) var isManuallyHidden = false
    var visibilityDidChange: (() -> Void)?

    init(panel: TaskbarPanel, settings: TaskbarSettings) {
        self.panel = panel
        self.settings = settings
        revealView.reveal = { [weak self] in self?.show() }
        settingsCancellable = settings.$taskbarHideScrollDirection
            .dropFirst()
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] direction in
                if direction == .disabled { self?.show() }
            }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, event.window === self.panel,
                  Self.isHideScroll(deltaX: event.scrollingDeltaX, deltaY: event.scrollingDeltaY,
                                    isMomentum: !event.momentumPhase.isEmpty,
                                    isDirectionInverted: event.isDirectionInvertedFromDevice,
                                    direction: self.settings.taskbarHideScrollDirection),
                  let root = self.panel.contentView,
                  root.hitTest(root.convert(event.locationInWindow, from: nil)) != nil
            else { return event }
            self.hide()
            return nil
        }
    }

    deinit {
        if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
        revealPanel?.orderOut(nil)
    }

    static func isHideScroll(
        deltaX: CGFloat, deltaY: CGFloat, isMomentum: Bool,
        isDirectionInverted: Bool, direction: TaskbarHideScrollDirection
    ) -> Bool {
        guard !isMomentum, abs(deltaY) > abs(deltaX) else { return false }
        let physicalDeltaY = isDirectionInverted ? -deltaY : deltaY
        switch direction {
        case .disabled: return false
        case .down: return physicalDeltaY < 0
        case .up: return physicalDeltaY > 0
        }
    }

    func setAvailable(_ available: Bool) {
        isAvailable = available
        updateVisibility()
    }

    func hide() {
        guard isAvailable, !isManuallyHidden else { return }
        isManuallyHidden = true
        prepareRevealPanel()
        revealView.arm(pointerIsInside: revealPanel?.frame.contains(NSEvent.mouseLocation) ?? false)
        updateVisibility()
        visibilityDidChange?()
    }

    func show() {
        isManuallyHidden = false
        updateVisibility()
        visibilityDidChange?()
    }

    private func updateVisibility() {
        if isAvailable && !isManuallyHidden {
            revealPanel?.orderOut(nil)
            panel.orderFront(nil)
        } else {
            panel.orderOut(nil)
            if isAvailable && isManuallyHidden {
                prepareRevealPanel()
                revealPanel?.orderFront(nil)
            } else {
                revealPanel?.orderOut(nil)
            }
        }
    }

    private func prepareRevealPanel() {
        guard let screen = ScreenGeometry.screen(for: panel.displayID) else { return }
        let frame = NSRect(x: screen.frame.minX, y: screen.frame.minY,
                           width: screen.frame.width, height: 2)
        if let revealPanel {
            revealPanel.collectionBehavior = panel.collectionBehavior
            revealPanel.setFrame(frame, display: false)
            return
        }
        let edge = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                           backing: .buffered, defer: false)
        edge.level = panel.level
        edge.collectionBehavior = panel.collectionBehavior
        edge.hidesOnDeactivate = false
        edge.backgroundColor = .clear
        edge.isOpaque = false
        edge.hasShadow = false
        edge.acceptsMouseMovedEvents = true
        edge.contentView = revealView
        revealPanel = edge
    }
}

final class TaskbarRevealView: NSView {
    var reveal: (() -> Void)?
    private var isArmed = true
    private var tracking: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("Show DeskBar")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func arm(pointerIsInside: Bool) {
        // Hiding while already on the edge must not immediately reveal the bar again.
        isArmed = !pointerIsInside
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let tracking = NSTrackingArea(rect: .zero,
                                     options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                     owner: self, userInfo: nil)
        addTrackingArea(tracking)
        self.tracking = tracking
    }

    override func mouseEntered(with event: NSEvent) {
        if isArmed { reveal?() }
    }

    override func mouseExited(with event: NSEvent) {
        isArmed = true
    }

    override func mouseDown(with event: NSEvent) {
        reveal?()
    }

    override func accessibilityPerformPress() -> Bool {
        reveal?()
        return true
    }
}
