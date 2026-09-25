// Draws the ccid app icon at 1024×1024.
// Usage: swift scripts/make-icon.swift <output.png>   (scripts/make-icon.sh wraps it into AppIcon.icns)
import AppKit

let output = CommandLine.arguments.dropFirst().first ?? "icon.png"
let canvas: CGFloat = 1024
let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

/// Apple's icon body is a continuous-corner square; a superellipse with n = 5 matches it closely.
func squircle(in rect: CGRect, n: CGFloat = 5) -> CGPath {
    let path = CGMutablePath()
    let steps = 1440
    for step in 0...steps {
        let t = CGFloat(step) / CGFloat(steps) * 2 * .pi
        let c = cos(t), s = sin(t)
        let point = CGPoint(
            x: rect.midX + rect.width / 2 * copysign(pow(abs(c), 2 / n), c),
            y: rect.midY + rect.height / 2 * copysign(pow(abs(s), 2 / n), s))
        step == 0 ? path.move(to: point) : path.addLine(to: point)
    }
    path.closeSubpath()
    return path
}

// The same four strokes as Sources/CCIDApp/Glyph.swift, in a unit square with y pointing up.
let strokes: [(CGPoint, CGPoint)] = [
    (CGPoint(x: 0.415, y: 0.86), CGPoint(x: 0.315, y: 0.14)),
    (CGPoint(x: 0.705, y: 0.86), CGPoint(x: 0.605, y: 0.14)),
    (CGPoint(x: 0.16, y: 0.635), CGPoint(x: 0.875, y: 0.635)),
    (CGPoint(x: 0.125, y: 0.365), CGPoint(x: 0.84, y: 0.365)),
]

guard let context = CGContext(
    data: nil, width: Int(canvas), height: Int(canvas), bitsPerComponent: 8, bytesPerRow: 0,
    space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
else { fatalError("no context") }

let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let shape = squircle(in: body)

// Shadow under the body.
context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -14), blur: 30, color: color(0x000000, 0.32))
context.addPath(shape)
context.setFillColor(color(0x18181B))
context.fillPath()
context.restoreGState()

// Graphite body, lit from above.
context.saveGState()
context.addPath(shape)
context.clip()
let bodyGradient = CGGradient(
    colorsSpace: sRGB, colors: [color(0x3A3A40), color(0x1C1C20), color(0x111114)] as CFArray,
    locations: [0, 0.55, 1])!
context.drawLinearGradient(
    bodyGradient, start: CGPoint(x: 512, y: body.maxY), end: CGPoint(x: 512, y: body.minY), options: [])
let sheen = CGGradient(
    colorsSpace: sRGB, colors: [color(0xFFFFFF, 0.10), color(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
context.drawRadialGradient(
    sheen, startCenter: CGPoint(x: 512, y: body.maxY + 40), startRadius: 0,
    endCenter: CGPoint(x: 512, y: body.maxY + 40), endRadius: 620, options: [])
// A hairline rim, brighter at the top edge.
context.addPath(shape)
context.setLineWidth(5)
context.replacePathWithStrokedPath()
context.clip()
let rim = CGGradient(
    colorsSpace: sRGB, colors: [color(0xFFFFFF, 0.22), color(0xFFFFFF, 0.04)] as CFArray, locations: [0, 1])!
context.drawLinearGradient(rim, start: CGPoint(x: 512, y: body.maxY), end: CGPoint(x: 512, y: body.minY), options: [])
context.restoreGState()

// The mark: a warm amber hash.
let box = CGRect(x: 257, y: 257, width: 510, height: 510)
let marks = CGMutablePath()
for (from, to) in strokes {
    marks.move(to: CGPoint(x: box.minX + from.x * box.width, y: box.minY + from.y * box.height))
    marks.addLine(to: CGPoint(x: box.minX + to.x * box.width, y: box.minY + to.y * box.height))
}
let glyph = marks.copy(strokingWithWidth: 64, lineCap: .round, lineJoin: .round, miterLimit: 10)

context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -8), blur: 22, color: color(0x000000, 0.45))
context.addPath(glyph)
context.setFillColor(color(0xFF8A3D))
context.fillPath()
context.restoreGState()

context.saveGState()
context.addPath(glyph)
context.clip()
let amber = CGGradient(
    colorsSpace: sRGB, colors: [color(0xFFC977), color(0xFF9A45), color(0xF26A21)] as CFArray,
    locations: [0, 0.5, 1])!
context.drawLinearGradient(amber, start: CGPoint(x: 512, y: box.maxY), end: CGPoint(x: 512, y: box.minY), options: [])
context.restoreGState()

guard let image = context.makeImage(),
      let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
else { fatalError("no image") }
try data.write(to: URL(fileURLWithPath: output))
print(output)
