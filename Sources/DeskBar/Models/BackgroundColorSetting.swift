import AppKit

/// A colour stored in the defaults as "#RRGGBBAA" (sRGB).
struct StoredColor: Equatable {
    var red: CGFloat
    var green: CGFloat
    var blue: CGFloat
    var alpha: CGFloat

    static let black = StoredColor(red: 0, green: 0, blue: 0, alpha: 1)

    init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init?(hex: String) {
        var digits = hex.trimmingCharacters(in: .whitespaces)
        if digits.hasPrefix("#") {
            digits.removeFirst()
        }
        if digits.count == 6 {
            digits += "FF"
        }
        guard digits.count == 8, let value = UInt32(digits, radix: 16) else {
            return nil
        }

        red = CGFloat((value >> 24) & 0xFF) / 255
        green = CGFloat((value >> 16) & 0xFF) / 255
        blue = CGFloat((value >> 8) & 0xFF) / 255
        alpha = CGFloat(value & 0xFF) / 255
    }

    init(_ color: NSColor) {
        // A pattern colour has no sRGB equivalent; fall back to black built in
        // sRGB, since reading components of `.black` (grey space) would raise.
        let srgb = color.usingColorSpace(.sRGB) ?? NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
        self.init(red: srgb.redComponent, green: srgb.greenComponent, blue: srgb.blueComponent, alpha: srgb.alphaComponent)
    }

    var hex: String {
        func byte(_ component: CGFloat) -> UInt32 {
            UInt32((min(max(component, 0), 1) * 255).rounded())
        }
        let value = byte(red) << 24 | byte(green) << 16 | byte(blue) << 8 | byte(alpha)
        return String(format: "#%08X", value)
    }

    var nsColor: NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    /// Relative luminance, used to pick light or dark text over the colour.
    var isDark: Bool {
        0.2126 * red + 0.7152 * green + 0.0722 * blue < 0.5
    }
}
