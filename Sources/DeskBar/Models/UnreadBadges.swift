import AppKit

/// Dock badge text per app, shared with the views that draw app icons.
///
/// `BadgeMonitor` fills `labels` from the Dock's accessibility tree; the
/// "Show unread counts on app icons" setting drives `showsCounts`. With it
/// off, icons keep the plain red dot.
enum UnreadBadges {
    static var showsCounts = false
    static var labels: [String: String] = [:]

    /// The size task icons are shown at: the "iconSize" preference when an
    /// icon size setting provides one, otherwise the 24 pt they have always
    /// been drawn at.
    static var displayedIconSize: CGFloat {
        (UserDefaults.standard.object(forKey: "iconSize") as? CGFloat) ?? 24
    }

    static let pillHeightRatio: CGFloat = 0.28
    static let minimumPillHeight: CGFloat = 10

    /// Pill height in the badged image's own coordinates, chosen so that on
    /// screen the pill is 28 % of the displayed icon and never under 10 pt.
    static func pillHeight(displayedIconSize: CGFloat, imageHeight: CGFloat) -> CGFloat {
        let onScreen = max(minimumPillHeight, displayedIconSize * pillHeightRatio)
        return onScreen * imageHeight / max(displayedIconSize, 1)
    }

    static func label(for bundleIdentifier: String?) -> String? {
        guard showsCounts, let bundleIdentifier else {
            return nil
        }
        return displayText(for: labels[bundleIdentifier])
    }

    /// Normalises Dock badge text: trims it, caps large counts at "99+" and
    /// treats an empty label as "no text" so the dot is drawn instead.
    static func displayText(for rawLabel: String?) -> String? {
        guard let text = rawLabel?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }
        if let count = Int(text) {
            return count > 99 ? "99+" : String(count)
        }
        return String(text.prefix(4))
    }
}

extension NSImage {
    /// Draws the badge the way the Dock does: the text in a red pill at the
    /// top-right corner when there is one, otherwise the existing dot.
    ///
    /// Group buttons show their window count at the top-right, so they pass
    /// `atLeadingCorner` to put the pill at the top-left instead.
    func withUnreadBadge(for bundleIdentifier: String?, atLeadingCorner: Bool = false) -> NSImage {
        guard let text = UnreadBadges.label(for: bundleIdentifier) else {
            return withBadgeDot()
        }
        return withBadgeLabel(text, atLeadingCorner: atLeadingCorner)
    }

    func withBadgeLabel(_ text: String, color: NSColor = .systemRed, atLeadingCorner: Bool = false) -> NSImage {
        // Drawn on demand at the size the image is displayed, so the icon and
        // the digits stay sharp at any icon size.
        NSImage(size: size, flipped: false) { rect in
            let displayedIconSize = UnreadBadges.displayedIconSize
            self.draw(in: rect)

            let pillHeight = UnreadBadges.pillHeight(displayedIconSize: displayedIconSize, imageHeight: rect.height)
            let font = NSFont.monospacedDigitSystemFont(ofSize: pillHeight * 0.7, weight: .semibold)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.white
            ]
            let textSize = (text as NSString).size(withAttributes: attributes)
            let pillWidth = min(rect.width, max(pillHeight, ceil(textSize.width + pillHeight * 0.5)))
            let pillRect = NSRect(
                x: atLeadingCorner ? rect.minX : rect.maxX - pillWidth,
                y: rect.maxY - pillHeight,
                width: pillWidth,
                height: pillHeight
            )

            color.setFill()
            NSBezierPath(roundedRect: pillRect, xRadius: pillHeight / 2, yRadius: pillHeight / 2).fill()
            // Centre the digits optically: put the cap height, not the line box,
            // in the middle of the pill. The drawing origin sits `descender`
            // below the baseline.
            let baselineY = pillRect.midY - font.capHeight / 2
            let textOrigin = NSPoint(
                x: pillRect.midX - textSize.width / 2,
                y: baselineY + font.descender
            )
            (text as NSString).draw(at: textOrigin, withAttributes: attributes)
            return true
        }
    }
}
