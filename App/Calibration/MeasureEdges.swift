import SwiftUI
import CoreGraphics
import BlurCore

// OWNER: CALIBRATION (frozen signature, ARCHITECTURE §5.13; CAL §7 steps 1–3). Renders `blur(CalibrationEdgeView)` with
// ImageRenderer at the request's display scale and colour mode, one render per run-loop turn through CalibrationRenderGate,
// and reads the 16 centre rows back in the blur's working space (extended sRGB for `.nonLinear`, extended linear sRGB
// otherwise), exactly as Tools/calibrate/MeasurePSF.swift does: same canvas (CalibrationCanvas), same step view, same
// 16-row float readback, same analysis window and plateau normalisation. Returns one EdgeSamples per whole-device-pixel
// phase; the first also carries the 45° twin's ESF (rows aligned along the diagonal before averaging). The fit is
// BlurServices.psfFitter's job. SwiftUI + CoreGraphics only (UIKit only for the experimental on-screen path), so the
// macOS cross-check harness compiles this file unchanged.

@MainActor
public func measureEdges<Content: View>(_ request: CalibrationRequest,
                                       blur: @escaping (CalibrationEdgeView) -> Content) async -> [EdgeSamples] {
    let canvas = CalibrationCanvas(parameter: request.parameter, scale: request.displayScale)
    let gate = CalibrationRenderGate.shared
    var samples: [EdgeSamples] = []
    for phase in 0..<Swift.max(1, request.phases) {
        guard await gate.waitForTurn() else { return samples }
        let edge = CalibrationEdgeView(size: CGSize(width: canvas.width, height: canvas.height), edgeX: CGFloat(canvas.edgeX(phase: phase)))
        let (rows, _) = gate.timed { CalibrationEdgeReadback.centreRows(of: blur(edge), request: request, size: edge.size, rows: 16) }
        guard let rows else { continue }
        guard let s = CalibrationEdgeReadback.samples(profile: CalibrationEdgeReadback.mean(rows), edgePx: canvas.edgeX(phase: phase) * canvas.scale,
                                                      windowPx: canvas.windowPx, phase: phase, encoded: request.colourMode.readsEncoded) else { continue }
        samples.append(s)
    }
    // The 45° twin (phase 0): separable kernels show half the axis kurtosis along the diagonal, isotropic ones the same.
    guard !samples.isEmpty, await gate.waitForTurn() else { return samples }
    let size45 = CGSize(width: canvas.diagonalWidth, height: canvas.height)
    let pivot45 = (canvas.diagonalWidth / 2).rounded()
    let edge45 = CalibrationEdgeView(size: size45, edgeX: CGFloat(pivot45), angleDegrees: 45)
    let (rows45, _) = gate.timed { CalibrationEdgeReadback.centreRows(of: blur(edge45), request: request, size: size45, rows: 16) }
    let window45 = canvas.windowPx * 2.0.squareRoot()
    if let rows45, let aligned = CalibrationEdgeReadback.alignedDiagonal(rows45, pivotPx: pivot45 * canvas.scale, windowPx: window45),
       let s45 = CalibrationEdgeReadback.samples(profile: aligned.profile, edgePx: aligned.edgePx,
                                                 windowPx: window45, phase: 0, encoded: request.colourMode.readsEncoded) {
        samples[0].esf45 = s45.esf
    }
    return samples
}

/// Rendering and readback, shared by measureEdges, the shadow measurements and the cross-check harness.
enum CalibrationEdgeReadback {
    enum Channel { case rgbMean, alpha }

    static func colorMode(_ mode: CalibrationColourMode) -> ColorRenderingMode {
        switch mode {
        case .nonLinear: .nonLinear
        case .linear: .linear
        case .extendedLinear: .extendedLinear
        }
    }

    /// Renders `view` (size in points) along the request's path and returns its centre rows, each a profile of
    /// mean(R, G, B) or alpha per device pixel in the working space. nil if the render failed.
    @MainActor
    static func centreRows<V: View>(of view: V, request: CalibrationRequest, size: CGSize, rows: Int, channel: Channel = .rgbMean) -> [[Double]]? {
        let encoded = request.colourMode.readsEncoded
        let scale = CGFloat(request.displayScale)
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        renderer.colorMode = colorMode(request.colourMode)
        switch request.path {
        case .imageRendererRenderInto:
            var result: [[Double]]?
            renderer.render(rasterizationScale: scale) { pointSize, draw in
                let w = Int((pointSize.width * scale).rounded()), h = Int((pointSize.height * scale).rounded())
                guard let ctx = floatContext(width: w, height: h, encoded: encoded) else { return }
                ctx.scaleBy(x: scale, y: scale)
                draw(ctx)
                result = rowsFromContext(ctx, width: w, height: h, first: (h - rows) / 2, count: rows, channel: channel)
            }
            return result
        #if canImport(UIKit)
        case .drawHierarchyOnScreen:
            guard let image = CalibrationOnScreenCapture.capture(view, size: size, scale: scale) else { return nil }
            return centreRows(image, encoded: encoded, rows: rows, channel: channel)
        #endif
        default:
            guard var image = renderer.cgImage else { return nil }
            // CAL §4.19: in `.linear` mode the bytes are sRGB-encoded but tagged linear; re-tag them as sRGB (MeasurePSF).
            if request.colourMode == .linear, let srgb = CGColorSpace(name: CGColorSpace.sRGB), let t = image.copy(colorSpace: srgb) { image = t }
            return centreRows(image, encoded: encoded, rows: rows, channel: channel)
        }
    }

    static func floatContext(width w: Int, height h: Int, encoded: Bool) -> CGContext? {
        guard w > 0, h > 0, let cs = CGColorSpace(name: encoded ? CGColorSpace.extendedSRGB : CGColorSpace.extendedLinearSRGB) else { return nil }
        return CGContext(data: nil, width: w, height: h, bitsPerComponent: 32, bytesPerRow: w * 16, space: cs,
                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.floatComponents.rawValue
                            | CGBitmapInfo.byteOrder32Little.rawValue)
    }

    /// MeasurePSF's `centreRows`: draws the image so that its `rows` centre rows land in a `rows`-high float RGBA context in
    /// the requested space (CG converts colour; the extended spaces keep values outside 0…1), then reads each row.
    static func centreRows(_ image: CGImage, encoded: Bool, rows: Int, channel: Channel = .rgbMean) -> [[Double]]? {
        let w = image.width, h = image.height
        guard h >= rows, let ctx = floatContext(width: w, height: rows, encoded: encoded) else { return nil }
        ctx.setBlendMode(.copy)
        ctx.interpolationQuality = .none
        // CG's origin is bottom-left: placing the image at y = −(h − rows)/2 puts its centre rows in the context.
        ctx.draw(image, in: CGRect(x: 0, y: -CGFloat(h - rows) / 2, width: CGFloat(w), height: CGFloat(h)))
        return rowsFromContext(ctx, width: w, height: rows, first: 0, count: rows, channel: channel)
    }

    static func rowsFromContext(_ ctx: CGContext, width w: Int, height h: Int, first: Int, count: Int, channel: Channel) -> [[Double]]? {
        guard let data = ctx.data, first >= 0, first + count <= h else { return nil }
        let p = data.bindMemory(to: Float.self, capacity: ctx.bytesPerRow / 4 * h)
        let stride = ctx.bytesPerRow / 4
        return (first..<first + count).map { y in
            (0..<w).map { x in
                let i = y * stride + x * 4
                switch channel {
                case .rgbMean: return Double(p[i] + p[i + 1] + p[i + 2]) / 3
                case .alpha: return Double(p[i + 3])
                }
            }
        }
    }

    static func mean(_ rows: [[Double]]) -> [Double] {
        guard let first = rows.first else { return [] }
        var out = [Double](repeating: 0, count: first.count)
        for row in rows { for x in row.indices where x < out.count { out[x] += row[x] } }
        return out.map { $0 / Double(rows.count) }
    }

    /// The analysis window of MeasurePSF's fitEdge (±`windowPx` around the edge, clipped to the image), normalised by its
    /// first and last four pixels; the encoded midpoint from the two pixels either side of the edge, encoded with the
    /// sRGB OETF when the space is linear.
    static func samples(profile: [Double], edgePx: Double, windowPx: Double, phase: Int, encoded: Bool) -> EdgeSamples? {
        let x0 = Swift.max(0, Int(edgePx - windowPx)), x1 = Swift.min(profile.count, Int(edgePx + windowPx))
        guard x1 - x0 > 16 else { return nil }
        let v = Array(profile[x0..<x1])
        let lo = v.prefix(4).reduce(0, +) / 4, hi = v.suffix(4).reduce(0, +) / 4
        guard abs(hi - lo) > 1e-6 else { return nil }
        let q = v.map { ($0 - lo) / (hi - lo) }
        let edge = edgePx - Double(x0)
        let e = Int(edge.rounded())
        let mid = e > 0 && e < q.count ? (q[e - 1] + q[e]) / 2 : 0.5
        return EdgeSamples(esf: q, edgePosition: edge, phase: phase, encodedMidpoint: encoded ? mid : srgbEncode(mid))
    }

    /// The rows of a 45° edge shift by one device pixel per row. Each row's LSF centroid is measured inside the analysis
    /// window around the pivot (the canvas borders fade with opaque: false and must stay out of it), the slope fitted over
    /// the rows and snapped to ±1 px per row (so the direction is read from the data, not assumed), and the rows are
    /// shifted onto the middle row's edge and averaged. Returns the aligned profile and the middle row's edge position.
    static func alignedDiagonal(_ rows: [[Double]], pivotPx: Double, windowPx: Double) -> (profile: [Double], edgePx: Double)? {
        guard rows.count >= 2, let width = rows.first?.count, width > 32 else { return nil }
        let lower = Swift.max(1, Int(pivotPx - windowPx) - rows.count), upper = Swift.min(width, Int(pivotPx + windowPx) + rows.count)
        guard upper - lower > 16 else { return nil }
        func centroid(_ row: [Double]) -> Double? {
            var s0 = 0.0, s1 = 0.0
            for x in lower..<upper { let m = row[x] - row[x - 1]; s0 += m; s1 += m * Double(x) }
            return abs(s0) > 1e-6 ? s1 / s0 : nil
        }
        let centres = rows.map(centroid)
        let indexed = centres.enumerated().compactMap { i, c in c.map { (Double(i), $0) } }
        guard indexed.count >= 2 else { return nil }
        let my = indexed.map(\.0).reduce(0, +) / Double(indexed.count), mc = indexed.map(\.1).reduce(0, +) / Double(indexed.count)
        let slope = indexed.reduce(0) { $0 + ($1.0 - my) * ($1.1 - mc) } / Swift.max(1e-9, indexed.reduce(0) { $0 + pow($1.0 - my, 2) })
        let step = slope >= 0 ? 1 : -1
        let middle = rows.count / 2
        var out = [Double](repeating: 0, count: width)
        var counts = [Double](repeating: 0, count: width)
        for (j, row) in rows.enumerated() {
            let shift = step * (j - middle)
            for x in 0..<width {
                let source = x + shift
                if source >= 0 && source < width { out[x] += row[source]; counts[x] += 1 }
            }
        }
        let margin = rows.count
        let profile = (margin..<(width - margin)).map { out[$0] / Swift.max(1, counts[$0]) }
        guard let c = centres[middle] else { return nil }
        // The row centroid sits on LSF sample positions (pixel boundaries); the step itself is between those pixels.
        return (profile, c - Double(margin))
    }

    static func srgbEncode(_ v: Double) -> Double {
        v <= 0.0031308 ? v * 12.92 : 1.055 * pow(v, 1 / 2.4) - 0.055
    }
}
