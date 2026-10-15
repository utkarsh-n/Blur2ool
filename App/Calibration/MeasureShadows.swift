import SwiftUI
import QuartzCore
import CoreGraphics
import BlurCore

// OWNER: CALIBRATION (SPEC §13.1 shadow rows; CAL §3.1 "shadow band", §5.5). Shadows blur an alpha mask, so the edge is
// the shadow's own rising edge, read from ALPHA: an opaque white band sits left of the analysis window and casts a black
// shadow (opacity 1) offset to the right, whose left edge lands on the window's centre, far from the band and from the
// shadow's falling edge. The three on-device shadow APIs:
//   SwiftUI .shadow(radius:)       ImageRenderer.cgImage at the display scale                 (OFFSCREEN)
//   CALayer.shadowRadius            CALayer.render(in:) — Core Animation's software path     (OFFSCREEN; on screen INFERRED)
//   CGContext.setShadow(blur:)      an offscreen float CGContext, in device pixels (scale 1)
// Same canvas rule, phases and normalisation as measureEdges; one render per run-loop turn through CalibrationRenderGate.

/// Geometry (points): band [margin, margin + 2W), shadow edge E = margin + 3W + 2 + phase/scale, canvas E + 2W + margin.
struct CalibrationShadowLayout {
    var canvas: CalibrationCanvas
    var phase: Int
    var band: CGRect
    var edgeX: Double
    var size: CGSize
    var offsetX: Double { edgeX - Double(band.minX) }

    init(parameter: Double, scale: Double, phase: Int) {
        canvas = CalibrationCanvas(parameter: parameter, scale: scale)
        self.phase = phase
        let w = canvas.reach, m = canvas.margin
        edgeX = m + 3 * w + 2 + Double(phase) / scale
        band = CGRect(x: m, y: 0, width: 2 * w, height: canvas.height)
        size = CGSize(width: (m + 3 * w + 2 + 1 + 2 * w + m).rounded(.up), height: canvas.height)
    }
}

@MainActor
func measureShadowEdges(_ request: CalibrationRequest) async -> [EdgeSamples] {
    let gate = CalibrationRenderGate.shared
    var samples: [EdgeSamples] = []
    for phase in 0..<Swift.max(1, request.phases) {
        guard await gate.waitForTurn() else { return samples }
        let layout = CalibrationShadowLayout(parameter: request.parameter, scale: request.displayScale, phase: phase)
        let (rows, _) = gate.timed { shadowRows(request, layout: layout) }
        guard let rows,
              var s = CalibrationEdgeReadback.samples(profile: CalibrationEdgeReadback.mean(rows), edgePx: layout.edgeX * request.displayScale,
                                                      windowPx: layout.canvas.windowPx, phase: phase, encoded: true) else { continue }
        s.encodedMidpoint = nil      // an alpha mask has no blend space (CAL §5.5)
        samples.append(s)
    }
    return samples
}

@MainActor
private func shadowRows(_ request: CalibrationRequest, layout: CalibrationShadowLayout) -> [[Double]]? {
    let scale = CGFloat(request.displayScale)
    let p = CGFloat(request.parameter)
    switch request.subject {
    case .swiftUIShadow:
        let view = ZStack(alignment: .topLeading) {
            Color.clear
            Rectangle().fill(Color.white)
                .frame(width: layout.band.width, height: layout.band.height)
                .shadow(color: .black, radius: p, x: CGFloat(layout.offsetX), y: 0)
                .offset(x: layout.band.minX)
        }
        .frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
        return CalibrationEdgeReadback.centreRows(of: view, request: request, size: layout.size, rows: 16, channel: .alpha)
    case .caLayerShadow:
        let w = Int((layout.size.width * scale).rounded(.up)), h = Int((layout.size.height * scale).rounded(.up))
        guard let ctx = CalibrationEdgeReadback.floatContext(width: w, height: h, encoded: true) else { return nil }
        let root = CALayer()
        root.frame = CGRect(origin: .zero, size: layout.size)
        root.contentsScale = scale
        let band = CALayer()
        band.frame = layout.band
        band.contentsScale = scale
        band.backgroundColor = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
        band.shadowColor = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
        band.shadowOpacity = 1
        band.shadowRadius = p
        band.shadowOffset = CGSize(width: layout.offsetX, height: 0)
        root.addSublayer(band)
        ctx.scaleBy(x: scale, y: scale)
        root.render(in: ctx)
        return CalibrationEdgeReadback.rowsFromContext(ctx, width: w, height: h, first: (h - 16) / 2, count: 16, channel: .alpha)
    case .cgContextShadow:
        // CG shadow offsets and blur are in device space (not scaled by the CTM): the subject is measured in pixels.
        let w = Int((layout.size.width * scale).rounded(.up)), h = Int((layout.size.height * scale).rounded(.up))
        guard let ctx = CalibrationEdgeReadback.floatContext(width: w, height: h, encoded: true) else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        ctx.setShadow(offset: CGSize(width: layout.offsetX * Double(scale), height: 0), blur: p,
                      color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(layout.band)
        return CalibrationEdgeReadback.rowsFromContext(ctx, width: w, height: h, first: (h - 16) / 2, count: 16, channel: .alpha)
    default:
        return nil
    }
}

/// The border probe for SwiftUI .blur (CAL §5.1 item 6): a white square blurred inside transparent padding; the alpha of
/// its outermost column, and four device pixels outside its frame.
@MainActor
func probeBlurBorder(radius: Double, opaque: Bool, scale: Double) async -> CalibrationBorderFinding? {
    let gate = CalibrationRenderGate.shared
    guard await gate.waitForTurn() else { return nil }
    let side = Swift.max(64, (8 * radius).rounded(.up)), pad = Swift.max(16, (4 * radius).rounded(.up))
    let total = side + 2 * pad
    let view = Color.white.frame(width: side, height: side).blur(radius: radius, opaque: opaque)
        .frame(width: total, height: total)
    let request = CalibrationRequest(subject: .swiftUIBlur, path: .imageRendererCGImage, parameter: radius, displayScale: scale)
    let (rows, _) = gate.timed { CalibrationEdgeReadback.centreRows(of: view, request: request, size: CGSize(width: total, height: total), rows: 1, channel: .alpha) }
    guard let row = rows?.first else { return nil }
    let border = Int((pad * scale).rounded()), outside = border - 4
    guard outside >= 0, border < row.count else { return nil }
    return CalibrationBorderFinding(borderAlpha: row[border], outsideAlpha: row[outside], opaqueRequested: opaque)
}
