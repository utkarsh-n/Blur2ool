import AppKit

// Tools/GenerateIcon.swift — Blur2ool's app icon (OWNER: SKEL), drawn with AppKit as AI Stuff/LosAlamosSimulator does.
// A Metro-styled glyph: the Gaussian's rings (1σ, 2σ, 3σ) in instrument cyan on recessed metal, a soft blurred light at
// the centre (the blur itself), tap dots on the axes sized by weight, and an amber probe mark. Tokens from
// Documentation/metro-station-design-tokens.json (surface.canvas, surface.metalLight/Dark, accent.instrumentCyan/Amber).
// usage: swiftc -O Tools/GenerateIcon.swift -o $TMPDIR/b2-icon && $TMPDIR/b2-icon App/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png
let side = 1024
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 4,
                              hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: side * 4, bitsPerPixel: 32)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
let canvas = NSColor(calibratedRed: 0.025, green: 0.042, blue: 0.058, alpha: 1)        // surface.canvas
let metalLight = NSColor(calibratedRed: 0.055, green: 0.073, blue: 0.090, alpha: 1)    // surface.metalLight
let metalDark = NSColor(calibratedRed: 0.021, green: 0.032, blue: 0.042, alpha: 1)     // surface.metalDark
let cyan = NSColor(calibratedRed: 0.32, green: 0.91, blue: 0.96, alpha: 1)             // accent.instrumentCyan
let amber = NSColor(calibratedRed: 1, green: 0.72, blue: 0.31, alpha: 1)               // accent.instrumentAmber
canvas.setFill()
NSBezierPath(rect: CGRect(x: 0, y: 0, width: side, height: side)).fill()
// Recessed metal face with the four-stop rim.
let face = NSBezierPath(roundedRect: CGRect(x: 92, y: 92, width: 840, height: 840), xRadius: 96, yRadius: 96)
NSGradient(starting: metalLight, ending: metalDark)!.draw(in: face, angle: -45)
face.lineWidth = 6
NSColor(calibratedWhite: 1, alpha: 0.16).setStroke()
face.stroke()
let center = CGPoint(x: 512, y: 512)
// The blurred light: a radial Gaussian falloff (the subject of the app).
let glow = NSGradient(colors: [cyan.withAlphaComponent(0.55), cyan.withAlphaComponent(0.18), cyan.withAlphaComponent(0.0)],
                      atLocations: [0, 0.45, 1], colorSpace: .deviceRGB)!
glow.draw(fromCenter: center, radius: 0, toCenter: center, radius: 300, options: [])
// Rings at 1σ, 2σ, 3σ.
for (k, alpha) in [(1, 0.95), (2, 0.65), (3, 0.38)] {
    let r = CGFloat(k) * 112
    let ring = NSBezierPath(ovalIn: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r))
    ring.lineWidth = 7
    cyan.withAlphaComponent(alpha).setStroke()
    ring.stroke()
}
// Tap dots on the horizontal axis, sized by the Gaussian weight.
for i in -6...6 {
    let x = center.x + CGFloat(i) * 56
    let w = exp(-Double(i * i) / (2 * 2.0 * 2.0))
    let r = CGFloat(6 + 16 * w)
    cyan.withAlphaComponent(0.85).setFill()
    NSBezierPath(ovalIn: CGRect(x: x - r, y: 190 - r, width: 2 * r, height: 2 * r)).fill()
}
// The probe: an amber crosshair with a gap, offset below the centre as on the Bench.
let probe = NSBezierPath()
probe.lineWidth = 8
for (dx, dy) in [(-1.0, 0.0), (1.0, 0.0), (0.0, -1.0), (0.0, 1.0)] {
    probe.move(to: CGPoint(x: center.x + 18 * dx, y: center.y - 70 + 18 * dy))
    probe.line(to: CGPoint(x: center.x + 70 * dx, y: center.y - 70 + 70 * dy))
}
amber.setStroke()
probe.stroke()
NSGraphicsContext.restoreGraphicsState()
// Flatten to an opaque image (no alpha channel): iOS app icons must not carry transparency.
let opaque = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
opaque.draw(bitmap.cgImage!, in: CGRect(x: 0, y: 0, width: side, height: side))
let png = NSBitmapImageRep(cgImage: opaque.makeImage()!).representation(using: .png, properties: [:])!
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
print("wrote \(CommandLine.arguments[1]) (\(side) × \(side))")
