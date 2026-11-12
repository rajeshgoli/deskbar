import AppKit

extension NSImage {
    /// Scale image to target size
    func scaled(to size: NSSize) -> NSImage {
        let newImage = NSImage(size: size)
        newImage.lockFocus()
        self.draw(in: NSRect(origin: .zero, size: size),
                  from: NSRect(origin: .zero, size: self.size),
                  operation: .copy,
                  fraction: 1.0)
        newImage.unlockFocus()
        return newImage
    }

    /// Desaturate the image (for minimized/inactive states)
    func desaturated() -> NSImage {
        guard let cgImage = self.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let filter = CIFilter(name: "CIColorControls") else { return self }
        let ciImage = CIImage(cgImage: cgImage)
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(0.0, forKey: kCIInputSaturationKey)
        guard let output = filter.outputImage else { return self }
        let context = CIContext()
        guard let resultCG = context.createCGImage(output, from: output.extent) else { return self }
        return NSImage(cgImage: resultCG, size: self.size)
    }

    /// Apply alpha/transparency
    func withAlpha(_ alpha: CGFloat) -> NSImage {
        let newImage = NSImage(size: self.size)
        newImage.lockFocus()
        self.draw(in: NSRect(origin: .zero, size: self.size),
                  from: NSRect(origin: .zero, size: self.size),
                  operation: .copy,
                  fraction: alpha)
        newImage.unlockFocus()
        return newImage
    }

    /// Draw a notification dot overlay (top-right corner)
    func withBadgeDot(dotSize: CGFloat = 6, color: NSColor = .systemRed) -> NSImage {
        // Drawn on demand at whatever size the image is displayed, so the icon
        // stays sharp when the icon size setting scales it up. A bitmap made
        // with lockFocus would be fixed at the source icon's 32 pt.
        let baseSize = size
        return NSImage(size: baseSize, flipped: false) { rect in
            self.draw(in: rect)
            let scale = rect.width / max(baseSize.width, 1)
            let scaledDot = dotSize * scale
            let dotRect = NSRect(
                x: rect.maxX - scaledDot - scale,
                y: rect.maxY - scaledDot - scale,
                width: scaledDot,
                height: scaledDot
            )
            color.setFill()
            NSBezierPath(ovalIn: dotRect).fill()
            return true
        }
    }
}
