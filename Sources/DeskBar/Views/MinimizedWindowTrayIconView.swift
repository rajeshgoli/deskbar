import AppKit

/// A single minimized window parked in the running-app tray. Unlike `TrayIconView`, which stands
/// for a whole application, this represents one window: clicking it restores that window rather
/// than activating the app.
final class MinimizedWindowTrayIconView: NSView {
    static let iconSize: CGFloat = 24

    private let windowInfo: WindowInfo
    private let iconView = NSImageView()
    private let activate: (WindowInfo) -> Void

    init(windowInfo: WindowInfo, activate: @escaping (WindowInfo) -> Void) {
        self.windowInfo = windowInfo
        self.activate = activate
        super.init(frame: .zero)

        translatesAutoresizingMaskIntoConstraints = false
        toolTip = Self.tooltip(for: windowInfo)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(Self.tooltip(for: windowInfo))

        configureSubviews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: Self.iconSize, height: Self.iconSize)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        IconClickFeedback.show(on: iconView)
        activate(windowInfo)
    }

    private static func tooltip(for windowInfo: WindowInfo) -> String {
        let title = windowInfo.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = title.isEmpty ? windowInfo.appName : "\(windowInfo.appName) — \(title)"
        return "\(name) (minimized)"
    }

    private func configureSubviews() {
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.wantsLayer = true
        iconView.imageScaling = .scaleProportionallyUpOrDown
        // Desaturated to read as parked rather than running, matching the minimized task button.
        iconView.image = windowInfo.icon?
            .scaled(to: NSSize(width: Self.iconSize, height: Self.iconSize))
            .desaturated()
        iconView.alphaValue = 0.75

        addSubview(iconView)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Self.iconSize),
            heightAnchor.constraint(equalToConstant: Self.iconSize),
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor),
            iconView.trailingAnchor.constraint(equalTo: trailingAnchor),
            iconView.topAnchor.constraint(equalTo: topAnchor),
            iconView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
}
