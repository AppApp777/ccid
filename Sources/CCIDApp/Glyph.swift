import AppKit

/// The ccid mark: a hash, drawn by hand so the menu bar and the app icon share one shape.
/// `scripts/make-icon.swift` draws the same four strokes.
enum Glyph {
    /// Stroke ends in a unit square, y pointing up.
    static let strokes: [(CGPoint, CGPoint)] = [
        (CGPoint(x: 0.415, y: 0.86), CGPoint(x: 0.315, y: 0.14)),
        (CGPoint(x: 0.705, y: 0.86), CGPoint(x: 0.605, y: 0.14)),
        (CGPoint(x: 0.16, y: 0.635), CGPoint(x: 0.875, y: 0.635)),
        (CGPoint(x: 0.125, y: 0.365), CGPoint(x: 0.84, y: 0.365)),
    ]

    static func menuBarImage() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let box = rect.insetBy(dx: 2, dy: 2)
            let path = NSBezierPath()
            path.lineWidth = 1.75
            path.lineCapStyle = .round
            for (from, to) in strokes {
                path.move(to: NSPoint(x: box.minX + from.x * box.width, y: box.minY + from.y * box.height))
                path.line(to: NSPoint(x: box.minX + to.x * box.width, y: box.minY + to.y * box.height))
            }
            NSColor.black.setStroke()
            path.stroke()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "ccid"
        return image
    }
}
