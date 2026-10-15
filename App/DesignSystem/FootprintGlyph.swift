import SwiftUI
import BlurCore

// OWNER: METRO-COMPONENTS (frozen initialiser, ARCHITECTURE §5.14; SPEC §4.1.2 "Glyph", §4.1.3 "Kernel well face").
// A blur's 2-D footprint drawn from its GlyphSpec in instrument cyan on recessed metal: the blur strip (44 pt), the kernel
// well's face (88 pt, under the fixed lens) and catalog rows. Every GlyphKind has its own drawing; `values` are the
// kind's numbers (GlyphSpec doc): rings → radii in σ (default 1 · 2 · 3); polygon → sides, rotation°; rays → count;
// arcs → count; segment / comet → angle°; ellipse → aspect, angle°; diagonalTaps → Kawase offsets (default 0 1 2 2 3);
// pyramid → levels; grid → cells per side; dots → count. Missing numbers fall back to the defaults in `GlyphDefaults`.
// Selected (strip): cyan fill 0.08 + border 0.35 AND a 2-pt underline (colour plus shape, Metro §17). Decorative for
// VoiceOver: the host labels the control that contains it.
public struct FootprintGlyph: View {
    private let glyph: GlyphSpec
    private let size: CGFloat
    private let isSelected: Bool
    @Environment(\.colorSchemeContrast) private var contrast

    public init(_ glyph: GlyphSpec, size: CGFloat = 44, isSelected: Bool = false) {
        self.glyph = glyph; self.size = size; self.isSelected = isSelected
    }

    /// A short name for each kind (gallery engravings, VoiceOver of hosts that want it).
    nonisolated public static func name(_ kind: GlyphKind) -> String {
        switch kind {
        case .rings: "RINGS"
        case .square: "SQUARE"
        case .squareCorners: "SAT"
        case .tent: "TENT"
        case .disc: "DISC"
        case .polygon: "POLYGON"
        case .rays: "RAYS"
        case .arcs: "ARCS"
        case .segment: "SEGMENT"
        case .ellipse: "ELLIPSE"
        case .diagonalTaps: "KAWASE"
        case .pyramid: "PYRAMID"
        case .notchedRing: "ADAPTIVE"
        case .dashedCircle: "SYSTEM"
        case .cross: "CROSS"
        case .wave: "WAVE"
        case .grid: "GRID"
        case .comet: "COMET"
        case .squiggle: "SHAKE"
        case .dots: "DOTS"
        case .sun: "SUN"
        case .spectrum: "SPECTRUM"
        case .diamond: "DIAMOND"
        case .none: "NONE"
        }
    }

    private var corner: CGFloat { InstrumentMetrics.tileRadius * Swift.max(1, size / 44) }

    public var body: some View {
        Canvas { context, canvasSize in
            FootprintDrawing(glyph: glyph, size: canvasSize, increased: contrast == .increased).draw(in: &context)
        }
        .frame(width: size, height: size)
        .background {
            RoundedRectangle(cornerRadius: corner)
                .fill(isSelected ? InstrumentPalette.actionCyan.opacity(InstrumentOpacity.tileActiveFill) : .clear)
                .background(InstrumentPalette.metalDark, in: .rect(cornerRadius: corner))
        }
        .overlay {
            // Recessed metal: dark upper edge, faint lit lower edge (Metro §6 "Metal detail is strongest at boundaries").
            RoundedRectangle(cornerRadius: corner)
                .strokeBorder(LinearGradient(colors: [.black.opacity(0.55), .white.opacity(0.07)], startPoint: .top, endPoint: .bottom),
                              lineWidth: InstrumentMetrics.panelStroke)
        }
        .overlay {
            RoundedRectangle(cornerRadius: corner)
                .strokeBorder(isSelected ? InstrumentPalette.actionCyan.opacity(InstrumentOpacity.tileActiveBorder)
                                         : .white.opacity(contrast == .increased ? InstrumentOpacity.panelBorderIncreasedContrast
                                                                                 : InstrumentOpacity.tileIdleBorder),
                              lineWidth: InstrumentMetrics.panelStroke)
        }
        .overlay(alignment: .bottom) {
            if isSelected {
                Capsule().fill(InstrumentPalette.actionCyan)
                    .frame(width: size * 0.36, height: InstrumentMetrics.subdivisionMark)
                    .padding(.bottom, 2)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Default numbers per kind when a GlyphSpec carries none.
enum GlyphDefaults {
    static let rings: [Double] = [1, 2, 3]
    static let polygonSides = 6.0
    static let rays = 12.0
    static let arcs = 3.0
    static let ellipseAspect = 0.5
    static let kawaseOffsets: [Double] = [0, 1, 2, 2, 3]
    static let pyramidLevels = 4.0
    static let gridCells = 4.0
    static let dots = 22.0
}

/// The drawing of every GlyphKind (pure; one place, so the strip, the well and the catalog always agree).
struct FootprintDrawing {
    let glyph: GlyphSpec
    let size: CGSize
    let increased: Bool

    private var c: CGPoint { CGPoint(x: size.width / 2, y: size.height / 2) }
    private var r: CGFloat { Swift.min(size.width, size.height) * 0.36 }
    private var lw: CGFloat { Swift.max(1, Swift.min(size.width, size.height) / 44) }
    private var cyan: Color { InstrumentPalette.instrumentCyan }
    private func value(_ i: Int, _ fallback: Double) -> Double {
        i < glyph.values.count && glyph.values[i].isFinite ? glyph.values[i] : fallback
    }
    private func point(_ radius: CGFloat, _ degrees: Double) -> CGPoint {
        let a = degrees * .pi / 180
        return CGPoint(x: c.x + radius * cos(a), y: c.y + radius * sin(a))
    }
    private func circle(_ radius: CGFloat, at p: CGPoint? = nil) -> Path {
        let o = p ?? c
        return Path(ellipseIn: CGRect(x: o.x - radius, y: o.y - radius, width: 2 * radius, height: 2 * radius))
    }

    func draw(in context: inout GraphicsContext) {
        let ink = GraphicsContext.Shading.color(cyan)
        let faint = GraphicsContext.Shading.color(cyan.opacity(increased ? 0.6 : 0.35))
        switch glyph.kind {
        case .rings:
            // Gaussian: rings at 1σ, 2σ, 3σ; tap dots on both axes sized by weight.
            let radii = glyph.values.isEmpty ? GlyphDefaults.rings : glyph.values
            let maxR = radii.max() ?? 3
            for (k, v) in radii.sorted().enumerated() {
                context.stroke(circle(r * CGFloat(v / maxR)), with: .color(cyan.opacity(1 - 0.22 * Double(k))), lineWidth: lw)
            }
            let sigma = r / CGFloat(maxR)
            for step in -6...6 {
                let x = CGFloat(step) * r / 6
                let w = exp(-Double(x * x) / Double(2 * sigma * sigma))
                let d = Swift.max(0.6, 2.4 * lw * CGFloat(w))
                context.fill(circle(d / 2, at: CGPoint(x: c.x + x, y: c.y)), with: ink)
                if step != 0 { context.fill(circle(d / 2, at: CGPoint(x: c.x, y: c.y + x)), with: ink) }
            }
        case .square:
            let rect = CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)
            context.fill(Path(rect), with: .color(cyan.opacity(0.12)))
            context.stroke(Path(rect), with: ink, lineWidth: lw)
        case .squareCorners:
            let rect = CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)
            context.stroke(Path(rect), with: ink, lineWidth: lw)
            for p in [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                      CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY)] {
                context.fill(circle(2 * lw, at: p), with: ink)
            }
        case .tent:
            let base = c.y + r * 0.55
            context.stroke(Path(CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: faint, lineWidth: lw * 0.6)
            var tent = Path()
            tent.move(to: CGPoint(x: c.x - r, y: base))
            tent.addLine(to: CGPoint(x: c.x, y: c.y - r * 0.75))
            tent.addLine(to: CGPoint(x: c.x + r, y: base))
            var fill = tent; fill.closeSubpath()
            context.fill(fill, with: .color(cyan.opacity(0.14)))
            context.stroke(tent, with: ink, style: StrokeStyle(lineWidth: lw, lineJoin: .round))
            var line = Path(); line.move(to: CGPoint(x: c.x - r, y: base)); line.addLine(to: CGPoint(x: c.x + r, y: base))
            context.stroke(line, with: faint, lineWidth: lw * 0.6)
        case .disc:
            context.fill(circle(r), with: .color(cyan.opacity(0.22)))
            context.stroke(circle(r), with: ink, lineWidth: lw)
        case .polygon:
            let sides = Swift.max(3, Int(value(0, GlyphDefaults.polygonSides).rounded()))
            let rotation = value(1, 0) - 90
            let vertices = (0..<sides).map { point(r, rotation + Double($0) * 360 / Double(sides)) }
            var poly = Path(); poly.addLines(vertices); poly.closeSubpath()
            context.fill(poly, with: .color(cyan.opacity(0.12)))
            // The n-gon split into rhombi: faint lines from the centre to alternate vertices (SPEC §4.1.3).
            var spokes = Path()
            for (i, v) in vertices.enumerated() where i % 2 == 0 || sides % 2 == 1 { spokes.move(to: c); spokes.addLine(to: v) }
            context.stroke(spokes, with: faint, lineWidth: lw * 0.6)
            context.stroke(poly, with: ink, style: StrokeStyle(lineWidth: lw, lineJoin: .round))
        case .rays:
            let count = Swift.max(4, Int(value(0, GlyphDefaults.rays).rounded()))
            for k in 0..<count {
                let a = Double(k) * 360 / Double(count) - 90
                var ray = Path(); ray.move(to: point(r * 0.32, a)); ray.addLine(to: point(r, a))
                context.stroke(ray, with: .linearGradient(Gradient(colors: [cyan.opacity(0.25), cyan]),
                                                          startPoint: point(r * 0.32, a), endPoint: point(r, a)),
                               style: StrokeStyle(lineWidth: lw, lineCap: .round))
            }
            context.fill(circle(2 * lw), with: ink)
        case .arcs:
            let count = Swift.max(1, Int(value(0, GlyphDefaults.arcs).rounded()))
            for k in 0..<count {
                let radius = r * CGFloat(k + 1) / CGFloat(count)
                let start = -90 + Double(k) * 47
                var arc = Path()
                arc.addArc(center: c, radius: radius, startAngle: .degrees(start), endAngle: .degrees(start + 70), clockwise: false)
                var arc2 = Path()
                arc2.addArc(center: c, radius: radius, startAngle: .degrees(start + 180), endAngle: .degrees(start + 250), clockwise: false)
                context.stroke(arc, with: .color(cyan.opacity(1 - 0.18 * Double(k))), style: StrokeStyle(lineWidth: lw, lineCap: .round))
                context.stroke(arc2, with: .color(cyan.opacity(1 - 0.18 * Double(k))), style: StrokeStyle(lineWidth: lw, lineCap: .round))
            }
            context.fill(circle(1.6 * lw), with: ink)
        case .segment:
            // A hard-ended line: butt caps and perpendicular end ticks (motion blur's box along a line).
            let a = value(0, 0)
            let p0 = point(r, a + 180), p1 = point(r, a)
            var line = Path(); line.move(to: p0); line.addLine(to: p1)
            context.stroke(line, with: ink, style: StrokeStyle(lineWidth: 1.6 * lw, lineCap: .butt))
            for p in [p0, p1] {
                let n = CGPoint(x: cos((a + 90) * .pi / 180) * 3.5 * lw, y: sin((a + 90) * .pi / 180) * 3.5 * lw)
                var tick = Path(); tick.move(to: CGPoint(x: p.x - n.x, y: p.y - n.y)); tick.addLine(to: CGPoint(x: p.x + n.x, y: p.y + n.y))
                context.stroke(tick, with: ink, lineWidth: lw)
            }
        case .ellipse:
            // Anisotropic Gaussian: two soft-ended contours at 1σ and 2σ along the rotated major axis.
            let aspect = CGFloat(Swift.min(1, Swift.max(0.1, value(0, GlyphDefaults.ellipseAspect))))
            var e = context
            e.translateBy(x: c.x, y: c.y)
            e.rotate(by: .degrees(value(1, 0)))
            for (k, f) in [CGFloat(1), 0.55].enumerated() {
                let rect = CGRect(x: -r * f, y: -r * f * aspect, width: 2 * r * f, height: 2 * r * f * aspect)
                if k == 1 { e.fill(Path(ellipseIn: rect), with: .color(cyan.opacity(0.16))) }
                e.stroke(Path(ellipseIn: rect), with: .color(cyan.opacity(k == 0 ? 0.6 : 1)), lineWidth: lw)
            }
        case .diagonalTaps:
            // Kawase: the four diagonal taps of each pass at offset o + 0.5; the last pass amber.
            let offsets = glyph.values.isEmpty ? GlyphDefaults.kawaseOffsets : glyph.values
            let reach = (offsets.max() ?? 3) + 0.5
            for (k, o) in offsets.enumerated() {
                let d = r * CGFloat((o + 0.5) / reach)
                let last = k == offsets.count - 1
                let colour = last ? InstrumentPalette.instrumentAmber : cyan.opacity(0.45 + 0.4 * Double(k) / Double(Swift.max(1, offsets.count - 1)))
                for (sx, sy) in [(-1.0, -1.0), (1, -1), (-1, 1), (1, 1)] {
                    context.fill(circle(1.5 * lw, at: CGPoint(x: c.x + CGFloat(sx) * d, y: c.y + CGFloat(sy) * d)), with: .color(colour))
                }
            }
            context.stroke(circle(1.2 * lw), with: faint, lineWidth: lw * 0.6)
        case .pyramid:
            // A mip chain: each level half the size of the last, stacked from the top-leading corner.
            let levels = Swift.max(1, Int(value(0, GlyphDefaults.pyramidLevels).rounded()))
            var side = 2 * r
            let origin = CGPoint(x: c.x - r, y: c.y - r)
            for k in 0..<levels {
                let rect = CGRect(x: origin.x, y: origin.y, width: side, height: side)
                context.fill(Path(rect), with: .color(cyan.opacity(0.05 + 0.05 * Double(k))))
                context.stroke(Path(rect), with: .color(cyan.opacity(1 - 0.15 * Double(k))), lineWidth: lw)
                side /= 2
            }
        case .notchedRing:
            // Adaptive filters: a ring with a notch (the weights depend on the data).
            var ring = Path()
            ring.addArc(center: c, radius: r, startAngle: .degrees(-62), endAngle: .degrees(242), clockwise: false)
            context.stroke(ring, with: ink, style: StrokeStyle(lineWidth: lw, lineCap: .round))
            var notch = Path(); notch.move(to: point(r * 0.62, -90)); notch.addLine(to: point(r * 1.05, -90))
            context.stroke(notch, with: ink, style: StrokeStyle(lineWidth: lw, lineCap: .round))
            context.fill(circle(1.4 * lw), with: faint)
        case .dashedCircle:
            // System materials: a dashed circle (the kernel is not exposed).
            context.stroke(circle(r), with: ink, style: StrokeStyle(lineWidth: lw, dash: [3 * lw, 2.2 * lw]))
            context.stroke(circle(r * 0.55), with: faint, style: StrokeStyle(lineWidth: lw * 0.6, dash: [2 * lw, 2 * lw]))
        case .cross:
            for horizontal in [true, false] {
                let rect = horizontal ? CGRect(x: c.x - r, y: c.y - 1.6 * lw, width: 2 * r, height: 3.2 * lw)
                                      : CGRect(x: c.x - 1.6 * lw, y: c.y - r, width: 3.2 * lw, height: 2 * r)
                context.fill(Path(roundedRect: rect, cornerRadius: 1.6 * lw), with: .color(cyan.opacity(0.85)))
            }
        case .wave:
            var wave = Path()
            for i in 0...48 {
                let t = Double(i) / 48
                let p = CGPoint(x: c.x - r + CGFloat(t) * 2 * r, y: c.y - r * 0.55 * CGFloat(sin(t * 3 * .pi)) * CGFloat(1 - 0.5 * t))
                if i == 0 { wave.move(to: p) } else { wave.addLine(to: p) }
            }
            var axis = Path(); axis.move(to: CGPoint(x: c.x - r, y: c.y)); axis.addLine(to: CGPoint(x: c.x + r, y: c.y))
            context.stroke(axis, with: faint, lineWidth: lw * 0.6)
            context.stroke(wave, with: ink, style: StrokeStyle(lineWidth: lw, lineCap: .round, lineJoin: .round))
        case .grid:
            let n = Swift.max(2, Int(value(0, GlyphDefaults.gridCells).rounded()))
            let cell = 2 * r / CGFloat(n)
            for i in 0..<n {
                for j in 0..<n {
                    let rect = CGRect(x: c.x - r + CGFloat(i) * cell, y: c.y - r + CGFloat(j) * cell, width: cell, height: cell)
                    let level = 0.10 + 0.5 * Double((i * 7 + j * 3) % n) / Double(n)
                    context.fill(Path(rect.insetBy(dx: 0.5 * lw, dy: 0.5 * lw)), with: .color(cyan.opacity(level)))
                }
            }
            context.stroke(Path(CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: ink, lineWidth: lw)
        case .comet:
            // Velocity motion blur: a bright head with a tail that fades against the motion.
            let a = value(0, -30)
            let head = point(r * 0.62, a)
            let tail = point(r, a + 180)
            var trail = Path(); trail.move(to: tail); trail.addLine(to: head)
            context.stroke(trail, with: .linearGradient(Gradient(colors: [cyan.opacity(0), cyan]), startPoint: tail, endPoint: head),
                           style: StrokeStyle(lineWidth: 3.2 * lw, lineCap: .round))
            context.fill(circle(2.6 * lw, at: head), with: ink)
        case .squiggle:
            // Camera shake: a deterministic hand-held path.
            let pts: [(Double, Double)] = [(-0.9, 0.1), (-0.6, -0.5), (-0.3, 0.2), (-0.05, -0.65), (0.2, 0.05), (0.45, -0.35),
                                           (0.3, 0.55), (0.65, 0.3), (0.85, 0.75)]
            var path = Path()
            for (i, p) in pts.enumerated() {
                let q = CGPoint(x: c.x + CGFloat(p.0) * r, y: c.y + CGFloat(p.1) * r)
                if i == 0 { path.move(to: q) } else {
                    let prev = pts[i - 1]
                    let control = CGPoint(x: c.x + CGFloat((prev.0 + p.0) / 2) * r, y: c.y + CGFloat(prev.1) * r)
                    path.addQuadCurve(to: q, control: control)
                }
            }
            context.stroke(path, with: ink, style: StrokeStyle(lineWidth: lw, lineCap: .round, lineJoin: .round))
        case .dots:
            // Stochastic sampling: a golden-angle scatter inside the disc.
            let n = Swift.max(6, Int(value(0, GlyphDefaults.dots).rounded()))
            for k in 0..<n {
                let radius = r * CGFloat((Double(k) + 0.5) / Double(n)).squareRoot()
                let p = point(radius, Double(k) * 137.507764)
                context.fill(circle(1.25 * lw, at: p), with: .color(cyan.opacity(0.5 + 0.5 * Double(k % 3) / 2)))
            }
            context.stroke(circle(r), with: faint, lineWidth: lw * 0.6)
        case .sun:
            // Bloom and god rays: a bright core with short rays.
            context.fill(circle(r * 0.34), with: .radialGradient(Gradient(colors: [cyan, cyan.opacity(0.25)]), center: c,
                                                                 startRadius: 0, endRadius: r * 0.34))
            for k in 0..<8 {
                let a = Double(k) * 45 - 90
                var ray = Path(); ray.move(to: point(r * 0.5, a)); ray.addLine(to: point(k % 2 == 0 ? r : r * 0.8, a))
                context.stroke(ray, with: ink, style: StrokeStyle(lineWidth: lw, lineCap: .round))
            }
        case .spectrum:
            // Frequency-domain filters: the frequency plane, its DC point and the cut-off circle.
            var axes = Path()
            axes.move(to: CGPoint(x: c.x - r, y: c.y)); axes.addLine(to: CGPoint(x: c.x + r, y: c.y))
            axes.move(to: CGPoint(x: c.x, y: c.y - r)); axes.addLine(to: CGPoint(x: c.x, y: c.y + r))
            context.stroke(axes, with: faint, lineWidth: lw * 0.6)
            context.fill(circle(r * 0.6), with: .radialGradient(Gradient(colors: [cyan.opacity(0.35), cyan.opacity(0.05)]), center: c,
                                                                startRadius: 0, endRadius: r * 0.6))
            context.stroke(circle(r * 0.6), with: ink, lineWidth: lw)
            context.fill(circle(1.6 * lw), with: .color(InstrumentPalette.instrumentAmber))
        case .diamond:
            var d = Path()
            d.addLines([CGPoint(x: c.x, y: c.y - r), CGPoint(x: c.x + r, y: c.y), CGPoint(x: c.x, y: c.y + r), CGPoint(x: c.x - r, y: c.y)])
            d.closeSubpath()
            context.fill(d, with: .color(cyan.opacity(0.12)))
            context.stroke(d, with: ink, style: StrokeStyle(lineWidth: lw, lineJoin: .round))
        case .none:
            var dash = Path(); dash.move(to: CGPoint(x: c.x - r * 0.3, y: c.y)); dash.addLine(to: CGPoint(x: c.x + r * 0.3, y: c.y))
            context.stroke(dash, with: .color(InstrumentPalette.secondaryInk), style: StrokeStyle(lineWidth: lw, lineCap: .round))
        }
    }
}
