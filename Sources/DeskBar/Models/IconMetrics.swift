import AppKit

/// Icon size and spacing shared by every taskbar button.
///
/// Views that are not handed a `TaskbarSettings` (launchers, group headers)
/// read these values directly and refresh when `didChange` is posted, which
/// `TaskbarSettings` does whenever the user moves either slider.
enum IconMetrics {
    static let iconSizeKey = "iconSize"
    static let itemSpacingKey = "itemSpacing"

    static let defaultIconSize: CGFloat = 24
    static let defaultItemSpacing: CGFloat = 8
    static let iconSizeRange: ClosedRange<CGFloat> = 16...64
    static let itemSpacingRange: ClosedRange<CGFloat> = 0...16

    static let didChange = Notification.Name("DeskBarIconMetricsDidChange")

    /// Room left on each side of the icon when a task button shows no title.
    static let iconOnlyHorizontalPadding: CGFloat = 6

    /// The sizes in effect, as `TaskbarSettings` stores them.
    static var iconSize: CGFloat {
        storedIconSize(in: .standard)
    }

    static var itemSpacing: CGFloat {
        storedItemSpacing(in: .standard)
    }

    static func storedIconSize(in defaults: UserDefaults) -> CGFloat {
        clamp(defaults.object(forKey: iconSizeKey) as? CGFloat ?? defaultIconSize, to: iconSizeRange)
    }

    static func storedItemSpacing(in defaults: UserDefaults) -> CGFloat {
        clamp(defaults.object(forKey: itemSpacingKey) as? CGFloat ?? defaultItemSpacing, to: itemSpacingRange)
    }

    static var launcherIconSize: CGFloat { launcherIconSize(forIconSize: iconSize) }
    static var launcherButtonWidth: CGFloat { launcherButtonWidth(forIconSize: iconSize) }
    static var groupHeaderWidth: CGFloat { groupHeaderWidth(forIconSize: iconSize) }
    static var iconOnlyTaskWidth: CGFloat { iconOnlyTaskWidth(forIconSize: iconSize) }
    static var rowHeight: CGFloat { rowHeight(forIconSize: iconSize) }

    /// Launchers have always drawn their icon 4 pt larger than task buttons.
    static func launcherIconSize(forIconSize iconSize: CGFloat) -> CGFloat { iconSize + 4 }
    static func launcherButtonWidth(forIconSize iconSize: CGFloat) -> CGFloat { launcherIconSize(forIconSize: iconSize) + 8 }
    static func groupHeaderWidth(forIconSize iconSize: CGFloat) -> CGFloat { iconSize + 16 }
    static func iconOnlyTaskWidth(forIconSize iconSize: CGFloat) -> CGFloat { iconSize + 2 * iconOnlyHorizontalPadding }

    /// Height of the band the buttons sit in, centred vertically in the bar.
    static func rowHeight(forIconSize iconSize: CGFloat) -> CGFloat {
        max(32, iconSize + 8)
    }

    /// The smallest taskbar that holds the button band: 32 pt, the slider's
    /// minimum, up to 24 pt icons, and the icon plus 8 pt above that.
    static func minimumTaskbarHeight(forIconSize iconSize: CGFloat) -> CGFloat {
        rowHeight(forIconSize: iconSize)
    }

    /// The lowest height the slider offers: what the smallest icons need.
    static var smallestTaskbarHeight: CGFloat {
        minimumTaskbarHeight(forIconSize: iconSizeRange.lowerBound)
    }

    /// The largest icon that fits a taskbar of the given height, the inverse
    /// of `minimumTaskbarHeight(forIconSize:)`.
    static func largestIconSize(forTaskbarHeight height: CGFloat) -> CGFloat {
        let margins = minimumTaskbarHeight(forIconSize: iconSizeRange.upperBound) - iconSizeRange.upperBound
        return clamp(max(height, smallestTaskbarHeight) - margins, to: iconSizeRange)
    }

    /// Source size for scaled app icons, large enough to stay sharp at the
    /// biggest slider value on a Retina display.
    static let iconRenderSize = NSSize(width: 128, height: 128)

    static func clamp(_ value: CGFloat, to range: ClosedRange<CGFloat>) -> CGFloat {
        min(max(value, range.lowerBound), range.upperBound)
    }
}

/// Keeps a view's size constraints in step with `IconMetrics`.
final class IconMetricsBinding {
    private var entries: [(constraint: NSLayoutConstraint, value: () -> CGFloat)] = []
    private weak var view: NSView?
    private var observer: NSObjectProtocol?

    init(view: NSView) {
        self.view = view
        observer = NotificationCenter.default.addObserver(
            forName: IconMetrics.didChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refresh()
        }
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func bind(_ constraint: NSLayoutConstraint, to value: @escaping () -> CGFloat) -> NSLayoutConstraint {
        constraint.constant = value()
        entries.append((constraint, value))
        return constraint
    }

    func refresh() {
        entries.forEach { $0.constraint.constant = $0.value() }
        view?.invalidateIntrinsicContentSize()
        view?.needsLayout = true
        view?.superview?.needsLayout = true
    }
}
